---@module 'filetree.features.cwd_sync'
---@brief Auto-reveal the current buffer's file in the tree on buffer change.
---@description
--- Debounced BufEnter/WinEnter handler that calls adapter.open_reveal() when
--- the active buffer changes to a real file. Pauses automatically when the
--- user navigates manually in the tree (detected via cursor movement inside
--- the tree window).

local notify = require("filetree.util.notify").create("[filetree.cwd_sync]")

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

local function do_reveal(path)
  if not _adapter then return end
  if paused() then return end
  if S.last_path == path then return end

  S.last_path = path
  local ok = _adapter.open_reveal(path, _cfg.parent_levels or 0)
  if not ok then
    notify.warn("reveal failed for: " .. path)
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
  local path = vim.fn.expand("%:p")
  if path == "" or vim.fn.filereadable(path) == 0 then return end

  local uv = vim.uv or vim.loop
  S.timer = uv.new_timer()
  S.timer:start(_cfg.debounce_ms or 150, 0, vim.schedule_wrap(function()
    cancel_timer()
    do_reveal(path)
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
