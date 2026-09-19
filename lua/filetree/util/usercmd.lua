---@module 'filetree.util.usercmd'
--- User-command helpers — delegate to lib.nvim.bindings.usercmd (a hard dependency).
---
--- `lib.nvim.bindings.usercmd.create(name, callback, opts)` is a drop-in for
--- `nvim_create_user_command`, so filetree shares the user's usercmd conventions.
---
---   local usercmd = require("filetree.util.usercmd")
---   usercmd.create("Filetree", handler, { nargs = "*", complete = comp })
---   usercmd.del("Filetree")

local lib = require("lib.nvim.bindings.usercmd")

local M = {}

---Create a user command.
---@param name     string
---@param callback string|fun(args: table)
---@param opts     table|nil
function M.create(name, callback, opts)
  return lib.create(name, callback, opts or {})
end

---Delete a user command, ignoring errors.
---@param name string
function M.del(name)
  pcall(vim.api.nvim_del_user_command, name)
end

return M
