---@module 'filetree.refs.registry'
--- Provider registry for the reference engine.
---
--- Built-in providers register themselves here at load time; third parties can
--- add their own via `require("filetree.refs").register(provider)` — the same
--- contract, no privileged access:
---
---   refs.register({
---     name = "rust",
---     plan = function(old_path, ctx)
---       ...
---       return { needles = {...}, extensions = {"rs"}, extract = ..., retarget = ... }
---     end,
---   })
---
--- Order matters only for display (the chooser summarizes "5 markdown, 2 lua"),
--- so providers are kept in registration order.

local M = {}

---@type FiletreeRefProvider[]
local _providers = {}

---@param provider FiletreeRefProvider
---@return boolean ok, string? err
function M.register(provider)
  if type(provider) ~= "table" or type(provider.name) ~= "string" then
    return false, "provider needs a string `name`"
  end
  if type(provider.plan) ~= "function" then
    return false, "provider '" .. provider.name .. "' needs a `plan` function"
  end
  for i, p in ipairs(_providers) do
    if p.name == provider.name then
      _providers[i] = provider -- re-registration replaces, so reloading works
      return true, nil
    end
  end
  _providers[#_providers + 1] = provider
  return true, nil
end

---All registered providers, in registration order.
---@return FiletreeRefProvider[]
function M.all()
  return _providers
end

---Providers enabled by `cfg.providers` (an unlisted provider — e.g. a
---third-party one — counts as enabled; only an explicit `false` turns one off).
---@param cfg FiletreeRefsConfig
---@return FiletreeRefProvider[]
function M.enabled(cfg)
  local out = {}
  local flags = (cfg and cfg.providers) or {}
  for _, p in ipairs(_providers) do
    if flags[p.name] ~= false then out[#out + 1] = p end
  end
  return out
end

---@param name string
---@return FiletreeRefProvider|nil
function M.get(name)
  for _, p in ipairs(_providers) do
    if p.name == name then return p end
  end
  return nil
end

return M
