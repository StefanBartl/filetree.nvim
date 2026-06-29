---@module 'filetree.features.safety'
---@brief File operation safety layer — backup and dry-run support.
---@description
--- Exposes M.before_delete(path) and M.before_move(src, dst) which other code
--- calls before destructive operations. Works entirely at the filesystem level;
--- no tree-API dependencies.

local backup = require("filetree.features.safety.backup")
local notify = require("filetree.util.notify").create("[filetree.safety]")

local M = {}

---@type FiletreeSafetyConfig
local _cfg = {}

---@param config FiletreeSafetyConfig
---@param _adapter FiletreeAdapter  (unused — safety is adapter-agnostic)
function M.setup(config, _adapter)
  if not config.enabled then return end
  _cfg = config
  backup.init(config)
end

---Call before deleting a file or directory.
---Creates a backup and returns its path.
---@param path string  Absolute path being deleted.
---@return string?     Backup path, or nil if backup was not created.
function M.before_delete(path)
  if not _cfg.enabled then return nil end
  if _cfg.dry_run then
    notify.info("[dry-run] delete: " .. path)
    return path
  end
  return backup.create(path)
end

---Call before moving/renaming a file.
---@param src string
---@param _dst string  (logged but not backed up separately — src is the risk)
---@return string?     Backup path, or nil if backup was not created.
function M.before_move(src, _dst)
  if not _cfg.enabled then return nil end
  if _cfg.dry_run then
    notify.info("[dry-run] move: " .. src .. " → " .. tostring(_dst))
    return src
  end
  return backup.create(src)
end

---List all existing backups.
---@return string[]
function M.list_backups()
  return backup.list()
end

---Toggle dry-run mode at runtime.
function M.toggle_dry_run()
  _cfg.dry_run = not _cfg.dry_run
  notify.info("dry-run: " .. (_cfg.dry_run and "ON" or "OFF"))
end

function M.teardown()
  _cfg = {}
end

return M
