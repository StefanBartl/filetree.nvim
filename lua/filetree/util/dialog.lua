---@module 'filetree.util.dialog'
---@brief The shared dialog (`lib.nvim.ui.dialog`), or ui.kit's `confirm` when lib.nvim predates it.
---@description
--- Every yes/no and choice dialog of this plugin goes through here. `lib.nvim.ui.dialog` is the one wrapper the
--- plugins share (kit answers exactly once, a float that cannot open falls back to `vim.ui.select`). A lib.nvim
--- without it must not break the features that merely load a dialog helper, so the module is resolved on first
--- use and then stands in with ui.kit directly (ui.nvim is a hard dependency).

local M = {}

local reported = false

---@return table dialog  # has `confirm` and `ask`
local function resolve()
  local ok, dialog = pcall(require, "lib.nvim.ui.dialog")
  if ok and type(dialog) == "table" and dialog.confirm and dialog.ask then return dialog end
  -- A module that is there but raises is not a module that is missing: say so once, then stand in.
  if
    not ok
    and not tostring(dialog):find("module 'lib.nvim.ui.dialog' not found", 1, true)
    and not reported
  then
    reported = true
    vim.schedule(function()
      vim.notify(
        "[filetree] lib.nvim.ui.dialog failed to load, dialogs use ui.kit directly: "
          .. tostring(dialog),
        vim.log.levels.WARN
      )
    end)
  end
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
