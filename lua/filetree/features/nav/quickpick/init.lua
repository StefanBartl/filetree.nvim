---@module 'filetree.features.nav.quickpick'
---@brief Numbered quick-pick mode: number the visible tree entries, open one by typing its number.
---@description
--- A temporary mode over the tree. `<leader>;` (or `:Filetree quickpick`) puts a
--- two-digit label on every visible entry; typing the number opens that entry.
--- `s`/`v`/`t` (before the first digit) choose split / vsplit / tab instead of
--- the plain edit, `c` cycles which entries carry a number (files and folders ->
--- files only -> folders only), and the number of a FOLDER expands or collapses
--- it and renumbers what is then visible. `<Esc>` or a short idle timeout ends
--- the mode and puts every key and every extmark back.
---
--- It is built on the adapter contract and nothing else -- no tree is parsed
--- here: `get_visible_nodes(nil, bufnr)` for the entries, `expand_node` /
--- `collapse_node` for folders, `open_file(path, mode)` for the open, and
--- `open_reveal` / `open_cwd` to bring the tree up when it is not open yet.
--- The numbering and the input state machine are pure and live in `logic.lua`;
--- the buffer-local keys, with exact restore, in `keys.lua`.
---
--- ### Lifecycle (one mode at a time)
---
---   start   open/reveal the tree if needed, wait until it has rendered, move
---           focus to it, install keys, autocmds, indicator and the idle timer
---   render  clear + redraw every label from a fresh `get_visible_nodes()` --
---           on start, on every key, on scroll, resize, expand/collapse and on
---           the adapter's own re-render. Never a patch of earlier extmarks.
---   cancel  `<Esc>`, the idle timeout, leaving the tree window, closing it, or
---           opening an entry: stop the timer, delete the autocmds, restore the
---           keys, clear the extmarks, close the indicator, return to the
---           window the mode was started from.
---
--- Opt-in: the two global triggers are a claim on the keyboard this plugin does
--- not make unasked.
---
--- Config (see `DEFAULTS` below for the annotated full list):
---   enabled, keymap, keymap_cwd, content, open_mode, width, timeout_ms,
---   silence_nvim_mappings, label_pos, indicator, indicator_position, keys,
---   hl_number, hl_typed, hl_indicator

local notify = require("filetree.util.notify").create("[filetree.quickpick]")
local bind = require("filetree.util.bind")
local au = require("filetree.util.autocmd")
local bufutil = require("filetree.util.buffer")
local window = require("filetree.util.window")
local lib_debounce = require("lib.nvim.debounce")
local logic = require("filetree.features.nav.quickpick.logic")
local keys = require("filetree.features.nav.quickpick.keys")

local uv = vim.uv or vim.loop

local M = {}

M.logic = logic

---Defaults. A literal on purpose: `TESTS/config_schema.lua` evaluates it and
---checks `M.SCHEMA` accepts every value in it.
---@type FiletreeQuickpickConfig
local DEFAULTS = {
  enabled = false,

  -- Global triggers. `keymap` brings the tree up on the current file's folder
  -- (a count goes up that many parents: `2<leader>;` roots it two levels above
  -- the file) or just numbers an already open tree; `keymap_cwd` roots it at
  -- the cwd. false = leave that trigger unmapped (`:Filetree quickpick` stays).
  keymap = "<leader>;",
  keymap_cwd = "<leader>:",

  -- Which entries carry a number when the mode starts: "all" | "files" | "folders".
  content = "all",
  -- Open mode when no prefix key was pressed: "edit" | "split" | "vsplit" | "tab".
  open_mode = "edit",
  -- Label width = digits to type (1..3). Two digits: 00..99 on screen.
  width = 2,
  -- The mode ends after this long without a key. 0 = never (Esc only).
  timeout_ms = 5000,
  -- Map every other key in the tree buffer to <Nop> while the mode runs, so a
  -- stray press cannot trigger the tree plugin's own action. false = only the
  -- mode's own keys are taken over.
  silence_nvim_mappings = true,

  -- Where the label is drawn: "overlay" (over the first cells of the line),
  -- "inline" (pushes the text right), "right_align" or "eol".
  label_pos = "overlay",
  -- The badge showing the open mode, the content kind and the number typed.
  indicator = true,
  -- { reference, vertical, horizontal }:
  --   reference   "nvim" (the whole editor) | "filetree" (the tree window)
  --   vertical    "top" | "bottom"
  --   horizontal  "left" | "center" | "right"
  indicator_position = { "nvim", "top", "center" },

  -- Keys that work while the mode runs; each a key, a list of keys or false.
  keys = {
    edit = "e", -- open mode: edit (the default)
    split = "s", -- open mode: horizontal split
    vsplit = "v", -- open mode: vertical split
    tab = "t", -- open mode: new tab
    cycle = "c", -- all -> files -> folders -> all
    cancel = { "<Esc>", "<C-c>" }, -- leave the mode
    backspace = { "<BS>", "<C-h>" }, -- drop the last typed digit
    scroll_down = "j", -- one line down in the tree
    scroll_up = "k", -- one line up
    page_down = "<C-d>", -- half a page down
    page_up = "<C-u>", -- half a page up
  },

  -- Highlight groups (defined as links, so a colorscheme can restyle them).
  hl_number = "FiletreeQuickpickNumber",
  hl_typed = "FiletreeQuickpickTyped",
  hl_indicator = "FiletreeQuickpickIndicator",
}

---Option schema (see `filetree.config.schema`): exactly what
---`features.quickpick` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {
  keymap = "keymap",
  keymap_cwd = "keymap",
  content = { "string", enum = { "all", "files", "folders" } },
  open_mode = { "string", enum = { "edit", "split", "vsplit", "tab" } },
  width = { "number", min = 1, max = 3 },
  timeout_ms = { "number", min = 0 },
  silence_nvim_mappings = "boolean",
  label_pos = { "string", enum = { "overlay", "inline", "right_align", "eol" } },
  indicator = "boolean",
  indicator_position = { "table", of = "string" },
  keys = {
    "table",
    fields = {
      edit = "keymap",
      split = "keymap",
      vsplit = "keymap",
      tab = "keymap",
      cycle = "keymap",
      cancel = "keymap",
      backspace = "keymap",
      scroll_down = "keymap",
      scroll_up = "keymap",
      page_down = "keymap",
      page_up = "keymap",
    },
  },
  hl_number = "string",
  hl_typed = "string",
  hl_indicator = "string",
}

---@class FiletreeQuickpickState
---@field buf integer                    Tree buffer the labels live in.
---@field win integer                    Tree window.
---@field origin_win? integer            Window the mode was started from.
---@field input FiletreeQuickpickInput
---@field content FiletreeQuickpickContent
---@field entries FiletreeQuickpickEntry[]  What is on screen right now.
---@field truncated boolean              More entries qualified than the width can label.
---@field keys? FiletreeQuickpickKeyHandle
---@field augroup? integer
---@field unsubscribe? fun()             Adapter `on_render` subscription.
---@field timer? Lib.Debounce.Handle     Idle timeout (nil when `timeout_ms = 0`).
---@field render_pending boolean
---@field indicator_win? integer
---@field indicator_buf? integer

---@type FiletreeQuickpickConfig
local _cfg = vim.deepcopy(DEFAULTS)
---@type FiletreeAdapter?
local _adapter = nil
---@type FiletreeQuickpickState?
local _state = nil
---Polling timer of a start that is still waiting for the tree to render.
---@type uv.uv_timer_t?
local _boot = nil
---@type string[]
local _position = vim.deepcopy(logic.POSITION_DEFAULT)
---@type integer?
local _ns = nil

---@return integer
local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_quickpick") end
  return _ns
end

---@return integer
local function width()
  return math.max(1, math.min(3, math.floor(tonumber(_cfg.width) or 2)))
end

---Groups are created once at setup, never per start: `nvim_set_hl` forces a
---full redraw, which would flash the screen on every trigger.
local function define_highlights()
  local defaults = {
    [_cfg.hl_number] = "Search",
    [_cfg.hl_typed] = "IncSearch",
    [_cfg.hl_indicator] = "PmenuSel",
  }
  for name, link in pairs(defaults) do
    pcall(vim.api.nvim_set_hl, 0, name, { link = link, default = true })
  end
end

---Merge the user's body over the defaults. `keys` and `indicator_position` are
---replaced per entry / wholesale: a deep merge would splice a user's one-element
---key list into the default two-element one (`{ "q" }` + `"<C-c>"`).
---@param config table
---@return FiletreeQuickpickConfig
local function resolve(config)
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), config or {})
  cfg.keys = vim.tbl_extend("force", vim.deepcopy(DEFAULTS.keys), (config or {}).keys or {})
  if type(config) == "table" and config.indicator_position ~= nil then
    cfg.indicator_position = vim.deepcopy(config.indicator_position)
  end
  return cfg
end

---Keys of one `keys.*` option as a list: a string is one key, `false` none.
---@param value string|string[]|false|nil
---@return string[]
local function key_list(value)
  if type(value) == "string" and value ~= "" then return { value } end
  if type(value) == "table" then
    local out = {}
    for _, v in ipairs(value) do
      if type(v) == "string" and v ~= "" then out[#out + 1] = v end
    end
    return out
  end
  return {}
end

-- ── Cleanup ───────────────────────────────────────────────────────────────────

---@param s FiletreeQuickpickState
local function close_indicator(s)
  if s.indicator_win and vim.api.nvim_win_is_valid(s.indicator_win) then
    pcall(vim.api.nvim_win_close, s.indicator_win, true)
  end
  if s.indicator_buf and vim.api.nvim_buf_is_valid(s.indicator_buf) then
    pcall(vim.api.nvim_buf_delete, s.indicator_buf, { force = true })
  end
  s.indicator_win, s.indicator_buf = nil, nil
end

---End the mode and give everything back. Idempotent; `_state` is dropped
---first, so an autocmd that our own cleanup provokes finds nothing to do.
---@param opts? { restore_focus?: boolean }
local function cleanup(opts)
  local s = _state
  if not s then return end
  _state = nil

  if s.timer then s.timer.cancel() end
  au.del_group(s.augroup)
  if s.unsubscribe then pcall(s.unsubscribe) end
  if s.keys then s.keys.restore() end
  if vim.api.nvim_buf_is_valid(s.buf) then
    pcall(vim.api.nvim_buf_clear_namespace, s.buf, ns(), 0, -1)
  end
  close_indicator(s)

  if
    opts
    and opts.restore_focus
    and s.origin_win
    and s.origin_win ~= s.win
    and vim.api.nvim_win_is_valid(s.origin_win)
  then
    pcall(vim.api.nvim_set_current_win, s.origin_win)
  end
end

local function stop_boot()
  if _boot then
    pcall(_boot.stop, _boot)
    pcall(_boot.close, _boot)
    _boot = nil
  end
end

-- ── Render ────────────────────────────────────────────────────────────────────

---Rows reserved above the editor area by a visible tabline.
---@return integer
local function tabline_rows()
  local st = vim.o.showtabline
  if st == 2 or (st == 1 and #vim.api.nvim_list_tabpages() > 1) then return 1 end
  return 0
end

---@param s FiletreeQuickpickState
local function update_indicator(s)
  if not _cfg.indicator then return end
  local text = logic.indicator_text(s.input, s.content, width())
  if s.truncated then text = text .. "+ " end

  local relative_win = _position[1] == "filetree"
  local area_w, area_h, row_off
  if relative_win then
    area_w, area_h, row_off =
      vim.api.nvim_win_get_width(s.win), vim.api.nvim_win_get_height(s.win), 0
  else
    local status = vim.o.laststatus > 0 and 1 or 0
    area_w = vim.o.columns
    area_h = vim.o.lines - vim.o.cmdheight - status - tabline_rows()
    row_off = tabline_rows()
  end
  local row, col, w =
    logic.indicator_geometry(_position, area_w, area_h, vim.fn.strdisplaywidth(text))

  local cfg = {
    relative = relative_win and "win" or "editor",
    win = relative_win and s.win or nil,
    row = row + row_off,
    col = col,
    width = w,
    height = 1,
  }

  if not (s.indicator_win and vim.api.nvim_win_is_valid(s.indicator_win)) then
    s.indicator_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[s.indicator_buf].bufhidden = "wipe"
    local ok, win = pcall(
      vim.api.nvim_open_win,
      s.indicator_buf,
      false,
      vim.tbl_extend("force", cfg, {
        style = "minimal",
        focusable = false,
        zindex = 250,
        noautocmd = true,
      })
    )
    if not ok then
      close_indicator(s)
      return
    end
    s.indicator_win = win
    vim.wo[win].winhighlight = "Normal:" .. _cfg.hl_indicator
  else
    pcall(vim.api.nvim_win_set_config, s.indicator_win, cfg)
  end
  vim.api.nvim_buf_set_lines(s.indicator_buf, 0, -1, false, { text })
end

---The tree window's first and last visible buffer line.
---
--- `line("w0")` / `line("w$")` rather than `getwininfo()`'s topline/botline:
--- the latter are the values of the last screen redraw, which have not caught
--- up yet right after the adapter rewrote the buffer (and never do without a
--- UI), so a renumber triggered by exactly that rewrite saw the old height.
---@param win integer
---@return { [1]: integer, [2]: integer }|nil
local function viewport(win)
  -- `nvim_win_call` hands back only the first value of its function: a table.
  local ok, range = pcall(vim.api.nvim_win_call, win, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end)
  if ok and type(range) == "table" and range[1] >= 1 and range[2] >= range[1] then return range end
  return nil
end

---Redraw every label from scratch.
local function render()
  local s = _state
  if not s or not _adapter then return end
  if not vim.api.nvim_buf_is_valid(s.buf) or not vim.api.nvim_win_is_valid(s.win) then
    cleanup()
    return
  end

  vim.api.nvim_buf_clear_namespace(s.buf, ns(), 0, -1)

  local ok, nodes = pcall(_adapter.get_visible_nodes, nil, s.buf)
  if not ok or type(nodes) ~= "table" then nodes = {} end

  local range = viewport(s.win)
  local root = _adapter.get_root_path and _adapter.get_root_path() or nil
  s.entries, s.truncated = logic.assign(nodes, {
    content = s.content,
    width = width(),
    range = range,
    skip_path = root,
    ignore_case = vim.fn.has("win32") == 1,
  })

  local typed = s.input.digits
  for _, e in ipairs(s.entries) do
    if logic.matches_prefix(e.label, typed) then
      local chunks = {}
      if typed ~= "" then chunks[#chunks + 1] = { typed, _cfg.hl_typed } end
      chunks[#chunks + 1] = { e.label:sub(#typed + 1), _cfg.hl_number }
      pcall(vim.api.nvim_buf_set_extmark, s.buf, ns(), e.line - 1, 0, {
        virt_text = chunks,
        virt_text_pos = _cfg.label_pos,
        hl_mode = "combine",
        priority = 200,
      })
    end
  end

  update_indicator(s)
end

---Coalesce a burst of triggers (scroll, resize, the adapter's own redraws)
---into one render on the next tick.
local function schedule_render()
  local s = _state
  if not s or s.render_pending then return end
  s.render_pending = true
  vim.schedule(function()
    if _state ~= s then return end
    s.render_pending = false
    render()
  end)
end

---Any key in the mode counts as activity.
local function touch()
  if _state and _state.timer then _state.timer.call() end
end

-- ── Actions ───────────────────────────────────────────────────────────────────

---Expand a collapsed folder, collapse an expanded one, then renumber.
---@param node FiletreeNode
local function toggle_folder(node)
  if not _adapter then return end
  local ok
  if node.is_expanded == true then
    ok = _adapter.collapse_node(node)
  else
    ok = _adapter.expand_node(node)
  end
  if not ok then
    notify.info(("the %s adapter cannot expand or collapse folders"):format(_adapter.name))
    return
  end
  -- The adapter may redraw synchronously (neo-tree's narrow redraw) or later
  -- (an async directory scan); the buffer watcher and `on_render` catch the
  -- late case, this one the synchronous.
  schedule_render()
end

---Open a file in the chosen mode, from an editor window -- never from the tree
---window itself (an `:edit` there would replace the tree, a `:split` would
---split it).
---@param node FiletreeNode
---@param mode FiletreeOpenMode
---@param tree_win integer
local function open_node(node, mode, tree_win)
  if not _adapter then return end
  local win = bufutil.find_editor_win(tree_win)
  if win then
    pcall(vim.api.nvim_set_current_win, win)
  else
    window.open_editor_window(_adapter)
  end
  if not _adapter.open_file(node.path, mode) then notify.warn("could not open " .. node.path) end
end

---A complete number was typed.
---@param number integer
local function select_number(number)
  local s = _state
  if not s then return end
  local entry = logic.find(s.entries, number)
  if not entry then
    notify.info(("no entry numbered %s"):format(logic.format_label(number, width())))
    render()
    return
  end
  if entry.node.type == "directory" then
    toggle_folder(entry.node)
    render()
    return
  end
  local node, mode, tree_win = entry.node, s.input.mode, s.win
  cleanup() -- before the open: the open moves focus and may close/replace windows
  open_node(node, mode, tree_win)
end

---@param ev FiletreeQuickpickEvent
local function on_event(ev)
  local s = _state
  if not s then return end
  touch()
  local next_input, res = logic.feed(s.input, ev, width())
  s.input = next_input
  if res.kind == "select" then
    select_number(res.number)
    return
  end
  render()
end

local function cycle_content()
  local s = _state
  if not s then return end
  touch()
  s.content = logic.next_content(s.content)
  s.input.digits = ""
  render()
end

---@param normal_keys string  Normal-mode keys to run in the tree window.
local function scroll(normal_keys)
  local s = _state
  if not s then return end
  touch()
  local keys_ = vim.api.nvim_replace_termcodes(normal_keys, true, false, true)
  pcall(vim.api.nvim_win_call, s.win, function()
    vim.cmd("normal! " .. keys_)
  end)
  schedule_render()
end

-- ── Start / cancel ────────────────────────────────────────────────────────────

---Is the mode running?
---@return boolean
function M.is_active()
  return _state ~= nil
end

---Read-only view of the running mode, for tests and statuslines.
---@return { mode: string, content: string, digits: string, count: integer, buf: integer, win: integer }|nil
function M.snapshot()
  local s = _state
  if not s then return nil end
  return {
    mode = s.input.mode,
    content = s.content,
    digits = s.input.digits,
    count = #s.entries,
    buf = s.buf,
    win = s.win,
  }
end

---End the mode (no-op when none is running).
function M.cancel()
  stop_boot()
  cleanup({ restore_focus = true })
end

---Cycle the content kind (all -> files -> folders) of the running mode.
function M.cycle_content()
  cycle_content()
end

---@return FiletreeQuickpickKeyBinding[]
local function key_bindings()
  ---@type FiletreeQuickpickKeyBinding[]
  local b = {}
  ---@param value any
  ---@param fn fun()
  ---@param desc string
  local function add(value, fn, desc)
    for _, lhs in ipairs(key_list(value)) do
      b[#b + 1] = { lhs = lhs, fn = fn, desc = "[filetree.quickpick] " .. desc }
    end
  end

  for d = 0, 9 do
    local digit = tostring(d)
    add(digit, function()
      on_event({ kind = "digit", value = digit })
    end, "digit " .. digit)
  end
  for _, mode in ipairs(logic.OPEN_MODES) do
    add(_cfg.keys[mode], function()
      on_event({ kind = "mode", value = mode })
    end, "open mode " .. mode)
  end
  add(_cfg.keys.backspace, function()
    on_event({ kind = "backspace" })
  end, "drop the last digit")
  add(_cfg.keys.cancel, M.cancel, "leave the mode")
  add(_cfg.keys.cycle, cycle_content, "cycle files / folders / both")
  add(_cfg.keys.scroll_down, function()
    scroll("j")
  end, "scroll down")
  add(_cfg.keys.scroll_up, function()
    scroll("k")
  end, "scroll up")
  add(_cfg.keys.page_down, function()
    scroll("<C-d>")
  end, "half page down")
  add(_cfg.keys.page_up, function()
    scroll("<C-u>")
  end, "half page up")
  return b
end

---@param s FiletreeQuickpickState
local function watch(s)
  s.augroup = au.group("filetree_quickpick", true)
  local win_pat = tostring(s.win)

  au.acmd("WinScrolled", {
    group = s.augroup,
    pattern = win_pat,
    desc = "[filetree.quickpick] renumber after the tree scrolled",
    callback = schedule_render,
  })
  au.acmd({ "WinResized", "VimResized" }, {
    group = s.augroup,
    desc = "[filetree.quickpick] renumber and re-place the indicator after a resize",
    callback = schedule_render,
  })
  -- Leaving the mode by any other route than its own keys: focus moved, the
  -- window or buffer went away, the tab changed.
  au.acmd("WinLeave", {
    group = s.augroup,
    desc = "[filetree.quickpick] leave the mode when the tree loses focus",
    callback = function()
      if _state == s and vim.api.nvim_get_current_win() == s.win then cleanup() end
    end,
  })
  au.acmd("WinClosed", {
    group = s.augroup,
    pattern = win_pat,
    desc = "[filetree.quickpick] leave the mode when the tree window closes",
    callback = function()
      if _state == s then cleanup() end
    end,
  })
  au.acmd({ "BufWipeout", "BufDelete" }, {
    group = s.augroup,
    buffer = s.buf,
    desc = "[filetree.quickpick] leave the mode when the tree buffer goes away",
    callback = function()
      if _state == s then cleanup() end
    end,
  })
  au.acmd("TabLeave", {
    group = s.augroup,
    desc = "[filetree.quickpick] leave the mode when the tab changes",
    callback = function()
      if _state == s then cleanup({ restore_focus = false }) end
    end,
  })

  -- A tree that re-renders under us (expand/collapse, an async scan landing, a
  -- watcher refresh) wipes the extmarks and moves the lines. Watch the text
  -- itself -- every backend's redraw goes through it -- and, where the adapter
  -- offers one, its own render event too.
  pcall(vim.api.nvim_buf_attach, s.buf, false, {
    on_lines = function()
      if _state ~= s then return true end
      vim.schedule(schedule_render)
    end,
    on_reload = function()
      if _state ~= s then return true end
    end,
  })
  if type(_adapter and _adapter.on_render) == "function" then
    local ok, unsub = pcall(_adapter.on_render, function(bufnr)
      if _state == s and (bufnr == nil or bufnr == s.buf) then schedule_render() end
    end)
    if ok and type(unsub) == "function" then s.unsubscribe = unsub end
  end
end

---The tree is rendered: take it over.
---@return boolean started
local function begin()
  local adapter = _adapter
  if not adapter then return false end
  local is_open, buf = adapter.is_open()
  local win = adapter.get_winid and adapter.get_winid() or nil
  if not (is_open and buf and win and vim.api.nvim_win_is_valid(win)) then
    notify.warn("the tree is not open")
    return false
  end

  local current = vim.api.nvim_get_current_win()
  local origin = current ~= win and current or nil
  if not origin then
    local prev = vim.fn.win_getid(vim.fn.winnr("#"))
    if prev ~= 0 and prev ~= win and vim.api.nvim_win_is_valid(prev) then origin = prev end
  end
  pcall(vim.api.nvim_set_current_win, win)

  ---@type FiletreeQuickpickState
  local s = {
    buf = buf,
    win = win,
    origin_win = origin,
    input = logic.new_input(_cfg.open_mode),
    content = logic.is_content(_cfg.content) and _cfg.content or "all",
    entries = {},
    truncated = false,
    render_pending = false,
  }
  _state = s

  s.keys = keys.install(buf, key_bindings(), _cfg.silence_nvim_mappings == true)
  watch(s)
  if (_cfg.timeout_ms or 0) > 0 then
    s.timer = lib_debounce.new(function()
      if _state == s then M.cancel() end
    end, _cfg.timeout_ms)
    s.timer.call()
  end

  render()
  if #s.entries == 0 and s.content == "all" then
    cleanup({ restore_focus = true })
    notify.info("nothing to number in the tree")
    return false
  end
  return true
end

---Poll until the tree is open and has rendered at least one entry (neo-tree's
---`show` is asynchronous), then `on_ready()`.
---@param on_ready fun()
local function wait_for_tree(on_ready)
  stop_boot()
  local adapter = _adapter
  if not adapter then return end
  local tries = 0
  local timer = uv.new_timer()
  if not timer then
    vim.schedule(on_ready)
    return
  end
  _boot = timer
  timer:start(
    30,
    40,
    vim.schedule_wrap(function()
      if _boot ~= timer then return end
      tries = tries + 1
      local is_open, buf = adapter.is_open()
      local ready = false
      if is_open and buf then
        local ok, nodes = pcall(adapter.get_visible_nodes, nil, buf)
        ready = ok and type(nodes) == "table" and #nodes > 0
      end
      if ready or tries >= 75 then
        stop_boot()
        if ready then
          on_ready()
        else
          notify.warn("the tree did not show any entries")
        end
      end
    end)
  )
end

---The buffer's file, when the current buffer is an ordinary file.
---@return string?
local function current_file()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" or bufutil.is_tree_buffer(buf) then return nil end
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and name or nil
end

---Start the mode.
---
--- Without options it numbers the open tree, or opens it on the current file's
--- folder first. `parent_levels` re-roots that many folders above the file
--- (`2<leader>;`); `cwd` roots it at the cwd. Either also re-roots an already
--- open tree -- asking for a root is explicit; plain start never moves one.
---@param opts? { parent_levels?: integer, cwd?: boolean }
---@return boolean ok  false when the mode could not be started (the reason is notified).
function M.start(opts)
  opts = opts or {}
  local adapter = _adapter
  if not adapter then
    notify.warn("quickpick is off (features.quickpick.enabled = true turns it on)")
    return false
  end
  M.cancel()

  local levels = math.max(0, math.floor(tonumber(opts.parent_levels) or 0))
  local rooted = levels > 0 or opts.cwd == true
  local is_open = adapter.is_open()
  if is_open and not rooted then return begin() end

  local file = current_file()
  local ok
  if opts.cwd then
    local cwd = uv.cwd()
    if file and cwd then
      ok = adapter.open_reveal(file, 0, cwd)
    else
      ok = adapter.open_cwd()
    end
  elseif file then
    ok = adapter.open_reveal(file, levels)
  else
    ok = adapter.open_cwd()
  end
  if not ok then
    notify.warn(("the %s adapter could not open the tree"):format(adapter.name))
    return false
  end
  wait_for_tree(function()
    begin()
  end)
  return true
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeQuickpickConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  _cfg = resolve(config)
  if not _cfg.enabled then return end
  _adapter = adapter

  local pos, ok = logic.normalize_position(_cfg.indicator_position)
  _position = pos
  if not ok then
    notify.warn(
      'indicator_position must be { "nvim"|"filetree", "top"|"bottom", "left"|"center"|"right" }'
        .. " -- using the default for the invalid part"
    )
  end

  define_highlights()

  bind.bind("quickpick/global", _cfg, {
    {
      name = "open",
      field = "keymap",
      rhs = function()
        M.start({ parent_levels = vim.v.count })
      end,
      desc = "numbered quick-pick (a count roots the tree that many folders above the file)",
    },
    {
      name = "open_cwd",
      field = "keymap_cwd",
      rhs = function()
        M.start({ cwd = true })
      end,
      desc = "numbered quick-pick with the tree rooted at the cwd",
    },
  }, "global")
end

function M.teardown()
  M.cancel()
  stop_boot()
  for _, field in ipairs({ "keymap", "keymap_cwd" }) do
    for _, lhs in ipairs(key_list(_cfg[field])) do
      pcall(vim.keymap.del, "n", lhs)
    end
  end
  _adapter = nil
end

return M
