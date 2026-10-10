---@module 'filetree.util.powershell'
---@brief Escaping for text spliced into a PowerShell single-quoted string.
---@description
--- PowerShell's tokenizer treats not only the ASCII `'` but also U+2018 to
--- U+201B (the typographic single quotes) as single-quote characters, both to
--- open/close a string and as the doubled escape. Doubling only the ASCII one
--- lets a file name such as `it’s.md` close the string early (a parse error at
--- best, injected script text at worst).

local M = {}

---Escape `s` for the inside of a PowerShell `'...'` literal: every quote
---character (`'` and U+2018 to U+201B) is doubled.
---@param s string
---@return string escaped
function M.escape_single(s)
  -- U+2018..U+201B are the UTF-8 sequences E2 80 98..9B.
  local escaped = s:gsub("'", "''"):gsub("\226\128[\152-\155]", "%0%0")
  return escaped
end

return M
