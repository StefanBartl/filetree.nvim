---@module 'filetree.util.conflict'
---@brief Destination-collision helpers shared by the features that write a
--- path someone else may already occupy (copy_move's paste, move).
---@description
---   local conflict = require("filetree.util.conflict")
---   conflict.exists(p)                                  -- file or directory
---   conflict.remove_existing(p)                         -- for "Overwrite"
---   conflict.unique_name(dir, "a.txt", claimed, false)  -- for "Keep both"

local M = {}

---Whether a path already exists as either a file or a directory.
---@param path string
---@return boolean
function M.exists(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

---Delete an existing destination (file or directory tree) with libuv/Vim
---builtins — the "Overwrite" resolution's prep step, run just before the
---copy/move that replaces it. No shell involved.
---@param path string
---@return boolean ok
function M.remove_existing(path)
  if vim.fn.isdirectory(path) == 1 then
    return vim.fn.delete(path, "rf") == 0
  end
  return vim.fn.delete(path) == 0
end

---First `name (N).ext` that collides with neither an existing path in `dir`
---nor a name already handed out earlier in the same batch (`claimed`).
---Directories don't get extension-splitting — a directory name has no
---extension to preserve.
---@param dir string
---@param name string
---@param claimed table<string, true>
---@param is_dir boolean
---@return string
function M.unique_name(dir, name, claimed, is_dir)
  local base, ext
  if not is_dir then
    base, ext = name:match("^(.*)(%.[^./\\]+)$")
  end
  if not base or base == "" then
    base, ext = name, ""
  end
  local candidate
  local n = 2
  repeat
    candidate = string.format("%s (%d)%s", base, n, ext)
    n = n + 1
  until not claimed[candidate] and not M.exists(dir .. "/" .. candidate)
  claimed[candidate] = true
  return candidate
end

return M
