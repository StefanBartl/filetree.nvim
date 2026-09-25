-- Test code: a nil coming back from a fixture or a picker double must crash
-- and name itself, not be papered over by the guards LuaLS would ask for.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- create_from_template.lua -- headless unit tests for the template-first flow
-- of `filetree.features.fileops.create_from_template`:
--   * `M.move` never crosses the [custom]/[builtin] category boundary
--   * the picker's rows carry [custom]/[builtin] headers only for mixed sets
--   * the template is picked BEFORE the filename; the name is pre-filled with
--     the template's own filename (extension included)
--   * the reorderable picker keeps the cursor off header rows
--
-- The `ui.kit` picker is a double that owns a REAL scratch results window, so
-- the cursor logic runs against genuine `nvim_win_get_cursor`/`set_cursor`.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/create_from_template.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root)

-- Same lookup order as TESTS/units.lua: env override, sibling checkout, lazy.
local function prepend_dep(envs, sibling, lazy_name, marker)
  local candidates = {}
  for _, env in ipairs(envs) do
    local v = vim.env[env]
    if v and v ~= "" then candidates[#candidates + 1] = v end
  end
  candidates[#candidates + 1] = vim.fn.fnamemodify(root, ":h") .. "/" .. sibling
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/" .. lazy_name
  for _, c in ipairs(candidates) do
    if vim.fn.isdirectory(c .. marker) == 1 then
      vim.opt.rtp:prepend(c)
      return
    end
  end
end
prepend_dep({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }, "lib.nvim", "lib.nvim", "/lua/lib")
prepend_dep({ "FILETREE_UI_NVIM", "UI_NVIM_PATH" }, "ui.nvim", "ui.nvim", "/lua/ui")

local TMP_ROOT = vim.env.TEMP or vim.env.TMPDIR or vim.env.TMP or "/tmp"
do
  local uv = vim.uv or vim.loop
  TMP_ROOT = (uv.fs_realpath(TMP_ROOT) or TMP_ROOT):gsub("\\", "/")
end

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. (detail and ("  — " .. detail) or ""))
  end
end
local function eq(name, got, want)
  check(name, got == want, ("got %q want %q"):format(vim.inspect(got), vim.inspect(want)))
end

-- ── Fixtures ────────────────────────────────────────────────────────────────

local tmp = (TMP_ROOT .. "/cft-tests"):gsub("\\", "/")
vim.fn.delete(tmp, "rf")
vim.fn.mkdir(tmp, "p")

---@param dir string
---@param files table<string, string>
local function fresh_dir(dir, files)
  vim.fn.delete(dir, "rf")
  vim.fn.mkdir(dir, "p")
  for name, content in pairs(files or {}) do
    vim.fn.writefile({ content }, dir .. "/" .. name)
  end
  return dir
end

-- Messages routed through vim.notify (filetree.util.notify), for the
-- "header submitted" feedback check.
local notified = {}
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg)
  notified[#notified + 1] = tostring(msg)
end

-- The `ui.kit` double. `picker_mode`:
--   "picker" -> exposes kit.picker (reorderable flow), records the handle
--   "select" -> no kit.picker, exposes kit.select (plain fallback flow)
local state = {}

local function results_win(lines_holder)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 40,
    height = 20,
    style = "minimal",
  })
  lines_holder.buf, lines_holder.win = buf, win
  return {
    winid = win,
    bufnr = buf,
    is_valid = function()
      return vim.api.nvim_win_is_valid(win)
    end,
  }
end

local function install_kit(picker_mode)
  state = { inputs = {}, selects = 0, opens = 0 }
  local kit = {
    input = function(opts)
      state.inputs[#state.inputs + 1] = opts
    end,
  }
  if picker_mode == "picker" then
    kit.picker = function(opts)
      local q = ""
      local rw = {}
      local prompt_buf = vim.api.nvim_create_buf(false, true)
      local handle = {
        query = function()
          return q
        end,
        set_results = function(lines)
          state.lines = lines
          vim.api.nvim_buf_set_lines(rw.buf, 0, -1, false, lines)
        end,
        slots = { results = results_win(rw), prompt = { bufnr = prompt_buf } },
      }
      handle.move = function(delta)
        local count = math.max(1, vim.api.nvim_buf_line_count(rw.buf))
        local line = vim.api.nvim_win_get_cursor(rw.win)[1] + delta
        if line < 1 then
          line = count
        elseif line > count then
          line = 1
        end
        vim.api.nvim_win_set_cursor(rw.win, { line, 0 })
      end
      state.opens = state.opens + 1
      state.handle, state.opts, state.rw, state.prompt_buf = handle, opts, rw, prompt_buf
      state.type = function(query)
        q = query
        opts.on_change(query)
      end
      return handle
    end
  else
    kit.select = function(o)
      state.selects = state.selects + 1
      state.select_items = o.items
      state.on_select(o)
    end
  end
  package.loaded["ui.kit"] = kit
end

-- A stub adapter is all `setup()` needs; open_after=false keeps the run from
-- touching real windows.
local stub = setmetatable({
  name = "cft-tests-stub",
  is_available = function()
    return true
  end,
  get_winid = function()
    return nil
  end,
  refresh = function()
    return true
  end,
}, {
  __index = function()
    return function()
      return false
    end
  end,
})

---Fresh module instance bound to `tdir`, against the currently installed kit.
local function load_cft(tdir)
  package.loaded["pickers.engines"] = nil
  package.loaded["filetree.util.select"] = nil
  package.loaded["filetree.features.fileops.create_from_template"] = nil
  local cft = require("filetree.features.fileops.create_from_template")
  cft.setup({
    enabled = true,
    template_dir = tdir,
    open_after = false,
    prefer = "builtin", -- never dispatch to pickers.nvim
    keymap = false,
  }, stub)
  return cft
end

local function builtin_names(cft)
  local out = {}
  for _, t in ipairs(cft.list()) do
    if t.builtin then out[#out + 1] = t.name end
  end
  return out
end

local function names(list)
  local out = {}
  for _, t in ipairs(list) do
    out[#out + 1] = t.name
  end
  return out
end

local function index_of(lines, text)
  for i, l in ipairs(lines) do
    if l == text then return i end
  end
end

---Callback of a prompt-buffer keymap, looked up the way a keypress would.
local function prompt_map(lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(state.prompt_buf, "n")) do
    if m.lhs == lhs then return m.callback end
  end
end

-- ── builtin templates must exist, or half of this suite proves nothing ─────

install_kit("picker")
local empty_dir = fresh_dir(tmp .. "/t-builtin-only", {})
local cft = load_cft(empty_dir)
local builtins = builtin_names(cft)
check("fixture: the shipped builtin templates are on the runtimepath", #builtins >= 2)

-- ── build_rows: header rows only for mixed sets ────────────────────────────

do
  cft.open(tmp) -- builtin-only: no custom templates at all
  check("builtin-only: picker opened", state.handle ~= nil)
  check("builtin-only: no [custom] header", index_of(state.lines, "[custom]") == nil)
  check("builtin-only: no [builtin] header", index_of(state.lines, "[builtin]") == nil)
  eq("builtin-only: rows are exactly the builtin templates", #state.lines, #builtins)
  eq("builtin-only: first row is a real template", state.lines[1], builtins[1])
end

local tdir = fresh_dir(tmp .. "/t-mixed", { ["alpha.lua"] = "A ${filename}", ["beta.lua"] = "B" })
cft = load_cft(tdir)
builtins = builtin_names(cft)

do
  cft.open(tmp)
  local lines = state.lines
  eq("mixed: row 1 is the [custom] header", lines[1], "[custom]")
  eq("mixed: custom templates follow, in order", lines[2], "alpha.lua")
  eq("mixed: ... both of them", lines[3], "beta.lua")
  eq("mixed: [builtin] header sits after the custom block", lines[4], "[builtin]")
  eq("mixed: builtin block starts right after it", lines[5], builtins[1])
  eq("mixed: total = custom + builtin + 2 headers", #lines, 2 + #builtins + 2)

  -- The cursor-nudge fix: row 1 is a header, so the cursor must have been
  -- moved onto the first real template row (2) by the initial render.
  eq(
    "cursor nudge: initial render leaves the cursor on the first template, not [custom]",
    vim.api.nvim_win_get_cursor(state.rw.win)[1],
    2
  )

  -- Filtering drops the headers and shows a flat list.
  state.type("beta")
  eq("filter: header-free flat match list", table.concat(state.lines, ","), "beta.lua")
  state.type("")
  eq("filter cleared: headers are back", state.lines[1], "[custom]")
  eq(
    "cursor nudge: re-render after clearing the filter also lands on a template row",
    vim.api.nvim_win_get_cursor(state.rw.win)[1],
    2
  )

  -- Submitting a header must be a no-op with feedback, not a silent close.
  local before_inputs, before_opens = #state.inputs, state.opens
  state.opts.on_submit(1)
  eq("header submit: no filename prompt opened", #state.inputs, before_inputs)
  vim.wait(500, function()
    return state.opens > before_opens
  end)
  eq("header submit: the picker re-opens instead of just closing", state.opens, before_opens + 1)
  eq("header submit: the re-opened picker shows the same rows", state.lines[1], "[custom]")
end

-- ── Template FIRST, then filename pre-filled with the template's name ──────

do
  local dest = fresh_dir(tmp .. "/dest-flow", {})
  cft.open(dest)
  eq("flow: no filename prompt before a template is picked", #state.inputs, 0)

  state.opts.on_submit(index_of(state.lines, "alpha.lua"))
  eq("flow: picking a template opens exactly one filename prompt", #state.inputs, 1)
  local inp = state.inputs[1]
  eq(
    "flow: name is pre-filled with the template filename, extension included",
    inp.default,
    "alpha.lua"
  )
  check(
    "flow: prompt title names the template",
    inp.title:find("alpha.lua", 1, true) ~= nil,
    inp.title
  )

  -- Keeping the extension is the whole point: the content's language survives.
  inp.on_submit("widget.lua")
  eq("flow: file created at dest/<name>", vim.fn.filereadable(dest .. "/widget.lua"), 1)
  eq(
    "flow: ${filename} substituted from the typed name",
    vim.fn.readfile(dest .. "/widget.lua")[1],
    "A widget"
  )

  -- Empty name -> nothing created, no error.
  local n_before = #vim.fn.readdir(dest)
  inp.on_submit("")
  eq("flow: empty name creates nothing", #vim.fn.readdir(dest), n_before)

  -- A builtin template pre-fills with its own (extension-bearing) name too.
  cft.open(dest)
  state.opts.on_submit(index_of(state.lines, builtins[1]))
  eq(
    "flow: builtin template pre-fills its own name",
    state.inputs[#state.inputs].default,
    builtins[1]
  )
end

-- ── M.move: category boundary ──────────────────────────────────────────────

do
  local function order()
    return names(cft.list())
  end
  local function custom_names()
    local out = {}
    for _, t in ipairs(cft.list()) do
      if not t.builtin then out[#out + 1] = t.name end
    end
    return table.concat(out, ",")
  end

  eq("move: start order is alphabetical custom", custom_names(), "alpha.lua,beta.lua")
  eq("move: first custom cannot go up (overall boundary)", cft.move("alpha.lua", -1), false)
  eq("move: last custom cannot go down across into [builtin]", cft.move("beta.lua", 1), false)
  eq("move: a refused move leaves the order untouched", custom_names(), "alpha.lua,beta.lua")

  eq("move: swap inside the custom block succeeds", cft.move("alpha.lua", 1), true)
  eq("move: ... and is reflected by list()", custom_names(), "beta.lua,alpha.lua")
  eq(
    "move: customs still all precede builtins after a move",
    (function()
      local seen_builtin = false
      for _, t in ipairs(cft.list()) do
        if t.builtin then
          seen_builtin = true
        elseif seen_builtin then
          return false
        end
      end
      return true
    end)(),
    true
  )

  local first_b, last_b = builtins[1], builtins[#builtins]
  eq("move: first builtin cannot go up into [custom]", cft.move(first_b, -1), false)
  eq("move: last builtin cannot go down (overall boundary)", cft.move(last_b, 1), false)
  eq("move: unknown name is a no-op", cft.move("nope.zzz", 1), false)
  eq("move: builtin block order untouched by refused moves", builtin_names(cft)[1], first_b)

  if #builtins >= 2 then
    eq("move: swap inside the builtin block succeeds", cft.move(first_b, 1), true)
    eq("move: ... first builtin is now second", builtin_names(cft)[2], first_b)
  end

  -- Persisted as custom-block then builtin-block, never interleaved.
  local persisted = vim.json.decode(table.concat(vim.fn.readfile(tdir .. "/.order.json"), "\n"))
  eq("move: order file persists custom first", persisted.order[1], "beta.lua")
  eq("move: ... then the rest of the custom block", persisted.order[2], "alpha.lua")
  eq("move: ... then the builtin block", persisted.order[3], builtin_names(cft)[1])
  eq("move: persisted the FULL list", #persisted.order, #order())
end

-- ── <M-j>/<M-k> in the reorderable picker: cursor follows the moved row ────

do
  fresh_dir(tdir, { ["alpha.lua"] = "A", ["beta.lua"] = "B" })
  cft.open(tmp)
  local win = state.rw.win
  local down, up = prompt_map("<M-j>"), prompt_map("<M-k>")
  check("reorder: <M-j>/<M-k> are mapped on the prompt buffer", down ~= nil and up ~= nil)

  vim.api.nvim_win_set_cursor(win, { index_of(state.lines, "alpha.lua"), 0 })
  down()
  eq("reorder: alpha moved below beta", state.lines[3], "alpha.lua")
  eq("reorder: cursor followed alpha", vim.api.nvim_win_get_cursor(win)[1], 3)

  -- alpha is now the last custom: moving further down must not cross [builtin].
  down()
  eq("reorder: cannot cross the [builtin] header", state.lines[3], "alpha.lua")
  eq("reorder: cursor stays on alpha", vim.api.nvim_win_get_cursor(win)[1], 3)

  up()
  eq("reorder: <M-k> moves it back up", state.lines[2], "alpha.lua")
  eq("reorder: cursor followed it up", vim.api.nvim_win_get_cursor(win)[1], 2)
  up()
  eq("reorder: cannot go above the first custom", state.lines[2], "alpha.lua")

  -- With a filter active, reordering is refused with a hint.
  state.type("alpha")
  notified = {}
  down()
  check(
    "reorder: refused while a filter is active",
    #notified == 1 and notified[1]:find("Clear the filter", 1, true) ~= nil,
    vim.inspect(notified)
  )
end

-- ── <Up>/<Down> browsing never rests on a header row ───────────────────────

do
  fresh_dir(tdir, { ["alpha.lua"] = "A", ["beta.lua"] = "B" })
  cft.open(tmp)
  local win, h = state.rw.win, state.handle
  eq("browse: rows are [custom], alpha, beta, [builtin], ...", state.lines[4], "[builtin]")

  vim.api.nvim_win_set_cursor(win, { 3, 0 }) -- beta, the last custom row
  h.move(1)
  eq(
    "browse: <Down> from the last custom skips the [builtin] header",
    vim.api.nvim_win_get_cursor(win)[1],
    5
  )
  h.move(-1)
  eq(
    "browse: <Up> from the first builtin skips it backwards too",
    vim.api.nvim_win_get_cursor(win)[1],
    3
  )

  vim.api.nvim_win_set_cursor(win, { 2, 0 }) -- alpha, the first custom row
  h.move(-1)
  eq(
    "browse: <Up> from the first template wraps past [custom] to the last row",
    vim.api.nvim_win_get_cursor(win)[1],
    #state.lines
  )
  h.move(1)
  eq(
    "browse: <Down> from the last row wraps past [custom] to the first template",
    vim.api.nvim_win_get_cursor(win)[1],
    2
  )
end

-- ── Filename handling: subdir, whitespace, directory targets ───────────────

do
  local dest = fresh_dir(tmp .. "/dest-names", {})
  local function submit(name)
    cft.open(dest)
    state.opts.on_submit(index_of(state.lines, "alpha.lua"))
    notified = {}
    return pcall(state.inputs[#state.inputs].on_submit, name)
  end

  local ok = submit("sub/dir/new.lua")
  check("names: a subdirectory name does not raise", ok)
  eq(
    "names: the missing parent directories are created",
    vim.fn.filereadable(dest .. "/sub/dir/new.lua"),
    1
  )

  ok = submit("  spaced.lua  ")
  check("names: surrounding whitespace does not raise", ok)
  eq(
    "names: ... and is trimmed from the created name",
    vim.fn.filereadable(dest .. "/spaced.lua"),
    1
  )

  local before = #vim.fn.readdir(dest)
  ok = submit("   ")
  check("names: whitespace-only is ignored without raising", ok)
  eq("names: ... and creates nothing", #vim.fn.readdir(dest), before)

  ok = submit("onlydir/")
  check("names: a trailing slash does not raise", ok)
  check(
    "names: ... and is refused with a hint",
    #notified == 1 and notified[1]:find("filename", 1, true) ~= nil,
    vim.inspect(notified)
  )
  eq("names: ... creating no directory either", vim.fn.isdirectory(dest .. "/onlydir"), 0)

  vim.fn.mkdir(dest .. "/isdir.lua", "p")
  ok = submit("isdir.lua")
  check("names: a directory as the destination is reported, not raised", ok)
  check(
    "names: ... via a 'Could not write' error",
    #notified >= 1 and notified[#notified]:find("Could not write", 1, true) ~= nil,
    vim.inspect(notified)
  )
  eq("names: ... and the directory survives", vim.fn.isdirectory(dest .. "/isdir.lua"), 1)
end

-- ── M.move must not claim success when the order file cannot be written ────

do
  fresh_dir(tdir, { ["alpha.lua"] = "A", ["beta.lua"] = "B" })
  -- json.write stages through "<file>.tmp"; a directory squatting on that
  -- name makes the write fail WITHOUT throwing (it returns false, err).
  vim.fn.mkdir(tdir .. "/.order.json.tmp", "p")
  notified = {}
  eq("move: an unwritable order file is reported as a failed move", cft.move("alpha.lua", 1), false)
  check(
    "move: ... with a warning naming the cause",
    #notified >= 1 and notified[1]:find("Could not save the template order", 1, true) ~= nil,
    vim.inspect(notified)
  )
  eq("move: ... and the visible order is unchanged", names(cft.list())[1], "alpha.lua")
  vim.fn.delete(tdir .. "/.order.json.tmp", "rf")
  eq("move: it works again once the write can succeed", cft.move("alpha.lua", 1), true)
end

-- ── Plain (kit.select) fallback: header pick re-opens instead of closing ───

do
  install_kit("select")
  local cft2 = load_cft(fresh_dir(tmp .. "/t-plain", { ["one.lua"] = "1" }))
  local picked
  state.on_select = function(o)
    -- 1st call: choose the [custom] header (items[1]); 2nd call: a real row.
    if state.selects == 1 then
      o.on_select(o.items[1], 1)
    else
      for _, item in ipairs(o.items) do
        if item.tmpl and item.tmpl.name == "one.lua" then
          o.on_select(item, 1)
          return
        end
      end
    end
  end
  local dest = fresh_dir(tmp .. "/dest-plain", {})
  cft2.open(dest)
  eq("plain: picking a header re-opens the picker once", state.selects, 2)
  eq("plain: header row is first in the mixed list", state.select_items[1].text, "[custom]")
  eq("plain: then the filename prompt appears for the real pick", #state.inputs, 1)
  picked = state.inputs[1]
  eq("plain: pre-filled with the template's name", picked.default, "one.lua")
end

package.loaded["ui.kit"] = nil
package.loaded["filetree.features.fileops.create_from_template"] = nil

print(("\nfiletree.nvim create_from_template: %d passed, %d failed"):format(passed, failed))
vim.cmd(failed == 0 and "qa!" or "cq!")
