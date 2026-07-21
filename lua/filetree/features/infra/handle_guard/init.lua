---@module 'filetree.features.handle_guard'
---@brief Release neo-tree's directory-watcher handles before destructive fileops.
---@description
--- Thin wiring around `lib.nvim.neotree.watch`. On Windows, neo-tree's libuv
--- directory watchers keep the directory open at the OS level and are never
--- `:close()`d, so renaming/deleting a watched directory intermittently fails
--- with EPERM / ERROR_SHARING_VIOLATION. This feature installs the shared watch
--- registry so the fileops (smart_rename, copy_move, trash, …) can call
--- `M.release(path)` — via `lib.nvim.cross.fs.mutate`'s `on_retry` hook — to
--- close the offending handle and let the retry succeed.
---
--- Unlike `watcher_quarantine` (which only suppresses the EPERM *message*), this
--- fixes the cause: it actually frees the handle. neo-tree adapter + Windows/WSL
--- only; a no-op everywhere else (`release` then releases nothing, so the
--- fileops' hook stays safe to pass unconditionally).
---
--- API:
---   M.release(paths)   Close watcher handle(s) on paths + subpaths. Safe no-op
---                      when not installed.

local platform = require("filetree.util.platform")

local M = {}

---@type FiletreeHandleGuardConfig
local _cfg = { enabled = false }

---@return table? watch  The lib.nvim.neotree.watch module, or nil if absent.
local function watch_mod()
  local ok, watch = pcall(require, "lib.nvim.neotree.watch")
  if ok and type(watch) == "table" then return watch end
  return nil
end

---Close the file-watcher handle(s) on `paths` (and every watched subpath) so a
---mutation there is not blocked by an open handle. Safe to call always: a no-op
---when the feature is off / not installed / lib.nvim is absent.
---@param paths string|string[]
---@return integer released
function M.release(paths)
  local watch = watch_mod()
  if not watch then return 0 end
  local ok, n = pcall(watch.release, paths)
  return ok and n or 0
end

---Whether the watch registry patch is actually installed (feature on, neo-tree,
---Windows/WSL, and neo-tree's fs_watch was reachable).
---@return boolean
function M.installed()
  local watch = watch_mod()
  return watch ~= nil and watch.installed() == true
end

---Snapshot of the currently tracked watcher handles, for `:Filetree handles`
---and the healthcheck. Empty when nothing is installed/tracked.
---@return { path: string, active: boolean, exists: boolean }[]
function M.handles()
  local watch = watch_mod()
  if not watch then return {} end
  local ok, list = pcall(watch.list)
  return ok and list or {}
end

---@param config FiletreeHandleGuardConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = config

  -- The whole mechanism is neo-tree-specific (it patches a neo-tree internal)
  -- and only fixes a Windows/WSL lock, so it is inert elsewhere.
  if not (platform.is_windows() or platform.is_wsl()) then return end
  if not adapter or adapter.name ~= "neotree" then return end

  -- neo-tree loads fs_watch lazily, so its module may not exist yet at setup()
  -- time; defer and pcall, mirroring watcher_quarantine's own install timing.
  vim.defer_fn(function()
    local watch = watch_mod()
    if watch then pcall(watch.install) end
  end, 100)
end

function M.teardown() end

return M
