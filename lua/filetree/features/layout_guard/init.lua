---@module 'filetree.features.layout_guard'
---@brief Ensure an editor window always exists when the tree is the only window.
---@description
--- When the user closes all editor windows but leaves the tree open, this
--- feature automatically opens a new empty window so the user is never
--- trapped inside the tree with no place to edit files.

local notify = require("filetree.util.notify").create("[filetree.layout_guard]")

local M = {}

---@type integer?
local _augroup = nil

---Create an empty editor window positioned next to the tree.
---@param adapter FiletreeAdapter
local function ensure_editor(adapter)
  -- Count normal (non-tree) windows
  local tree_winid = adapter.get_winid()
  local normal_wins = 0
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if winid ~= tree_winid then
      local cfg = vim.api.nvim_win_get_config(winid)
      if cfg.relative == "" then -- not a floating window
        normal_wins = normal_wins + 1
      end
    end
  end

  if normal_wins > 0 then return end

  -- Open a new split next to the tree
  local ok = pcall(vim.cmd, "vsplit | enew")
  if not ok then
    pcall(vim.cmd, "new")
  end
end

---@param config FiletreeLayoutGuardConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local delay = config.delay_ms or 50

  if _augroup then
    vim.api.nvim_del_augroup_by_id(_augroup)
  end
  _augroup = vim.api.nvim_create_augroup("filetree_layout_guard", { clear = true })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout", "WinClosed" }, {
    group    = _augroup,
    callback = function()
      vim.defer_fn(function()
        if not adapter.is_open() then return end
        ensure_editor(adapter)
      end, delay)
    end,
  })
end

function M.teardown()
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
