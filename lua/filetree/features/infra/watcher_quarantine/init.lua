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
  enabled             = false,
  duration_ms         = 500,
  silent              = true,
  patch_neotree_watch = true,   -- wrap neo-tree's fs_watch callbacks to swallow EPERM
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

-- ── Neo-tree fs_watch patch (source-level EPERM suppression) ────────────────────
--
-- Complements the notify-based quarantine: instead of only hiding EPERM *messages*
-- during timed windows, this wraps neo-tree's own watcher callbacks so EPERM /
-- EACCES from libuv fs events (common on Windows when a watched file is deleted or
-- moved) never propagate into an error at all. Adapted from the neo-tree config's
-- utils/event_patch. Applied once; future watch_folder() calls get wrapped callbacks.

---@type boolean
local _neotree_patched = false

---Return true for libuv permission errors that are safe to swallow.
---@param s string?
---@return boolean
local function is_perm_error(s)
  if type(s) ~= "string" then return false end
  return s:match("EPERM") ~= nil
    or s:match("EACCES") ~= nil
    or s:match("permission denied") ~= nil
end

---Wrap a watcher callback so permission errors are suppressed.
---@param original function
---@return function
local function wrap_callback(original)
  return function(err, fname)
    if err then
      if is_perm_error(err) then return end
      return original(err, fname)
    end
    local ok, result = pcall(original, err, fname)
    if not ok then
      if is_perm_error(tostring(result)) then return nil end
      error(result)
    end
    return result
  end
end

---Patch neo-tree's fs_watch.watch_folder so new watchers get wrapped callbacks.
---Safe to call repeatedly; no-op if neo-tree's fs_watch module is unavailable.
---@return boolean ok
function M.patch_neotree_watch()
  if _neotree_patched then return true end

  local ok, fs_watch = pcall(require, "neo-tree.sources.filesystem.lib.fs_watch")
  if not ok or type(fs_watch) ~= "table" then return false end

  local original_watch_folder = fs_watch.watch_folder
  if type(original_watch_folder) ~= "function" then return false end

  fs_watch.watch_folder = function(path, callback)
    if type(callback) == "function" then
      callback = wrap_callback(callback)
    end
    return original_watch_folder(path, callback)
  end

  _neotree_patched = true
  if not _cfg.silent then
    notify.debug("neo-tree fs_watch patched for EPERM suppression")
  end
  return true
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
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)

  -- Only useful on Windows / WSL where EPERM is common.
  local relevant = platform.is_windows() or platform.is_wsl()
  if not relevant then
    if not _cfg.silent then
      notify.info("watcher_quarantine: no-op on non-Windows platform")
    end
    return
  end

  -- Neo-tree-specific: wrap fs_watch callbacks at the source. neo-tree loads
  -- fs_watch lazily, so defer until after startup and guard with pcall.
  if _cfg.patch_neotree_watch and adapter and adapter.name == "neotree" then
    vim.defer_fn(function() pcall(M.patch_neotree_watch) end, 100)
  end
end

function M.teardown()
  M.exit()
  _cfg.enabled = false
end

return M
