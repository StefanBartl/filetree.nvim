---@module 'filetree.features.auto_reveal'
---@brief Automatically reveal the current editor buffer in the tree.
---@description
--- Unlike cwd_sync (which changes the working directory), auto_reveal only
--- calls adapter.reveal(path) to scroll and highlight the current file in
--- the tree without changing the cwd or the tree's root.
---
--- Debounced to avoid spam during rapid buffer switching. Automatically
--- pauses when the cursor is inside the tree window to prevent feedback
--- loops. Can also be paused programmatically (e.g. during batch ops).
---
--- Config:
---   enabled        boolean
---   debounce_ms    integer   Delay after BufEnter (default 150ms).
---   ignore_ft      string[]  Filetypes to never trigger reveal (e.g. lazy, mason).
---   only_if_open   boolean   Only reveal when tree window is visible (default true).
---
--- User commands:
---   :FiletreeAutoRevealPause [ms]   Pause for N ms (default 2000).
---   :FiletreeAutoRevealResume       Resume immediately.
---   :FiletreeRevealCurrent          Force reveal now.

local notify = require("filetree.util.notify").create("[filetree.auto_reveal]")

local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeAutoRevealConfig
local _cfg = {
  enabled      = false,
  debounce_ms  = 150,
  ignore_ft    = {
    "neo-tree", "NvimTree", "netrw",
    "TelescopePrompt", "fzf",
    "lazy", "mason", "trouble", "qf",
    "help", "man", "terminal",
    "nofile", "prompt",
  },
  only_if_open = true,
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  monotonic timestamp (vim.uv.hrtime) after which reveals are active
local _paused_until = 0

---@type any?
local _timer = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function is_paused()
  return (vim.uv or vim.loop).hrtime() < _paused_until
end

local function tree_is_open()
  if not _adapter then return false end
  local winid = _adapter.get_winid and _adapter.get_winid() or -1
  return winid > 0 and vim.api.nvim_win_is_valid(winid)
end

local function cursor_in_tree()
  if not _adapter then return false end
  local winid = _adapter.get_winid and _adapter.get_winid() or -1
  return winid > 0 and vim.api.nvim_get_current_win() == winid
end

local function should_ignore(bufnr)
  local ft = vim.bo[bufnr].filetype
  local bt = vim.bo[bufnr].buftype
  if bt ~= "" and bt ~= "acwrite" then return true end
  for _, ignored in ipairs(_cfg.ignore_ft) do
    if ft == ignored then return true end
  end
  return false
end

---Whether `path` lives under `root` (prefers lib.nvim.fs.is_subpath; falls back
---to a local forward-slash prefix comparison so this still works without it).
---@param path string
---@param root string
---@return boolean
local function under_root(path, root)
  local ok, is_subpath = pcall(require, "lib.nvim.fs.is_subpath")
  if ok and type(is_subpath) == "function" then
    local ok2, result = pcall(is_subpath, path, root)
    if ok2 then return result end
  end
  local p = path:gsub("\\", "/")
  local r = root:gsub("\\", "/"):gsub("/$", "")
  return p == r or p:sub(1, #r + 1) == r .. "/"
end

-- ── Reveal logic ──────────────────────────────────────────────────────────────

local function do_reveal(path)
  if not _adapter then return end
  if is_paused() then return end
  if cursor_in_tree() then return end
  if _cfg.only_if_open and not tree_is_open() then return end

  -- Fast path: the file is already rendered (its parent dirs are expanded) —
  -- just move the tree cursor to it (cheap; the adapter caches the path→line map).
  if type(_adapter.get_node_line) == "function"
    and type(_adapter.scroll_to_line) == "function" then
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
      pcall(_adapter.open_reveal, path, 0, root)
    end
  end
end

local function schedule_reveal(path)
  local uv = vim.uv or vim.loop
  if _timer then pcall(function() _timer:stop() end)
  else _timer = uv.new_timer() end
  _timer:start(_cfg.debounce_ms, 0, vim.schedule_wrap(function()
    do_reveal(path)
  end))
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
  local path  = vim.api.nvim_buf_get_name(bufnr)
  if path and path ~= "" and vim.fn.filereadable(path) == 1 then
    do_reveal(path)
  end
end

---@return boolean
function M.is_paused()
  return is_paused()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeAutoRevealConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_auto_reveal", true)

  au.acmd("BufEnter", {
    group    = _augroup,
    callback = function(ev)
      if should_ignore(ev.buf) then return end
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if path and path ~= "" and vim.fn.filereadable(path) == 1 then
        schedule_reveal(path)
      end
    end,
  })

  -- Auto-pause when user enters the tree window
  au.acmd("WinEnter", {
    group    = _augroup,
    callback = function()
      local ft = vim.bo.filetype
      if ft == "neo-tree" or ft == "NvimTree" then
        -- Short pause so that the reveal triggered by WinEnter doesn't
        -- immediately jump again when the user leaves the tree
        M.pause(500)
      end
    end,
  })

end

function M.teardown()
  _adapter = nil
  _paused_until = 0
  if _timer then
    pcall(function() _timer:stop(); _timer:close() end)
    _timer = nil
  end
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
