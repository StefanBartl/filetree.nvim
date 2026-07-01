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
--- Adapter-agnostic: the tree filetypes and highlight-group names come from the
--- active adapter's optional `filetypes` / `hl_groups` capabilities, so this
--- works for any backend that declares them (neo-tree, nvim-tree ship them).
--- When an adapter omits them, a superset covering all known trees is used as a
--- harmless fallback.
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
---@type FiletreeAdapter?
local _adapter = nil

-- Fallbacks used when the active adapter does not declare the capability.
local DEFAULT_FILETYPES = { "neo-tree", "NvimTree", "netrw", "oil", "minifiles" }
local DEFAULT_HL_GROUPS = {
  NeoTreeNormal       = "Normal",
  NeoTreeNormalNC     = "NormalNC",
  NeoTreeEndOfBuffer  = "EndOfBuffer",
  NvimTreeNormal      = "Normal",
  NvimTreeNormalNC    = "NormalNC",
  NvimTreeEndOfBuffer = "EndOfBuffer",
}

---Tree filetypes to target — the adapter's if declared, else the superset.
---@return string[]
local function tree_filetypes()
  local ft = _adapter and _adapter.filetypes
  if type(ft) == "table" and #ft > 0 then return ft end
  return DEFAULT_FILETYPES
end

---Blank the statusline in every tree window of the current tabpage.
local function apply_statusline()
  local want = {}
  for _, f in ipairs(tree_filetypes()) do want[f] = true end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_valid(buf) and want[vim.bo[buf].filetype] then
        vim.wo[win].statusline = " "
      end
    end
  end
end

---Link tree highlight groups to the editor's own so the sidebar blends in.
local function isolate_highlights()
  local groups = _adapter and _adapter.hl_groups
  if type(groups) ~= "table" or next(groups) == nil then
    groups = DEFAULT_HL_GROUPS
  end
  for group, target in pairs(groups) do
    pcall(vim.api.nvim_set_hl, 0, group, { link = target })
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeWindowStyleConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  _cfg     = vim.tbl_deep_extend("force", _cfg, config or {})
  _adapter = adapter
  if not _cfg.enabled then return end
  -- Nothing to do unless at least one effect is opted into.
  if not (_cfg.statusline or _cfg.highlights_isolate) then return end

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_window_style", { clear = true })

  if _cfg.statusline then
    vim.api.nvim_create_autocmd("FileType", {
      group    = _augroup,
      pattern  = tree_filetypes(),
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
