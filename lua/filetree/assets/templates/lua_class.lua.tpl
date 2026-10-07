---@module '${module}'
--- Template for a new Lua class module, instantiated via `:new()`.

---@class ${filename}
local ${filename} = {}
${filename}.__index = ${filename}

---Create a new ${filename} instance.
---@return ${filename}
function ${filename}.new()
  return setmetatable({}, ${filename})
end

return ${filename}
