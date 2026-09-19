---@module 'filetree.util.map'
---@brief Keymap helper — re-exports lib.nvim.bindings.keymap (a hard dependency).
---@description
--- `lib.nvim.bindings.keymap` is a drop-in superset of `vim.keymap.set` (same first four
--- args, plus an optional `desc` as the 5th and sensible noremap/silent
--- defaults). Requiring this module returns that callable directly, so filetree
--- shares the user's map conventions and every bound key is recorded in lib's
--- registry (which `bindings.live()` reads back):
---
---   local map = require("filetree.util.map")
---   map("n", lhs, rhs, { buffer = buf }, "Filetree: …")

return require("lib.nvim.bindings.keymap")
