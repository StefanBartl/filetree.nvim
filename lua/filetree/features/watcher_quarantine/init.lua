---@module 'filetree.features.watcher_quarantine'
---@brief Suppress file-watcher EPERM errors on Windows around destructive operations.
---@description
--- On Windows, libuv file watchers sometimes emit EPERM errors when a file
--- or directory is deleted or moved while the watcher is active. This feature
--- temporarily suspends watching for a configurable duration and suppresses
--- the resulting error notifications, then restores normal operation.
---
--- API:
---   M.enter(duration_ms, paths?)   Start quarantine period.
---   M.exit()                       End quarantine immediately.
---   M.is_active() → boolean
---   M.wrap(fn, duration_ms)        Execute fn inside an auto quarantine.

local notify   = require("filetree.util.notify").create("[filetree.watcher_quarantine]")
local platform = require("filetree.util.platform")

local M = {}

---@type FiletreeWatcherQuarantineConfig
local _cfg = {
  enabled     = false,
  duration_ms = 500,
  silent      = true,
}

---@class QuarantineState
---@field active         boolean
---@field until_ms       number    vim.uv.now() timestamp after which quarantine ends.
---@field suspended_paths table<string, boolean>
---@field original_notify function?

---@type QuarantineState
local S = {
  active          = false,
  until_ms        = 0,
  suspended_paths = {},
  original_notify = nil,
}

---@type any?
local _timer = nil

local function cancel_timer()
  if _timer then
    pcall(function()
      _timer:stop()
      _timer:close()
    end)
    _timer = nil
  end
end

local function restore_notify()
  if S.original_notify then
    vim.notify = S.original_notify
    S.original_notify = nil
  end
end

local function patch_notify()
  if S.original_notify then return end  -- already patched
  S.original_notify = vim.notify
  vim.notify = function(msg, level, opts)
    -- Suppress EPERM noise from file watchers during quarantine
    if S.active and type(msg) == "string" and msg:find("EPERM") then
      return
    end
    S.original_notify(msg, level, opts)
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Enter quarantine for `duration_ms` milliseconds.
---Optionally restrict suppression to specific paths.
---@param duration_ms? integer
---@param paths?       string[]  Paths to quarantine. nil = quarantine all.
function M.enter(duration_ms, paths)
  if not _cfg.enabled then return end

  cancel_timer()
  S.active    = true
  S.until_ms  = (vim.uv or vim.loop).now() + (duration_ms or _cfg.duration_ms)
  S.suspended_paths = {}

  if paths then
    for _, p in ipairs(paths) do S.suspended_paths[p] = true end
  end

  patch_notify()

  if not _cfg.silent then
    notify.debug("quarantine entered (" .. (duration_ms or _cfg.duration_ms) .. "ms)")
  end

  local uv = vim.uv or vim.loop
  _timer = uv.new_timer()
  _timer:start(duration_ms or _cfg.duration_ms, 0, vim.schedule_wrap(function()
    M.exit()
  end))
end

---End quarantine immediately.
function M.exit()
  cancel_timer()
  S.active    = false
  S.until_ms  = 0
  S.suspended_paths = {}
  restore_notify()
end

---@return boolean
function M.is_active()
  if not S.active then return false end
  -- Auto-expire if timer somehow missed
  if (vim.uv or vim.loop).now() >= S.until_ms then
    M.exit()
    return false
  end
  return true
end

---Return true when `path` is quarantined.
---@param path string
---@return boolean
function M.is_path_quarantined(path)
  if not M.is_active() then return false end
  if vim.tbl_isempty(S.suspended_paths) then return true end  -- global quarantine
  return S.suspended_paths[path] == true
end

---Execute `fn` inside a quarantine window and return its result.
---@param fn          fun(): any
---@param duration_ms? integer
---@return any
function M.wrap(fn, duration_ms)
  M.enter(duration_ms)
  local ok, result = pcall(fn)
  -- quarantine self-cancels via timer; we do not force-exit here
  -- so the watcher has time to settle after fn returns
  if not ok then
    notify.warn("wrapped fn errored: " .. tostring(result))
  end
  return result
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeWatcherQuarantineConfig
---@param _adapter FiletreeAdapter
function M.setup(config, _adapter)
  if not config.enabled then return end
  -- Only useful on Windows / WSL where EPERM is common
  if not platform.is_windows() and not platform.is_wsl() then
    if not _cfg.silent then
      notify.info("watcher_quarantine: no-op on non-Windows platform")
    end
  end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)
end

function M.teardown()
  M.exit()
  _cfg.enabled = false
end

return M
