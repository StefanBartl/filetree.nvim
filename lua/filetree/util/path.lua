---@module 'filetree.util.path'
---@brief Path normalization and conversion utilities.

local M = {}

---Expand to absolute path and normalize separators to the OS default.
---@param p string
---@return string
function M.normalize(p)
  p = vim.fn.fnamemodify(p, ":p")
  p = p:gsub('"', ""):gsub("'", "")
  return p
end

---Return the parent directory of a path.
---@param p string
---@return string
function M.parent(p)
  return vim.fn.fnamemodify(p, ":h")
end

---Return the filename (tail) of a path.
---@param p string
---@return string
function M.basename(p)
  return vim.fn.fnamemodify(p, ":t")
end

---Return the path relative to a base directory.
---Returns the original path when it is not under base.
---@param p    string  Absolute path.
---@param base string  Base directory.
---@return string
function M.relative(p, base)
  p    = M.normalize(p)
  base = M.normalize(base)
  if base:sub(-1) ~= "/" then base = base .. "/" end
  if p:sub(1, #base) == base then
    return p:sub(#base + 1)
  end
  return p
end

---Escape a path for use as a vim command argument.
---@param p string
---@return string
function M.fnameescape(p)
  return vim.fn.fnameescape(p)
end

return M
