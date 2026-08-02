---@module '${module}'
---@brief

---@class ${filename}
local ${filename} = {}
${filename}.__index = ${filename}

---@return ${filename}
function ${filename}.new()
  return setmetatable({}, ${filename})
end

return ${filename}
