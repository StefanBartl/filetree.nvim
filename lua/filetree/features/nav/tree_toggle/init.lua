---@module 'filetree.features.nav.tree_toggle'
---@brief Toggle the tree at a chosen position from anywhere: four global keys.
---@description
--- `<M-l>` opens (or closes) the tree on the left, `<M-r>` on the right,
--- `<M-f>` as a float, `<M-c>` in the current window -- and reveals the
--- current file on the way in, re-rooting to the cwd if it lives outside
--- the tree. This is the `:Neotree toggle position=… reveal reveal_force_cwd`
--- most configs end up writing four times, through the adapter instead, so
--- it works on every backend that can place its tree (`adapter.toggle_at`).
---
--- Opt-in: four global Alt keys are a claim on the keyboard this plugin
--- does not make unasked. Enable it and remap what collides.
---
--- Config:
---   enabled           boolean   (default false)
---   reveal            boolean   Reveal the current file when opening (default true).
---   reveal_force_cwd  boolean   Re-root to the cwd when the file is outside the tree (default true).
---   keymap_current    string?   Global key (default "<M-c>").
---   keymap_float      string?   Global key (default "<M-f>").
---   keymap_left       string?   Global key (default "<M-l>").
---   keymap_right      string?   Global key (default "<M-r>").

local notify = require("filetree.util.notify").create("[filetree.tree_toggle]")
local bind = require("filetree.util.bind")

local M = {}

---@type FiletreeTreeToggleConfig
local DEFAULTS = {
  enabled = false,
  reveal = true,
  reveal_force_cwd = true,
  keymap_current = "<M-c>",
  keymap_float = "<M-f>",
  keymap_left = "<M-l>",
  keymap_right = "<M-r>",
}

---Option schema (see `filetree.config.schema`): exactly what
---`features.tree_toggle` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {
  reveal = "boolean",
  reveal_force_cwd = "boolean",
  keymap_current = "keymap",
  keymap_float = "keymap",
  keymap_left = "keymap",
  keymap_right = "keymap",
}

---@type FiletreeTreeToggleConfig
local _cfg = vim.deepcopy(DEFAULTS)
---@type FiletreeAdapter|nil
local _adapter = nil

---@type FiletreeTreePosition[]
M.POSITIONS = { "left", "right", "float", "current" }

---Toggle the tree at `position`.
---@param position FiletreeTreePosition
---@return boolean ok
---@return string|nil err
function M.toggle(position)
  if not vim.tbl_contains(M.POSITIONS, position) then
    return false, ("unknown position %q (left, right, float, current)"):format(tostring(position))
  end
  local adapter = _adapter
  if not adapter then return false, "tree_toggle is not set up" end
  if type(adapter.toggle_at) ~= "function" then
    return false, ("the %s adapter cannot place its tree"):format(adapter.name)
  end
  local file = vim.api.nvim_buf_get_name(0)
  local reveal = _cfg.reveal == true and file ~= ""
  local ok = adapter.toggle_at(position, {
    reveal = reveal,
    file = reveal and file or nil,
    reveal_force_cwd = reveal and _cfg.reveal_force_cwd == true,
  })
  if not ok then return false, "toggle failed" end
  return true, nil
end

---@internal
---@param position FiletreeTreePosition
---@return fun()
local function toggler(position)
  return function()
    local ok, err = M.toggle(position)
    if not ok then notify.warn(err or "toggle failed") end
  end
end

---@param config FiletreeTreeToggleConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  _cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), config or {})
  if not _cfg.enabled then return end
  _adapter = adapter
  if type(adapter.toggle_at) ~= "function" then
    notify.warn(
      ("adapter %q cannot place its tree; tree_toggle binds nothing"):format(adapter.name)
    )
    return
  end

  bind.bind("tree_toggle/global", _cfg, {
    {
      name = "current",
      field = "keymap_current",
      rhs = toggler("current"),
      desc = "toggle tree in this window",
    },
    {
      name = "float",
      field = "keymap_float",
      rhs = toggler("float"),
      desc = "toggle tree as a float",
    },
    {
      name = "left",
      field = "keymap_left",
      rhs = toggler("left"),
      desc = "toggle tree on the left",
    },
    {
      name = "right",
      field = "keymap_right",
      rhs = toggler("right"),
      desc = "toggle tree on the right",
    },
  }, "global")
end

function M.teardown()
  for _, field in ipairs({ "keymap_current", "keymap_float", "keymap_left", "keymap_right" }) do
    local lhs = _cfg[field]
    if type(lhs) == "string" and lhs ~= "" then pcall(vim.keymap.del, "n", lhs) end
  end
  _adapter = nil
end

return M
