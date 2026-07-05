---@module 'filetree.features.cwd_sync'
---@brief Keep Neovim's cwd (and the tree) in sync with the current buffer.
---@description
--- Debounced BufEnter/WinEnter handler for the active buffer's file:
---
---   1. change_dir (default true): if the file is not under the current cwd,
---      silently `chdir` to its project root (via the project_root feature —
---      falls back to the file's own parent directory when no root marker is
---      found, or when use_project_root is false) — never prompts.
---   2. Refreshes the tree adapter so its cwd/root display updates.
---   3. Calls adapter.open_reveal() to scroll/highlight the file in the tree
---      (unchanged behaviour from before; parent_levels still governs how far
---      the reveal call itself ascends).
---
--- Pauses automatically when the user navigates manually in the tree (detected
--- via cursor movement inside the tree window).

local notify = require("filetree.util.notify").create("[filetree.cwd_sync]")
local path = require("filetree.util.path")

local au  = require("filetree.util.autocmd")
local M = {}

---@class CwdSyncState
---@field timer           any?     Pending uv timer handle.
---@field last_path       string?  Last file we revealed.
---@field paused_until    number   Timestamp (uv.hrtime) after which sync resumes.
---@field user_navigated  boolean  Set when the user moved inside the tree manually.

---@type CwdSyncState
local S = {
  timer          = nil,
  last_path      = nil,
  paused_until   = 0,
  user_navigated = false,
}

---@type integer?
local _augroup = nil

---@type FiletreeCwdSyncConfig
local _cfg = {}

---@type FiletreeAdapter?
local _adapter = nil

local function paused()
  local uv = vim.uv or vim.loop
  return uv.hrtime() < S.paused_until
end

local function pause(ms)
  local uv = vim.uv or vim.loop
  S.paused_until = uv.hrtime() + (ms or 2000) * 1e6
end

local function cancel_timer()
  if S.timer then
    pcall(function()
      S.timer:stop()
      S.timer:close()
    end)
    S.timer = nil
  end
end

---Compare two directories for equality, ignoring separator style and a
---trailing slash.
---@param a string
---@param b string
---@return boolean
local function same_dir(a, b)
  local na = path.slashify(a):gsub("/$", "")
  local nb = path.slashify(b):gsub("/$", "")
  return na == nb
end

---Resolve the directory `file` should put Neovim's cwd in: the detected
---project root (default), or just the file's own parent directory.
---@param file string
---@return string
local function target_dir(file)
  if _cfg.use_project_root ~= false then
    local registry = require("filetree.features")
    local proot = registry.require("project_root")
    if proot then
      local ok, root = pcall(proot.find, file)
      if ok and root and root ~= "" then return root end
    end
  end
  return path.parent(file)
end

---Silently `chdir` to `file`'s target directory when it differs from the
---current cwd, then refresh the tree adapter so its cwd/root display updates.
---Never prompts — that is the whole point of "sync".
---@param file string
local function sync_cwd(file)
  if _cfg.change_dir == false then return end
  local dir = target_dir(file)
  if dir == "" or same_dir(dir, vim.fn.getcwd()) then return end

  local ok = pcall(vim.fn.chdir, dir)
  if not ok then
    notify.warn("could not change cwd to: " .. dir)
    return
  end

  if _adapter and type(_adapter.refresh) == "function" then
    pcall(_adapter.refresh)
  end
end

local function do_reveal(path_)
  if not _adapter then return end
  if paused() then return end
  if S.last_path == path_ then return end

  S.last_path = path_
  sync_cwd(path_)

  local ok = _adapter.open_reveal(path_, _cfg.parent_levels or 0)
  if not ok then
    notify.warn("reveal failed for: " .. path_)
    return
  end

  if _cfg.keep_focus then
    -- Restore focus to the editor window after a brief delay
    local cur_win = vim.api.nvim_get_current_win()
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(cur_win) then
        vim.api.nvim_set_current_win(cur_win)
      end
    end, 50)
  end
end

local function debounced_reveal()
  cancel_timer()
  local file = vim.fn.expand("%:p")
  if file == "" or vim.fn.filereadable(file) == 0 then return end

  local uv = vim.uv or vim.loop
  S.timer = uv.new_timer()
  S.timer:start(_cfg.debounce_ms or 150, 0, vim.schedule_wrap(function()
    cancel_timer()
    do_reveal(file)
  end))
end

---@param config FiletreeCwdSyncConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = config
  _adapter = adapter

  if _augroup then
    au.del_group(_augroup)
  end
  _augroup = au.group("filetree_cwd_sync", true)

  au.acmd({ "BufEnter", "WinEnter" }, {
    group    = _augroup,
    callback = function()
      -- Skip if cursor is inside the tree window
      local tree_winid = adapter.get_winid()
      if tree_winid and vim.api.nvim_get_current_win() == tree_winid then
        pause(2000) -- user is navigating manually
        return
      end
      debounced_reveal()
    end,
  })
end

function M.teardown()
  cancel_timer()
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
  S.last_path      = nil
  S.paused_until   = 0
  S.user_navigated = false
end

---Manually pause auto-reveal for `ms` milliseconds.
---@param ms integer
function M.pause(ms)
  pause(ms)
end

return M
