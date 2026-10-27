---@module 'filetree.util.dialog'
---@brief The shared dialog (`lib.nvim.ui.dialog`), or ui.kit's `confirm` when lib.nvim predates it.
---@description
--- Every yes/no and choice dialog of this plugin goes through here. `lib.nvim.ui.dialog` is the one wrapper the
--- plugins share (kit answers exactly once, a float that cannot open falls back to `vim.ui.select`). A lib.nvim
--- without it must not break the features that merely load a dialog helper, so the module is resolved on first
--- use and then stands in with ui.kit directly (ui.nvim is a hard dependency).

local M = {}

---@return table dialog  # has `confirm` and `ask`
local function resolve()
  local ok, dialog = pcall(require, "lib.nvim.ui.dialog")
  if ok and type(dialog) == "table" and dialog.confirm and dialog.ask then return dialog end
  local kit = require("ui.kit")
  return {
    confirm = function(opts)
      kit.confirm(opts)
    end,
    ask = function(opts)
      return (kit.ask or kit.confirm)(opts)
    end,
  }
end

---@param opts table  # options of `kit.confirm`
function M.confirm(opts)
  return resolve().confirm(opts)
end

---@param opts table  # options of `kit.ask` (waits behind an open dialog)
function M.ask(opts)
  return resolve().ask(opts)
end

return M
