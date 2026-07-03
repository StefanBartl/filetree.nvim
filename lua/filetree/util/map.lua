---@module 'filetree.util.map'
---@brief Keymap helper — delegates to lib.nvim.map, falls back to vim.keymap.set.
---@description
--- `lib.nvim.map` is a drop-in superset of `vim.keymap.set` (same first four
--- args, plus an optional `desc` as the 5th and sensible noremap/silent
--- defaults). Requiring this module returns a callable with that signature:
---
---   local map = require("filetree.util.map")
---   map("n", lhs, rhs, { buffer = buf }, "Filetree: …")
---
--- When lib.nvim is present its implementation is used verbatim (so filetree
--- shares the user's map conventions); otherwise a local fallback keeps the same
--- signature so call sites never change.

local ok, libmap = pcall(require, "lib.nvim.map")
if ok and type(libmap) == "function" then
  return libmap
end

---@param modes string|string[]
---@param lhs string
---@param rhs string|function
---@param opts table|nil
---@param desc string|nil
return function(modes, lhs, rhs, opts, desc)
  opts = opts or {}
  if type(desc) == "string" then opts.desc = desc end
  if opts.silent == nil then opts.silent = true end
  vim.keymap.set(modes, lhs, rhs, opts)
end
