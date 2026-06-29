---@module 'filetree.features.safety.backup'
---@brief File backup engine — copies files to a backup directory before destructive operations.

local notify = require("filetree.util.notify").create("[filetree.safety.backup]")
local path   = require("filetree.util.path")

local M = {}

---@type FiletreeSafetyConfig
local _cfg = {}

---@type string  resolved backup directory
local _dir = ""

---Initialize and create the backup directory.
---@param config FiletreeSafetyConfig
function M.init(config)
  _cfg = config
  _dir = config.backup_dir
    or (vim.fn.stdpath("data") .. "/filetree/backups")
  if vim.fn.isdirectory(_dir) == 0 then
    vim.fn.mkdir(_dir, "p")
  end
end

---Return a unique backup destination path for `src`.
---Format: <backup_dir>/<timestamp>_<basename>
---@param src string  Absolute source path.
---@return string
local function backup_path(src)
  local ts    = os.date("%Y%m%d_%H%M%S")
  local base  = path.basename(src)
  return _dir .. "/" .. ts .. "_" .. base
end

---Recursively copy a file or directory.
---Uses vim.fn.system("cp -r …") on POSIX and xcopy on Windows.
---@param src string
---@param dst string
---@return boolean
local function copy(src, dst)
  local platform = require("filetree.util.platform")
  local ok, result
  if platform.is_windows() and not platform.is_wsl() then
    -- xcopy handles both files and directories
    local cmd = string.format('xcopy /E /I /H /Y "%s" "%s"', src, dst)
    ok = os.execute(cmd) == 0
  else
    ok = os.execute(string.format("cp -r %s %s", vim.fn.shellescape(src), vim.fn.shellescape(dst))) == 0
  end
  return ok or false
end

---Create a backup of `src`.
---@param src string  Absolute path of the file or directory to back up.
---@return string?    Path of the created backup, or nil on failure.
function M.create(src)
  if _cfg.dry_run then
    notify.info("[dry-run] would back up: " .. src)
    return src
  end
  if vim.fn.filereadable(src) == 0 and vim.fn.isdirectory(src) == 0 then
    notify.warn("backup: source does not exist: " .. src)
    return nil
  end
  local dst = backup_path(src)
  if not copy(src, dst) then
    notify.error("backup failed: " .. src .. " → " .. dst)
    return nil
  end
  M.prune()
  return dst
end

---Remove oldest backups when count exceeds max_backups.
function M.prune()
  local max = _cfg.max_backups or 5
  local ok, files = pcall(vim.fn.glob, _dir .. "/*", false, true)
  if not ok or not files then return end
  -- Sort by name (timestamp prefix ensures chronological order)
  table.sort(files)
  while #files > max do
    local oldest = table.remove(files, 1)
    if vim.fn.isdirectory(oldest) == 1 then
      pcall(vim.fn.delete, oldest, "rf")
    else
      pcall(vim.fn.delete, oldest)
    end
  end
end

---List all backups (sorted oldest→newest).
---@return string[]
function M.list()
  local ok, files = pcall(vim.fn.glob, _dir .. "/*", false, true)
  if not ok or not files then return {} end
  table.sort(files)
  return files
end

return M
