---@module 'filetree.util.autocmd'
---@brief Autocmd/augroup helpers — delegate to lib.nvim.bindings.autocmd (a hard dependency).
---@description
--- Thin wrappers so filetree shares lib.nvim's autocmd conventions and its
--- record-keeping (bindings.autocmds reads that back for `:checkhealth` and
--- the binding catalog). Signatures:
---
---   local au = require("filetree.util.autocmd")
---   local grp = au.group("filetree_marks", true)          -- clear = true
---   au.create(event, callback, { group = grp, pattern = … })

local lib = require("lib.nvim.bindings.autocmd")

local M = {}

---Create (or clear) a named augroup and return its id.
---
---Delegated to lib.nvim.bindings.autocmd.group(): it used not to be, and lib
---cached the returned id per name forever without re-validating it, so once
---a feature's re-setup deleted its previous augroup by id (del_group then
---group(name, true) — the pattern throughout filetree), lib kept handing
---back the dangling id and the next nvim_create_autocmd failed with "Invalid
---'group': N". That was fixed in lib (the cache is verified against
---nvim_get_autocmds now), and delegating again matters for more than
---tidiness: lib drops a group's autocmd records when the group is cleared,
---and going around it left those records describing autocmds that no longer
---fire.
---@param name  string
---@param clear boolean|nil  Default true.
---@return integer
function M.group(name, clear)
  if clear == nil then clear = true end
  return lib.group(name, clear)
end

---Create an autocmd. `callback` is passed as the handler; `opts` carries
---group/pattern/once/nested/desc (as with nvim_create_autocmd).
---@param event  string|string[]
---@param callback fun(args: table)
---@param opts   table|nil
function M.create(event, callback, opts)
  return lib.create(event, callback, opts or {})
end

---Drop-in replacement for `nvim_create_autocmd`: `opts` carries the callback (or
---command) plus group/pattern/etc., exactly as the native API. Lets call sites
---migrate with a pure textual swap; routes through lib.nvim's callback form,
---and straight to the native API for the `command = "…"` form, which lib
---cannot take.
---@param event string|string[]
---@param opts  table  Native nvim_create_autocmd opts (with `callback`/`command`).
---@return integer
function M.acmd(event, opts)
  opts = opts or {}
  if type(opts.callback) == "function" then
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
