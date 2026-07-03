---@module 'filetree.util.usercmd'
---@brief User-command helpers — delegate to lib.nvim.usercmd, with fallbacks.
---@description
--- `lib.nvim.usercmd.create(name, callback, opts)` is a drop-in for
--- `nvim_create_user_command`, so filetree shares the user's usercmd conventions
--- when lib.nvim is present and still works standalone otherwise.
---
---   local usercmd = require("filetree.util.usercmd")
---   usercmd.create("Filetree", handler, { nargs = "*", complete = comp })
---   usercmd.del("Filetree")

local _ok, lib = pcall(require, "lib.nvim.usercmd")
local has_lib = _ok and type(lib) == "table" and type(lib.create) == "function"

local M = {}

---Create a user command.
---@param name     string
---@param callback string|fun(args: table)
---@param opts     table|nil
function M.create(name, callback, opts)
  if has_lib then
    return lib.create(name, callback, opts or {})
  end
  return vim.api.nvim_create_user_command(name, callback, opts or {})
end

---Delete a user command, ignoring errors.
---@param name string
function M.del(name)
  pcall(vim.api.nvim_del_user_command, name)
end

return M
