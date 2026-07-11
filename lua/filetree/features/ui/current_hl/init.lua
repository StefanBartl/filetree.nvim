---@module 'filetree.features.current_hl'
---@brief Highlight the current file and its parent directory in the tree.
---@description
--- On BufEnter/WinEnter events (debounced), the current file's line and its
--- parent directory's line are highlighted in the tree buffer using extmarks.
--- Highlight groups are resolved from the config spec which accepts hex colors,
--- linked groups ("link:GroupName"), or named colors ("red", "darkred", etc.).

local au  = require("filetree.util.autocmd")
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
local ICON_HL   = "FiletreeCurrentIcon"

local function setup_hl_groups()
  ensure_hl_group(FILE_HL,   _cfg.file_hl   or { fg = "#7aa2f7", bold = true })
  ensure_hl_group(PARENT_HL, _cfg.parent_hl or { fg = "#565f89" })
  -- The icon gets its own group so it can be coloured independently of the
  -- line highlight; defaults to linking the file highlight.
  ensure_hl_group(ICON_HL,   _cfg.icon_hl   or ("link:" .. FILE_HL))
end

-- ── Highlight application ─────────────────────────────────────────────────────

local function clear_old()
  if _last_file and _adapter then
    _adapter.unhighlight_node(_last_file)
    if _cfg.icon and type(_adapter.unsign_node) == "function" then
      _adapter.unsign_node(_last_file)
    end
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

  -- Optional sign-column marker on the current file's line (distinguishes the
  -- focused buffer from the tree plugin's generic "opened files" colouring).
  if _cfg.icon and _cfg.icon ~= "" and type(_adapter.sign_node) == "function" then
    _adapter.sign_node(path, _cfg.icon, ICON_HL)
  end

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
    au.del_group(_augroup)
  end
  _augroup = au.group("filetree_current_hl", true)

  au.acmd({ "BufEnter", "WinEnter", "BufWritePost" }, {
    group    = _augroup,
    callback = debounced_apply,
  })

  -- Re-apply after colorscheme changes
  au.acmd("ColorScheme", {
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
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
