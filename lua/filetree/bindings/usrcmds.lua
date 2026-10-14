---@module 'filetree.bindings.usrcmds'
--- The `:Filetree ...` user-command catalog: the sub-command paths, read live
--- from the dispatcher tree in `filetree.commands` so the list never drifts.

local M = {}

---Return every registered `:Filetree` sub-command path.
---@return string[]
function M.paths()
  local ok, commands = pcall(require, "filetree.commands")
  if not ok or type(commands.command_paths) ~= "function" then return {} end
  return commands.command_paths()
end

return M
