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
local tree_attach = require("filetree.util.tree_attach")

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

---@internal
---The keys `config.keymap` asks for: the default `W` when unset, none for `false`.
---@param config FiletreeCollapseAllConfig
---@return string[]
local function wanted_keys(config)
  local v = config.keymap
  if v == nil then return { "W" } end
  if v == false then return {} end
  if type(v) == "string" then return { v } end
  if type(v) == "table" then return vim.deepcopy(v) end
  return {}
end

---@internal
---Whether `buf` already has a buffer-local normal-mode map on `lhs` that
---filetree did not set: the tree plugin's or the user's own (a neo-tree
---`window.mappings` entry is exactly that).
---@param buf integer
---@param lhs string
---@return string|nil desc  What the foreign map does, nil when the key is free.
function M.foreign_map(buf, lhs)
  local m = vim.api.nvim_buf_call(buf, function()
    return vim.fn.maparg(lhs, "n", false, true)
  end)
  if type(m) ~= "table" or m.buffer ~= 1 then return nil end
  local desc = m.desc or ""
  if desc:find("^filetree") then return nil end
  return desc ~= "" and desc or (type(m.rhs) == "string" and m.rhs or "a mapping")
end

---@type table<string, true>  keys already reported as taken, once per session
local _reported = {}

---@param config FiletreeCollapseAllConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _adapter = adapter
  local wanted = wanted_keys(config)
  -- Bound per tree buffer, and only on keys that are still free there: the
  -- default `W` is free in neo-tree and nvim-tree's own `W` is this very
  -- action, but a config that put something of its own on `W` (a window
  -- picker, say) must not lose it silently to a plugin update.
  tree_attach.on_attach(function(buf)
    local free = {}
    for _, lhs in ipairs(wanted) do
      local taken = M.foreign_map(buf, lhs)
      if taken then
        -- nvim-tree's own `W` IS collapse-all: nothing lost, nothing to say.
        local same_action = taken:lower():find("collapse all", 1, true) ~= nil
        if not same_action and not _reported[lhs] then
          _reported[lhs] = true
          notify.info(
            ("%s is already mapped in the tree (%s); collapse_all leaves it alone -- "):format(
              lhs,
              taken
            ) .. "set features.collapse_all.keymap, or use :Filetree collapse"
          )
        end
      else
        free[#free + 1] = lhs
      end
    end
    bind.bind_buffer("collapse_all", { keymap = #free > 0 and free or false }, {
      {
        name = "collapse",
        field = "keymap",
        rhs = run,
        desc = "collapse all folders",
      },
    }, buf)
  end, "collapse_all")
end

function M.teardown()
  _adapter = nil
end

return M
