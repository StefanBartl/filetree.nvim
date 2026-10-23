---@module 'filetree.features.nav.collapse_all'
---@brief Collapse every open folder back to the root: one key, one command.
---@description
--- A thin front for the optional adapter method `collapse_all` (neo-tree:
--- `close_all_nodes`, nvim-tree: `api.tree.collapse_all`). The flat backends
--- (netrw, oil, mini.files) have nothing to collapse and say so. The cursor
--- lands on the top-level entry it was under, or the root.
---
--- `tree_toggle.collapse_on_toggle` uses the same adapter method, keeping the
--- current file's folder chain open.
---
--- Config:
---   enabled  boolean
---   keymap   string?  Key in the tree buffer (default "W", nvim-tree's own key for it).

local notify = require("filetree.util.notify").create("[filetree.collapse_all]")
local bind = require("filetree.util.bind")

local M = {}

---Option schema (see `filetree.config.schema`): exactly what
---`features.collapse_all` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {
  keymap = "keymap",
}

---@type FiletreeAdapter|nil
local _adapter = nil

---Collapse every folder of the tree. A backend that cannot is reported, not
---an error.
---@return boolean ok
---@return string? reason
function M.collapse()
  local adapter = _adapter
  if not adapter then return false, "collapse_all is not set up" end
  if type(adapter.collapse_all) ~= "function" then
    return false, ("not applicable: the %s adapter has no collapse_all"):format(adapter.name)
  end
  local ok, reason = adapter.collapse_all(nil)
  if not ok then return false, reason or "collapse failed" end
  return true, nil
end

---@internal
local function run()
  local ok, reason = M.collapse()
  if ok then return end
  if reason and reason:find("^not applicable") then
    notify.info(reason)
  else
    notify.warn(reason or "collapse failed")
  end
end

M.run = run

---@param config FiletreeCollapseAllConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _adapter = adapter
  bind.bind("collapse_all", config, {
    {
      name = "collapse",
      field = "keymap",
      default = "W",
      rhs = run,
      desc = "collapse all folders",
    },
  })
end

function M.teardown()
  _adapter = nil
end

return M
