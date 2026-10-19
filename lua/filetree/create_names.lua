---@module 'filetree.create_names'
--- Name suggestions for the create prompt (`smart_create`, `a`): another
--- plugin registers a provider that, given the folder something is created
--- in, returns the text to pre-fill -- or nil to stay out of it. The first
--- provider with an answer wins, in registration order; a provider that
--- raises is skipped. The prompt stays editable: a suggestion is a default,
--- never a rule.
---
--- Kept apart from the feature module on purpose: a plugin can register at
--- its own setup, before or after filetree's, without filetree being set up
--- or the feature being enabled.
---
--- ```lua
--- require("filetree.create_names").register("casedesk", function(dir)
---   if dir:match("/assets$") then return "03_2026-10-19/" end
--- end)
--- ```

local M = {}

---@alias FiletreeCreateNameProvider fun(dir: string): string|nil

---@type { id: string, fn: FiletreeCreateNameProvider }[]
local providers = {}

--- Register (or replace, by `id`) a provider.
---@param id string
---@param fn FiletreeCreateNameProvider
function M.register(id, fn)
  assert(
    type(id) == "string" and id ~= "",
    "filetree.create_names.register: id must be a non-empty string"
  )
  assert(type(fn) == "function", "filetree.create_names.register: fn must be a function")
  for _, p in ipairs(providers) do
    if p.id == id then
      p.fn = fn
      return
    end
  end
  providers[#providers + 1] = { id = id, fn = fn }
end

--- Drop the provider registered under `id`; a no-op for an unknown one.
---@param id string
function M.unregister(id)
  for i, p in ipairs(providers) do
    if p.id == id then
      table.remove(providers, i)
      return
    end
  end
end

--- The suggestion for a create in `dir` (`/`-separated, no trailing slash),
--- or nil when no provider has one.
---@param dir string
---@return string|nil
function M.suggest(dir)
  for _, p in ipairs(providers) do
    local ok, name = pcall(p.fn, dir)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return nil
end

return M
