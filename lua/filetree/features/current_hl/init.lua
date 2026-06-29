---@module 'filetree.features.current_hl'
---@brief Highlight the current file and its parent directory in the tree.
---@description
--- On BufEnter/WinEnter events (debounced), the current file's line and its
--- parent directory's line are highlighted in the tree buffer using extmarks.
--- Highlight groups are resolved from the config spec which accepts hex colors,
--- linked groups ("link:GroupName"), or named colors ("red", "darkred", etc.).

local M = {}

---@type integer?
local _augroup = nil

---@type FiletreeCurrentHlConfig
local _cfg = {}

---@type FiletreeAdapter?
local _adapter = nil

---@type any?   pending uv timer
local _timer = nil

---@type string?  last highlighted file path
local _last_file = nil
---@type string?  last highlighted parent path
local _last_parent = nil

-- ── Highlight group resolution ────────────────────────────────────────────────

local function ensure_hl_group(name, spec)
  if type(spec) == "table" then
    vim.api.nvim_set_hl(0, name, spec)
    return name
  end
  if type(spec) ~= "string" then return nil end
  if spec:match("^#%x%x%x%x%x%x$") then
    vim.api.nvim_set_hl(0, name, { fg = spec, bold = true })
    return name
  end
  local linked = spec:match("^link:(.+)$")
  if linked then
    vim.api.nvim_set_hl(0, name, { link = linked })
    return name
  end
  -- named color fallback
  local ok = pcall(vim.api.nvim_set_hl, 0, name, { fg = spec, bold = true })
  if ok then return name end
  return nil
end

local FILE_HL   = "FiletreeCurrentFile"
local PARENT_HL = "FiletreeCurrentParent"

local function setup_hl_groups()
  ensure_hl_group(FILE_HL,   _cfg.file_hl   or { fg = "#7aa2f7", bold = true })
  ensure_hl_group(PARENT_HL, _cfg.parent_hl or { fg = "#565f89" })
end

-- ── Highlight application ─────────────────────────────────────────────────────

local function clear_old()
  if _last_file and _adapter then
    _adapter.unhighlight_node(_last_file)
  end
  if _last_parent and _adapter then
    _adapter.unhighlight_node(_last_parent)
  end
  _last_file   = nil
  _last_parent = nil
end

local function apply()
  if not _adapter or not _adapter.is_open() then return end

  local path = vim.fn.expand("%:p")
  if path == "" or vim.fn.filereadable(path) == 0 then return end

  local parent = vim.fn.fnamemodify(path, ":h")

  clear_old()
  setup_hl_groups()

  _adapter.highlight_node(path,   FILE_HL)
  _adapter.highlight_node(parent, PARENT_HL)

  _last_file   = path
  _last_parent = parent
end

local function debounced_apply()
  if _timer then
    pcall(function()
      _timer:stop()
      _timer:close()
    end)
    _timer = nil
  end
  local uv = vim.uv or vim.loop
  _timer = uv.new_timer()
  _timer:start(_cfg.debounce_ms or 100, 0, vim.schedule_wrap(function()
    _timer = nil
    apply()
  end))
end

-- ── Public API ────────────────────────────────────────────────────────────────

---@param config FiletreeCurrentHlConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = config
  _adapter = adapter

  setup_hl_groups()

  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
  end
  _augroup = vim.api.nvim_create_augroup("filetree_current_hl", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "BufWritePost" }, {
    group    = _augroup,
    callback = debounced_apply,
  })

  -- Re-apply after colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = _augroup,
    callback = function()
      setup_hl_groups()
      apply()
    end,
  })
end

function M.teardown()
  clear_old()
  if _timer then
    pcall(function()
      _timer:stop()
      _timer:close()
    end)
    _timer = nil
  end
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
