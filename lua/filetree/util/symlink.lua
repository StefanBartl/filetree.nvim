---@module 'filetree.util.symlink'
---@brief Fresh symlink-state helpers that work off a bare path string — no
--- adapter node required. `features.ui.node_info`'s own broken-symlink
--- detection predates this and stays as-is (it already has the node's lstat
--- to hand); this module is for callers that only have a path, e.g. a
--- `marks.get_marked()` entry or a raw usercmd argument (trash's
--- symlink-aware confirm wording, `:Filetree symlink check/repair/delete`).

local uv = vim.uv or vim.loop

local M = {}

---True when `path` is itself a symlink (lstat sees the dirent, not what it
---points to) — regardless of whether the target exists.
---@param path string
---@return boolean
function M.is_link(path)
  local lst = uv.fs_lstat(path)
  return lst ~= nil and lst.type == "link"
end

---The raw, on-disk link target of `path` (not resolved against cwd), or nil
---when `path` is not a link or the link could not be read.
---@param path string
---@return string?
function M.read_target(path)
  local ok, target = pcall(uv.fs_readlink, path)
  if ok and type(target) == "string" and target ~= "" then return target end
  return nil
end

---True when `path` is a symlink whose target does not resolve (dangling).
---False for anything that is not a symlink at all, and false for a symlink
---that resolves fine.
---@param path string
---@return boolean
function M.is_broken(path)
  local lst = uv.fs_lstat(path)
  if not lst or lst.type ~= "link" then return false end
  return uv.fs_stat(path) == nil
end

return M
