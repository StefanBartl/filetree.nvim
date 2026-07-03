---@module 'filetree.features.window_size_cycler'
---@brief Manually cycle the tree sidebar width through preset sizes.
---@description
--- Binds a key (default `w`) in the tree buffer.  Each press advances
--- through the configured size presets in order:
---   normal → large → small → normal → …
---
--- The cycle starts at whichever preset is closest to the current width.
--- Integrates cleanly with auto_resize: the cycler just sets the window
--- width directly; auto_resize may overwrite it on VimResized.
---
--- Config:
---   enabled  boolean
---   keymap   string?     Key in tree buffer (default "w").
---   sizes    integer[]   Width presets to cycle through (default { 30, 50, 15 }).

local notify = require("filetree.util.notify").create("[filetree.window_size_cycler]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeWindowSizeCyclerConfig
local _cfg = {
  enabled = false,
  keymap  = "w",
  sizes   = { 30, 50, 15 },
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  0-based index into _cfg.sizes
local _idx = 0

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function get_winid()
  return _adapter and _adapter.get_winid and _adapter.get_winid() or -1
end

local function current_width()
  local winid = get_winid()
  if winid > 0 and vim.api.nvim_win_is_valid(winid) then
    return vim.api.nvim_win_get_width(winid)
  end
  return _cfg.sizes[1] or 30
end

local function apply_width(w)
  local winid = get_winid()
  if winid > 0 and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_set_width(winid, w)
  end
end

local function nearest_idx()
  local w   = current_width()
  local best, best_d = 0, math.huge
  for i, sz in ipairs(_cfg.sizes) do
    local d = math.abs(sz - w)
    if d < best_d then best_d = d; best = i end
  end
  return best
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.cycle()
  local sizes = _cfg.sizes
  if not sizes or #sizes == 0 then
    notify.warn("No sizes configured")
    return
  end
  -- Advance from current position
  _idx = (_idx % #sizes) + 1
  apply_width(sizes[_idx])
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeWindowSizeCyclerConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  -- Start at the preset closest to the current window width
  _idx = nearest_idx()

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_window_size_cycler", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if _cfg.keymap then
          map("n", _cfg.keymap, M.cycle, {
            buffer = buf, silent = true,
            desc   = "Filetree: cycle tree width",
          })
        end
      end)
    end,
  })
end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
