---@module 'filetree.features.tree_open_keymaps'
---@brief Global normal-mode keys to toggle the tree at a chosen position.
---@description
--- Registers global (not tree-buffer-local) keymaps that toggle the file tree at
--- a given position and reveal the current buffer's file:
---
---   left     sidebar on the left
---   right    sidebar on the right
---   float    floating window
---   current  in the current window (netrw-style)
---
--- Adapter-agnostic: neo-tree honours the position via its own command; other
--- adapters fall back to `adapter.open_reveal()` (position is ignored) or
--- `adapter.open_cwd()` when there is no file to reveal.
---
--- OFF by default — it binds global keys, which is opinionated; opt in explicitly.
---
--- Config:
---   enabled           boolean
---   keymaps           { left?, right?, float?, current? }  Global lhs per position.
---   reveal_force_cwd  boolean  Set the tree root to cwd when toggling (default false).

local map = require("filetree.util.map")
local M = {}

---@class FiletreeTreeOpenKeymapsConfig
---@field enabled          boolean
---@field keymaps          { left?:string|false, right?:string|false, float?:string|false, current?:string|false }
---@field reveal_force_cwd boolean

---@type FiletreeTreeOpenKeymapsConfig
local _cfg = {
  enabled = false,
  keymaps = {
    left    = "<leader>el",
    right   = "<leader>er",
    float   = "<leader>ef",
    current = "<leader>ec",
  },
  reveal_force_cwd = false,
}

---@type FiletreeAdapter?
local _adapter = nil

---Toggle/open the tree at `position`, revealing the current file when possible.
---@param position "left"|"right"|"float"|"current"
local function open_at(position)
  local adapter = _adapter
  if not adapter then return end

  local file = vim.api.nvim_buf_get_name(0)
  local has_file = file ~= "" and vim.fn.filereadable(file) == 1
  local dir = _cfg.reveal_force_cwd and vim.fn.getcwd() or nil

  -- Preferred: the adapter exposes a position-aware toggle (neo-tree does; other
  -- backends can add `toggle_at` later). Position/float/current live in the
  -- adapter, keeping this feature plugin-agnostic.
  if type(adapter.toggle_at) == "function" then
    if adapter.toggle_at(position, { reveal = has_file, file = file, dir = dir }) then
      return
    end
  end

  -- Fallback for adapters without position support: just reveal / open cwd.
  if has_file and type(adapter.open_reveal) == "function" then
    adapter.open_reveal(file, 0)
  elseif type(adapter.open_cwd) == "function" then
    adapter.open_cwd()
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeTreeOpenKeymapsConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  _cfg     = vim.tbl_deep_extend("force", _cfg, config or {})
  _adapter = adapter
  if not _cfg.enabled then return end

  local km = _cfg.keymaps or {}
  local defs = {
    { key = km.left,    pos = "left",    desc = "Filetree: toggle tree (left)"    },
    { key = km.right,   pos = "right",   desc = "Filetree: toggle tree (right)"   },
    { key = km.float,   pos = "float",   desc = "Filetree: toggle tree (float)"   },
    { key = km.current, pos = "current", desc = "Filetree: open tree (current window)" },
  }

  for _, d in ipairs(defs) do
    if type(d.key) == "string" and d.key ~= "" then
      map("n", d.key, function() open_at(d.pos) end, {
        silent = true, desc = d.desc,
      })
    end
  end
end

function M.teardown()
  local km = _cfg.keymaps or {}
  for _, key in pairs(km) do
    if type(key) == "string" and key ~= "" then
      pcall(vim.keymap.del, "n", key)
    end
  end
  _adapter = nil
end

return M
