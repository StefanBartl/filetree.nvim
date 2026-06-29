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

---Apply user config on top of defaults.
---@param user FiletreeConfig?
function M.setup(user)
  -- Deep-copy defaults
  _active = vim.deepcopy(_defaults)
  if user then
    deep_merge(_active, user)
  end
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
