---@module 'filetree.adapter'
---@brief Adapter registry: load, resolve, and cache the active filetree adapter.

local notify = require("filetree.util.notify").create("[filetree.adapter]")

local M = {}

---@type table<string, FiletreeAdapter>
local _registry = {}

---@type FiletreeAdapter?
local _active = nil

---Register a custom adapter.
---Adapters shipped with the plugin register themselves via their own module.
---@param adapter FiletreeAdapter
function M.register(adapter)
  assert(type(adapter.name) == "string", "adapter.name must be a string")
  _registry[adapter.name] = adapter
end

---Resolve and cache the active adapter by name or "auto".
---"auto" picks the first registered adapter whose is_available() returns true.
---@param name FiletreeAdapterName|"auto"
---@return FiletreeAdapter?
function M.resolve(name)
  if name ~= "auto" then
    -- Lazy-load built-in adapter module if not yet registered
    if not _registry[name] then
      local ok, mod = pcall(require, "filetree.adapter." .. name)
      if ok and mod then
        _registry[name] = mod
      end
    end
    local adapter = _registry[name]
    if not adapter then
      notify.error("Unknown adapter: " .. name)
      return nil
    end
    if not adapter.is_available() then
      notify.warn("Adapter '" .. name .. "' is not available (plugin not loaded?)")
      return nil
    end
    _active = adapter
    return adapter
  end

  -- auto: try known built-ins in priority order
  local candidates = { "neotree", "nvimtree", "netrw", "oil" }
  for _, candidate in ipairs(candidates) do
    if not _registry[candidate] then
      pcall(require, "filetree.adapter." .. candidate)
    end
    local adapter = _registry[candidate]
    if adapter and adapter.is_available() then
      _active = adapter
      return adapter
    end
  end

  notify.error("No supported filetree plugin found (tried: " .. table.concat(candidates, ", ") .. ")")
  return nil
end

---Return the currently active adapter (set by resolve()).
---@return FiletreeAdapter?
function M.get()
  return _active
end

---Return all registered adapter names.
---@return string[]
function M.list()
  local names = {}
  for name in pairs(_registry) do
    names[#names + 1] = name
  end
  return names
end

return M
