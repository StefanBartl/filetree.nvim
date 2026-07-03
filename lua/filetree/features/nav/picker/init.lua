---@module 'filetree.features.picker'
---@brief Two-digit quick-pick mode for any supported filetree.
---@description
--- Activates an overlay that labels visible tree nodes with two-digit indices.
--- Typing a number immediately opens/toggles the corresponding node.
--- A mode prefix key (e, s, v, t, p) before the number selects how the file opens.

local core = require("filetree.features.nav.picker.core")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type integer?
local _augroup = nil

---@param config  FiletreePickerConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  core.init(config, adapter)

  local kmaps = config.keymaps or {}
  local reveal_key = kmaps.trigger_reveal or "<leader>ftp"
  local cwd_key    = kmaps.trigger_cwd    or "<leader>ftc"

  if _augroup then
    au.del_group(_augroup)
  end
  _augroup = au.group("filetree_picker", true)

  -- Global normal-mode keymaps (outside tree buffer)
  map("n", reveal_key, function() core.start_reveal() end,
    { desc = "Filetree: picker (reveal)", silent = true })
  map("n", cwd_key, function() core.start_cwd() end,
    { desc = "Filetree: picker (cwd)", silent = true })

  -- Exit picker on BufLeave from the tree
  au.acmd("BufLeave", {
    group    = _augroup,
    callback = function()
      if core.state.active then core.exit() end
    end,
  })
end

function M.teardown()
  core.exit()
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

-- Re-export for direct use
M.start_reveal = core.start_reveal
M.start_cwd    = core.start_cwd
M.exit         = core.exit
M.is_active    = function() return core.state.active end

return M
