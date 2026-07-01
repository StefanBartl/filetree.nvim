---@module 'filetree.features.picker'
---@brief Two-digit quick-pick mode for any supported filetree.
---@description
--- Activates an overlay that labels visible tree nodes with two-digit indices.
--- Typing a number immediately opens/toggles the corresponding node.
--- A mode prefix key (e, s, v, t, p) before the number selects how the file opens.

local core = require("filetree.features.nav.picker.core")

local M = {}

---@type integer?
local _augroup = nil

---@param config  FiletreePickerConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  core.init(config, adapter)

  local kmaps = config.keymaps or {}
  local reveal_key = kmaps.trigger_reveal or "<leader>fp"
  local cwd_key    = kmaps.trigger_cwd    or "<leader>fc"

  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
  end
  _augroup = vim.api.nvim_create_augroup("filetree_picker", { clear = true })

  -- Global normal-mode keymaps (outside tree buffer)
  vim.keymap.set("n", reveal_key, function() core.start_reveal() end,
    { desc = "Filetree: picker (reveal)", silent = true })
  vim.keymap.set("n", cwd_key, function() core.start_cwd() end,
    { desc = "Filetree: picker (cwd)", silent = true })

  -- Exit picker on BufLeave from the tree
  vim.api.nvim_create_autocmd("BufLeave", {
    group    = _augroup,
    callback = function()
      if core.state.active then core.exit() end
    end,
  })
end

function M.teardown()
  core.exit()
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

-- Re-export for direct use
M.start_reveal = core.start_reveal
M.start_cwd    = core.start_cwd
M.exit         = core.exit
M.is_active    = function() return core.state.active end

return M
