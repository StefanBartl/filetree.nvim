---@module 'filetree.util.autocmd'
---@brief Autocmd/augroup helpers — delegate to lib.nvim.autocmd, with fallbacks.
---@description
--- Thin wrappers so filetree shares lib.nvim's autocmd conventions when present,
--- and still runs standalone otherwise. Signatures:
---
---   local au = require("filetree.util.autocmd")
---   local grp = au.group("filetree_marks", true)          -- clear = true
---   au.create(event, callback, { group = grp, pattern = … })

local _ok, lib = pcall(require, "lib.nvim.autocmd")
local has_lib = _ok and type(lib) == "table"

local M = {}

---Create (or clear) a named augroup and return its id.
---
---Deliberately NOT delegated to lib.nvim.autocmd.group(): that function caches
---the returned id per name forever and never re-validates it, so once a
---feature's own re-setup cycle deletes its previous augroup by id (the pattern
---used throughout filetree — del_group(_augroup) then group(name, true) again),
---lib's cache keeps handing back the now-dangling id, and the next
---nvim_create_autocmd call fails with "Invalid 'group': N". filetree calls
---setup() more than once in the same process routinely (re-setup, tests), so
---this goes straight to the native API instead, which is idempotent by name.
---@param name  string
---@param clear boolean|nil  Default true.
---@return integer
function M.group(name, clear)
  if clear == nil then clear = true end
  return vim.api.nvim_create_augroup(name, { clear = clear })
end

---Create an autocmd. `callback` is passed as the handler; `opts` carries
---group/pattern/once/nested/desc (as with nvim_create_autocmd).
---@param event  string|string[]
---@param callback fun(args: table)
---@param opts   table|nil
function M.create(event, callback, opts)
  opts = opts or {}
  if has_lib and type(lib.create) == "function" then
    return lib.create(event, callback, opts)
  end
  local o = vim.tbl_extend("force", {}, opts)
  o.callback = callback
  return vim.api.nvim_create_autocmd(event, o)
end

---Drop-in replacement for `nvim_create_autocmd`: `opts` carries the callback (or
---command) plus group/pattern/etc., exactly as the native API. Lets call sites
---migrate with a pure textual swap; routes through lib.nvim when its callback
---form is available.
---@param event string|string[]
---@param opts  table  Native nvim_create_autocmd opts (with `callback`/`command`).
---@return integer
function M.acmd(event, opts)
  opts = opts or {}
  if has_lib and type(lib.create) == "function" and type(opts.callback) == "function" then
    local o = vim.tbl_extend("force", {}, opts)
    local cb = o.callback
    o.callback = nil
    return lib.create(event, cb, o)
  end
  return vim.api.nvim_create_autocmd(event, opts)
end

---Delete an augroup by id, ignoring errors.
---@param id integer|nil
function M.del_group(id)
  if id then pcall(vim.api.nvim_del_augroup_by_id, id) end
end

return M
