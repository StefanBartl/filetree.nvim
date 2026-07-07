---@module 'filetree.config'
---@brief Configuration management — defaults, merging, validation.
---@description
--- Plugin-side defaults live in `filetree.config.DEFAULTS`; this module deep-merges
--- the user's `setup({})` config on top and exposes the active config.

local M = {}

---@type FiletreeConfig
local _defaults = require("filetree.config.DEFAULTS")

---@type FiletreeConfig
local _active = {}

---Deep-merge src into dst (modifies dst in place).
---@param dst table
---@param src table
---@return table
local function deep_merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      deep_merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

---Scan all feature keymap fields and apply the global `keymaps` remap table.
---Covers two patterns:
---  1. Fields whose key starts with "keymap"  (e.g. keymap, keymap_open, keymap_scroll_up)
---  2. All string values inside a sub-table whose key is "keymaps"
---     (e.g. copy_move.keymaps.copy, copy_file_list.keymaps.files_abs)
---A remap value of `false` disables the key; a string replaces it.
---@param cfg FiletreeConfig
local function apply_keymap_remap(cfg)
  local remap = cfg.keymaps
  if type(remap) ~= "table" then return end

  local function patch(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do
      if type(v) == "string" then
        if type(k) == "string" and k:match("^keymap") and remap[v] ~= nil then
          t[k] = remap[v]
        end
      elseif type(v) == "table" then
        if k == "keymaps" then
          -- patch all string values inside a keymaps sub-table
          for ik, iv in pairs(v) do
            if type(iv) == "string" and remap[iv] ~= nil then
              v[ik] = remap[iv]
            end
          end
        else
          patch(v)
        end
      end
    end
  end

  if type(cfg.features) == "table" then
    for _, fcfg in pairs(cfg.features) do
      patch(fcfg)
    end
  end
end

---Propagate top-level `autocmds` disables into per-feature configs.
---`autocmds = { auto_reveal = false }` sets `fcfg.autocmds_enabled = false`.
---@param cfg FiletreeConfig
local function apply_autocmd_overrides(cfg)
  local overrides = cfg.autocmds
  if type(overrides) ~= "table" then return end
  if type(cfg.features) ~= "table" then return end
  for name, val in pairs(overrides) do
    local fcfg = cfg.features[name]
    if type(fcfg) == "table" and val == false then
      fcfg.autocmds_enabled = false
    end
  end
end

---Map of user-facing action names (what the confirmation is actually about)
---to the feature + config field that action's prompt lives on.
---@type table<string, { feature: string, field: string }>
local CONFIRMATION_ACTIONS = {
  paste        = { feature = "copy_move",   field = "confirm" },
  delete       = { feature = "trash",       field = "confirm" },
  rename_batch = { feature = "rename_batch", field = "confirm" },
}

---Translate top-level `confirmations` into the per-feature `confirm` fields
---it controls.
---  true / false → applies to every confirmable action
---  table        → applies per action name, e.g. { paste = false, delete = true }
--- Either way, a feature whose `confirm` the user already set explicitly
--- (via `features.<name>.confirm`) keeps that value -- the top-level switch
--- only fills in fields the user left unset.
---@param cfg FiletreeConfig
local function apply_confirmations(cfg)
  local val = cfg.confirmations
  if val == nil then return end
  cfg.features = cfg.features or {}

  local function set_if_unset(action, value)
    local spec = CONFIRMATION_ACTIONS[action]
    if not spec then return end
    local fcfg = cfg.features[spec.feature]
    if type(fcfg) ~= "table" then
      fcfg = {}
      cfg.features[spec.feature] = fcfg
    end
    if fcfg[spec.field] == nil then
      fcfg[spec.field] = value
    end
  end

  if type(val) == "table" then
    for action, value in pairs(val) do
      set_if_unset(action, value)
    end
  else
    for action in pairs(CONFIRMATION_ACTIONS) do
      set_if_unset(action, val)
    end
  end
end

---Translate top-level `ignore_list` into `features.ignore_list`.
---  true / nil → enabled, no override (use built-in / lib.nvim names)
---  false      → disabled
---  string[]   → enabled with those exact names
---@param cfg FiletreeConfig
local function apply_ignore_list(cfg)
  local val = cfg.ignore_list
  cfg.features = cfg.features or {}
  local fi = cfg.features.ignore_list or {}
  if val == false then
    fi.enabled = false
  elseif type(val) == "table" then
    fi.enabled = true
    fi.names   = val
  else
    -- true or nil → default on, built-in names
    fi.enabled = true
    fi.names   = fi.names  -- preserve user override if they set features.ignore_list.names directly
  end
  cfg.features.ignore_list = fi
end

---Apply user config on top of defaults.
---@param user FiletreeConfig?
function M.setup(user)
  -- Deep-copy defaults
  _active = vim.deepcopy(_defaults)
  if user then
    deep_merge(_active, user)
  end
  apply_keymap_remap(_active)
  apply_autocmd_overrides(_active)
  apply_confirmations(_active)
  apply_ignore_list(_active)
end

---Return the active configuration.
---@return FiletreeConfig
function M.get()
  return _active
end

---Validate the active config and return error messages.
---@return boolean ok
---@return string? err
function M.validate()
  local cfg = _active
  if type(cfg.adapter) ~= "string" then
    return false, "config.adapter must be a string"
  end
  if type(cfg.features) ~= "table" then
    return false, "config.features must be a table"
  end
  return true, nil
end

return M
