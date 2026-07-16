---@module 'filetree.util.fs'
---@brief Recursive filesystem traversal. Delegates the walk itself to
--- lib.nvim.fs.collect_recursive (same libuv fs_scandir/fs_scandir_next
--- approach, plus proper subtree pruning via its ignore predicate).

local M = {}

---Adapt this module's `ignore_fn(name)` (bare entry name) to lib.nvim's
---`ignore(abs_path, is_dir)` (full path) shape.
---@param ignore_fn fun(name: string): boolean
---@return fun(abs_path: string, is_dir: boolean): boolean
local function adapt_ignore(ignore_fn)
  return function(abs_path)
    local name = abs_path:match("([^/\\]+)$") or abs_path
    return ignore_fn(name)
  end
end

---Collect files or folders recursively under root_path.
---@param root_path    string
---@param collect_type "files"|"folders"
---@param ignore_fn?   fun(name:string):boolean  Return true to skip an entry.
---@return string[]  Absolute paths.
function M.collect_recursive(root_path, collect_type, ignore_fn)
  local collect = require("lib.nvim.fs.collect_recursive")
  local opts = ignore_fn and { ignore = adapt_ignore(ignore_fn) } or nil

  if collect_type == "files" then
    return collect.files(root_path, opts)
  elseif collect_type == "folders" then
    local dirs = collect.dirs(root_path, opts)
    -- lib.nvim's dirs() only returns descendants; this module's own prior
    -- version also included root_path itself in "folders" results.
    if vim.fn.isdirectory(root_path) == 1 then
      table.insert(dirs, 1, root_path)
    end
    return dirs
  end

  return {}
end

---Convenience wrapper: collect files only.
---@param root_path string
---@param ignore_fn? fun(name:string):boolean
---@return string[]
function M.collect_files(root_path, ignore_fn)
  return M.collect_recursive(root_path, "files", ignore_fn)
end

---Convenience wrapper: collect directories only (includes root_path itself).
---@param root_path string
---@param ignore_fn? fun(name:string):boolean
---@return string[]
function M.collect_folders(root_path, ignore_fn)
  return M.collect_recursive(root_path, "folders", ignore_fn)
end

return M
