---@module 'filetree.features.window_style'
---@brief Cosmetic tweaks for tree windows: blank statusline + isolated highlights.
---@description
--- Both effects are OFF by default, so enabling the feature changes nothing until
--- you opt into one of them:
---
---   statusline           Blank the statusline inside tree windows (a single
---                        space), so the sidebar has no cluttered status text.
---   highlights_isolate   Link the tree's Normal / NormalNC / EndOfBuffer groups
---                        to the editor's own, so the sidebar shares the editor
---                        background instead of a plugin-specific one.
---
--- Adapted from the neo-tree config's window/disable_statusline + window/highlight
--- helpers, generalized to neo-tree and nvim-tree.
---
--- Config:
---   enabled              boolean
---   statusline           boolean  Blank statusline in tree windows (default false).
---   highlights_isolate   boolean  Link tree HL groups to editor groups (default false).

local M = {}

---@class FiletreeWindowStyleConfig
---@field enabled            boolean
---@field statusline         boolean
---@field highlights_isolate boolean

---@type FiletreeWindowStyleConfig
local _cfg = {
  enabled            = false,
  statusline         = false,
  highlights_isolate = false,
}

---@type integer?
local _augroup = nil

local _TREE_FT = { ["neo-tree"] = true, ["NvimTree"] = true }

---Blank the statusline in every tree window of the current tabpage.
local function apply_statusline()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_valid(buf) and _TREE_FT[vim.bo[buf].filetype] then
        vim.wo[win].statusline = " "
      end
    end
  end
end

---Link tree highlight groups to the editor's own so the sidebar blends in.
local function isolate_highlights()
  local links = {
    NeoTreeNormal      = "Normal",
    NeoTreeNormalNC    = "NormalNC",
    NeoTreeEndOfBuffer = "EndOfBuffer",
    NvimTreeNormal      = "Normal",
    NvimTreeNormalNC    = "NormalNC",
    NvimTreeEndOfBuffer = "EndOfBuffer",
  }
  for group, target in pairs(links) do
    pcall(vim.api.nvim_set_hl, 0, group, { link = target })
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeWindowStyleConfig
---@param _adapter FiletreeAdapter
function M.setup(config, _adapter)
  _cfg = vim.tbl_deep_extend("force", _cfg, config or {})
  if not _cfg.enabled then return end
  -- Nothing to do unless at least one effect is opted into.
  if not (_cfg.statusline or _cfg.highlights_isolate) then return end

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_window_style", { clear = true })

  if _cfg.statusline then
    vim.api.nvim_create_autocmd("FileType", {
      group    = _augroup,
      pattern  = { "neo-tree", "NvimTree" },
      callback = function() vim.schedule(apply_statusline) end,
    })
  end

  if _cfg.highlights_isolate then
    vim.api.nvim_create_autocmd("ColorScheme", {
      group    = _augroup,
      callback = function() vim.schedule(isolate_highlights) end,
    })
    vim.schedule(isolate_highlights)
  end
end

function M.teardown()
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
