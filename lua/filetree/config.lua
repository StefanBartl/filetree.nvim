---@module 'filetree.config'
---@brief Configuration management — defaults, merging, validation.

local M = {}

---@type FiletreeConfig
local _defaults = {
  adapter = "auto",
  features = {
    picker = {
      enabled     = true,
      index_width = 2,
      timeout_ms  = 3000,
      keymaps = {
        trigger_reveal = "<leader>fp",
        trigger_cwd    = "<leader>fc",
      },
    },
    layout_guard = {
      enabled  = true,
      delay_ms = 50,
    },
    cwd_sync = {
      enabled       = false,
      debounce_ms   = 150,
      parent_levels = 0,
      keep_focus    = true,
    },
    current_hl = {
      enabled     = false,
      file_hl     = { fg = "#7aa2f7", bold = true },
      parent_hl   = { fg = "#565f89" },
      debounce_ms = 100,
    },
    safety = {
      enabled     = false,
      backup_dir  = nil,
      max_backups = 5,
      dry_run     = false,
    },
  },
}

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
---A remap value of `false` disables the key; a string replaces it.
---@param cfg FiletreeConfig
local function apply_keymap_remap(cfg)
  local remap = cfg.keymaps
  if type(remap) ~= "table" then return end

  local function patch(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do
      if type(k) == "string" and k:match("^keymap") and type(v) == "string" then
        if remap[v] ~= nil then
          t[k] = remap[v]   -- false → disabled, string → renamed
        end
      elseif type(v) == "table" then
        patch(v)
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
  local picker = cfg.features.picker
  if picker and picker.enabled then
    if type(picker.index_width) ~= "number" or picker.index_width < 1 then
      return false, "features.picker.index_width must be a positive number"
    end
    if type(picker.timeout_ms) ~= "number" or picker.timeout_ms < 0 then
      return false, "features.picker.timeout_ms must be >= 0"
    end
  end
  return true, nil
end

return M
