---@module 'filetree.features.nav.auto_reveal'
--- Automatically reveal the current editor buffer in the tree.
---
--- Unlike cwd_sync (which changes the working directory), auto_reveal never
--- changes the cwd or the tree's root. On every buffer switch it:
---   1. Scrolls to the file's line if it is already rendered (cheap).
---   2. Otherwise expands collapsed parent directories to reveal it, but only
---      within the tree's CURRENT root (adapter.open_reveal is called with that
---      root pinned) — so it can never re-root the tree itself.
---   3. Does nothing when the file lives outside the current root; getting the
---      root there first is cwd_sync's job (or the tree plugin's own cwd-follow,
---      e.g. neo-tree's bind_to_cwd + follow_current_file).
---
--- Debounced to avoid spam during rapid buffer switching. Automatically
--- pauses when the cursor is inside the tree window to prevent feedback
--- loops. Can also be paused programmatically (e.g. during batch ops).
---
--- Entering the tree window (`<C-w>w`, `<C-h>`, `:wincmd h`, a mouse click)
--- syncs the tree cursor to the file you came from, before the pause is armed.
--- Without that, landing on the right node depended on whether the debounced
--- BufEnter reveal happened to have fired first: switch buffers and step into
--- the tree inside the debounce window and the reveal arrives to find the
--- cursor already in the tree, drops itself, and leaves you on whatever node
--- you last touched. Same for stepping out and back in inside the pause. The
--- reveal-on-enter does not go through the debounce and does not consult the
--- entry pause -- it *is* the entry -- so where the cursor lands no longer
--- depends on how fast the window switch was.
---
--- Config:
---   enabled        boolean
---   debounce_ms    integer   Delay after BufEnter (default 150ms).
---   ignore_ft      string[]  Filetypes to never trigger reveal (e.g. lazy, mason).
---   only_if_open   boolean   Only reveal when tree window is visible (default true).
---   sync_on_enter  boolean   Move the tree cursor onto the current file's node
---                            when the tree window is entered (default true).
---
--- User commands:
---   :FiletreeAutoRevealPause [ms]   Pause for N ms (default 2000).
---   :FiletreeAutoRevealResume       Resume immediately.
---   :FiletreeRevealCurrent          Force reveal now.

local bufevents = require("filetree.util.bufevents")
local lib_debounce = require("lib.nvim.debounce")
local M = {}

---@type FiletreeAutoRevealConfig
local _cfg = {
  enabled = false,
  debounce_ms = 150,
  ignore_ft = {
    "neo-tree",
    "NvimTree",
    "netrw",
    "TelescopePrompt",
    "fzf",
    "lazy",
    "mason",
    "trouble",
    "qf",
    "help",
    "man",
    "terminal",
    "nofile",
    "prompt",
  },
  only_if_open = true,
  sync_on_enter = true,
}

---@type FiletreeAdapter?
local _adapter = nil

---Explicit pauses only -- `M.pause()`, `:Filetree reveal pause`. Kept separate
---from the entry pause below so that a caller pausing reveals for a batch
---operation still silences everything, while merely stepping into the tree does
---not disable the reveal-on-enter that stepping into the tree is supposed to do.
---@type integer  monotonic timestamp (vim.uv.hrtime) after which reveals are active
local _paused_until = 0

---Set when the tree window is entered: suppresses the *editor-driven* reveal for
---a moment, so leaving the tree does not immediately drag the tree cursor off
---the node the user just navigated to. Deliberately not consulted by the
---reveal-on-enter -- re-entering the tree within the window would otherwise skip
---the sync and land on a stale node, which is the very unreliability this
---feature exists to remove.
---@type integer  monotonic timestamp (vim.uv.hrtime) after which reveals are active
local _tree_pause_until = 0

---Last real file seen in an editor window, as the fallback for
---`current_file_path()` when the window we came from holds something else
---(a terminal, help, a picker) or is already gone.
---@type string?
local _last_editor_path = nil

---Debounce handle built in M.setup() (needs `_cfg.debounce_ms`); `{ call, cancel }`.
---@type table?
local _debounce = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

---@internal
---@return boolean
local function is_paused()
  return (vim.uv or vim.loop).hrtime() < _paused_until
end

---@internal
---@return boolean
local function tree_paused()
  return (vim.uv or vim.loop).hrtime() < _tree_pause_until
end

---@internal
---@return boolean
local function tree_is_open()
  if not _adapter then return false end
  local winid = _adapter.get_winid and _adapter.get_winid() or -1
  return winid > 0 and vim.api.nvim_win_is_valid(winid)
end

---@internal
---@return boolean
local function cursor_in_tree()
  if not _adapter then return false end
  local winid = _adapter.get_winid and _adapter.get_winid() or -1
  return winid > 0 and vim.api.nvim_get_current_win() == winid
end

---@internal
---@param bufnr integer
---@return boolean
local function should_ignore(bufnr)
  local ft = vim.bo[bufnr].filetype
  local bt = vim.bo[bufnr].buftype
  if bt ~= "" and bt ~= "acwrite" then return true end
  for _, ignored in ipairs(_cfg.ignore_ft) do
    if ft == ignored then return true end
  end
  return false
end

---@internal
---Whether `path` lives under `root` (prefers lib.nvim.fs.is_subpath; falls back
---to a local forward-slash prefix comparison so this still works without it).
---
---The `{}` third argument makes is_subpath canonicalize both sides through
---`lib.nvim.fs.normkey` instead of `vim.fs.normalize`. Neither side is ours:
---`path` comes from a buffer name and `root` from whatever resolved the
---project, so on Windows they can differ in drive-letter case or in 8.3 short
---vs long form and a plain string compare then answers false — auto-reveal
---silently never fires. Older lib versions ignore the extra argument and keep
---the previous behavior. (An `is_subpath` predating the parameter is why the
---fallback below still exists at all.)
---@param path string
---@param root string
---@return boolean
local function under_root(path, root)
  local ok, is_subpath = pcall(require, "lib.nvim.fs.is_subpath")
  if ok and type(is_subpath) == "function" then
    local ok2, result = pcall(is_subpath, path, root, {})
    if ok2 then return result end
  end
  local p = path:gsub("\\", "/")
  local r = root:gsub("\\", "/"):gsub("/$", "")
  return p == r or p:sub(1, #r + 1) == r .. "/"
end

-- ── Reveal logic ──────────────────────────────────────────────────────────────

---How long to keep looking for a node that `open_reveal` is still scanning in,
---as successive delays in ms. Bounded on purpose: about a second in total, then
---it gives up rather than fighting whatever else is moving the cursor.
---@type integer[]
local REVEAL_RETRY_MS = { 60, 120, 240, 480 }

---`open_reveal` only guarantees the node becomes *rendered*. Neo-tree reveals
---through a debounced, asynchronous rescan, and when that is driven from inside
---the tree window it leaves the cursor where it was instead of jumping to the
---revealed node -- so the tree expands correctly and the cursor sits on the root
---line. Once the node turns up in the line map, put the cursor there.
---
---Aborts as soon as the tree cursor moves from where this left it: that is
---either the tree plugin having focused the node itself (nothing to do) or the
---user having moved on (nothing to interrupt).
---@internal
---@param path string
---@param anchor integer  Tree cursor line as it was when the reveal was issued.
---@param attempt integer
local function place_cursor_when_rendered(path, anchor, attempt)
  if not _adapter or type(_adapter.get_node_line) ~= "function" then return end
  local winid = _adapter.get_winid and _adapter.get_winid() or -1
  if winid <= 0 or not vim.api.nvim_win_is_valid(winid) then return end
  local ok, pos = pcall(vim.api.nvim_win_get_cursor, winid)
  if not ok or pos[1] ~= anchor then return end

  local line = _adapter.get_node_line(path)
  if line then
    _adapter.scroll_to_line(line)
    return
  end
  local delay = REVEAL_RETRY_MS[attempt]
  if not delay then return end
  vim.defer_fn(function()
    place_cursor_when_rendered(path, anchor, attempt + 1)
  end, delay)
end

---Move the tree cursor onto `path`, expanding parents if it takes that. No
---guards: every caller has already decided that a reveal is wanted.
---@internal
---@param path string
local function reveal_to(path)
  if not _adapter then return end

  -- Fast path: the file is already rendered (its parent dirs are expanded) —
  -- just move the tree cursor to it (cheap; the adapter caches the path→line map).
  if type(_adapter.get_node_line) == "function" and type(_adapter.scroll_to_line) == "function" then
    local line = _adapter.get_node_line(path)
    if line then
      _adapter.scroll_to_line(line)
      return
    end
  end

  -- Slow path: the node is not currently visible (a parent dir is collapsed).
  -- Expand to reveal it, but ONLY within the tree's CURRENT root — never re-root
  -- here. Re-rooting is cwd_sync's job (it anchors at the project root); if
  -- auto_reveal also re-rooted (e.g. to the file's parent), the two would race on
  -- every buffer switch and the tree could settle on the wrong directory. When the
  -- file lives outside the current root, silently do nothing — cwd_sync (or the
  -- tree plugin's own cwd-follow, e.g. neo-tree bind_to_cwd) is responsible for
  -- getting the root there first.
  if type(_adapter.get_root_path) == "function" and type(_adapter.open_reveal) == "function" then
    local root = _adapter.get_root_path()
    if root and root ~= "" and under_root(path, root) then
      local winid = _adapter.get_winid and _adapter.get_winid() or -1
      local anchor = nil
      if winid > 0 and vim.api.nvim_win_is_valid(winid) then
        local ok, pos = pcall(vim.api.nvim_win_get_cursor, winid)
        if ok then anchor = pos[1] end
      end
      pcall(_adapter.open_reveal, path, 0, root)
      if anchor then place_cursor_when_rendered(path, anchor, 1) end
    end
  end
end

---The editor-driven reveal: something entered a buffer, follow it in the tree.
---@internal
---@param path string
local function do_reveal(path)
  if not _adapter then return end
  if is_paused() or tree_paused() then return end
  if cursor_in_tree() then return end
  if _cfg.only_if_open and not tree_is_open() then return end
  reveal_to(path)
end

---@internal
---@param path string
local function schedule_reveal(path)
  if _debounce then _debounce.call(path) end
end

---The file the user was looking at before stepping into the tree. Prefers the
---window actually left behind (`winnr("#")`) over the alternate buffer or the
---last BufEnter, because with several editor windows open those disagree — and
---the one the user came from is the one they mean.
---@internal
---@return string?
local function current_file_path()
  local nr = vim.fn.winnr("#")
  if nr > 0 then
    local win = vim.fn.win_getid(nr)
    -- win_getid(0) is the *current* window, so a stale `#` must not fall through
    -- to it: that would resolve to the tree buffer and be discarded a line later
    -- anyway, but only by accident.
    if win ~= 0 and win ~= vim.api.nvim_get_current_win() and vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if not should_ignore(buf) then
        local p = vim.api.nvim_buf_get_name(buf)
        if p ~= "" and vim.fn.filereadable(p) == 1 then return p end
      end
    end
  end
  if _last_editor_path and vim.fn.filereadable(_last_editor_path) == 1 then
    return _last_editor_path
  end
  return nil
end

---Put the tree cursor on the current file's node, on entering the tree window.
---Unlike `do_reveal` this runs *while* the cursor is in the tree — that is the
---point — and ignores the entry pause it is about to arm. An explicit
---`M.pause()` still silences it: a batch operation that asked for no reveals
---means no reveals.
---@internal
local function sync_on_enter()
  if not _cfg.sync_on_enter then return end
  if not _adapter or is_paused() then return end
  local path = current_file_path()
  if not path then return end
  -- A reveal queued by the BufEnter that brought us here is now redundant, and
  -- would fire from inside the tree only to drop itself.
  if _debounce then _debounce.cancel() end
  reveal_to(path)
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Pause auto-reveal for `ms` milliseconds.
---@param ms? integer  Default 2000ms.
function M.pause(ms)
  ms = ms or 2000
  _paused_until = (vim.uv or vim.loop).hrtime() + (ms * 1e6)
end

---Resume auto-reveal immediately.
function M.resume()
  _paused_until = 0
end

---Force-reveal the current buffer right now.
function M.reveal_current()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path and path ~= "" and vim.fn.filereadable(path) == 1 then do_reveal(path) end
end

---@return boolean
function M.is_paused()
  return is_paused()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeAutoRevealConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _debounce then _debounce.cancel() end
  _debounce = lib_debounce.new(do_reveal, _cfg.debounce_ms)

  bufevents.register("auto_reveal", "BufEnter:editor", {
    desc = "[filetree] Reveal the entered file in the tree",
    priority = bufevents.PRIORITY.REVEAL,
    load = function(ctx)
      if should_ignore(ctx.buf) then return end
      local path = vim.api.nvim_buf_get_name(ctx.buf)
      if path and path ~= "" and vim.fn.filereadable(path) == 1 then
        _last_editor_path = path
        schedule_reveal(path)
      end
    end,
  })

  -- Entering the tree: land on the current file's node, then hold reveals off
  -- for a moment so leaving again doesn't immediately drag the cursor away.
  bufevents.register("auto_reveal", "WinEnter:tree", {
    desc = "[filetree] Reveal the current file when the tree window is entered",
    priority = bufevents.PRIORITY.REVEAL,
    load = function()
      sync_on_enter()
      _tree_pause_until = (vim.uv or vim.loop).hrtime() + (500 * 1e6)
    end,
  })
end

function M.teardown()
  bufevents.unregister("auto_reveal")
  _adapter = nil
  _paused_until = 0
  _tree_pause_until = 0
  _last_editor_path = nil
  if _debounce then
    if _debounce then _debounce.cancel() end
    _debounce = nil
  end
end

return M
