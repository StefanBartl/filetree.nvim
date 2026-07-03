---@module 'filetree.features.auto_resize'
---@brief Responsive tree sidebar width based on editor column count.
---@description
--- Listens to VimResized and adjusts the tree window width to one of the
--- configured breakpoint widths. Also exposes M.set_width(n) for manual
--- control and :Filetree resize [width].
---
--- Breakpoints: list of { cols, width } pairs sorted ascending by cols.
--- The last matching breakpoint is used (i.e. the largest cols ≤ vim.o.columns).
---
--- Default breakpoints (columns → tree width):
---   <100  → 25
---   <140  → 30
---   ≥140  → 35
---
--- Config:
---   enabled      boolean
---   breakpoints  { cols: integer, width: integer }[]
---   min_width    integer  Absolute minimum (default 20).
---   max_width    integer  Absolute maximum (default 60).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree resize [width]

local notify = require("filetree.util.notify").create("[filetree.auto_resize]")

local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeAutoResizeConfig
local _cfg = {
  enabled     = false,
  breakpoints = {
    { cols = 0,   width = 25 },
    { cols = 100, width = 30 },
    { cols = 140, width = 35 },
  },
  min_width = 20,
  max_width = 60,
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function target_width()
  local cols  = vim.o.columns
  local width = _cfg.breakpoints[1] and _cfg.breakpoints[1].width or 30
  for _, bp in ipairs(_cfg.breakpoints) do
    if cols >= bp.cols then width = bp.width end
  end
  return clamp(width, _cfg.min_width, _cfg.max_width)
end

local function apply_width(w)
  if not _adapter then return end
  local winid = _adapter.get_winid and _adapter.get_winid() or -1
  if winid > 0 and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_set_width(winid, w)
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Apply the auto-calculated width now.
function M.apply()
  apply_width(target_width())
end

---Set a specific width, clamped to min/max.
---@param w? integer  Default: auto from breakpoints.
function M.set_width(w)
  if w then
    apply_width(clamp(w, _cfg.min_width, _cfg.max_width))
  else
    M.apply()
  end
end

---@return integer
function M.current_target()
  return target_width()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeAutoResizeConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  -- Sort breakpoints ascending by cols so the last match wins
  table.sort(_cfg.breakpoints, function(a, b) return a.cols < b.cols end)

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_auto_resize", true)

  au.acmd("VimResized", {
    group    = _augroup,
    callback = function() M.apply() end,
  })

  -- Also apply when the tree window opens / gets focus
  au.acmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function()
      vim.schedule(M.apply)
    end,
  })

  -- Apply immediately
  vim.schedule(M.apply)
end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
