---@module 'filetree.features.breadcrumbs'
---@brief Show the path from project root to the current node as breadcrumbs.
---@description
--- Three display modes (configurable):
---   "winbar"    Set &winbar of the editor window (requires Neovim 0.8+)
---   "float"     Small 1-line floating window anchored to the tree window top
---   "statusline" Provide M.component() for statusline integration
---
--- The breadcrumb string is rebuilt on CursorMoved in the tree buffer and
--- on BufEnter in any editor buffer (syncing the breadcrumb to the editor
--- file's path relative to the project root).
---
--- Format: root  /  parent  /  child  /  filename
--- The separator, max depth, and highlight groups are configurable.

local notify = require("filetree.util.notify").create("[filetree.breadcrumbs]")

local M = {}

---@type FiletreeBreadcrumbsConfig
local _cfg = {
  enabled     = false,
  mode        = "winbar",  -- "winbar"|"float"|"statusline"
  separator   = "  ",
  max_depth   = 5,
  hl_dir      = "Comment",
  hl_file     = "Normal",
  hl_sep      = "NonText",
  winbar_hl   = "WinBar",
}

---@type FiletreeAdapter?
local _adapter = nil

---@type string  last computed breadcrumb string (plain text)
local _current = ""

---@type integer?  float window id
local _float_win  = nil
---@type integer?  float buffer id
local _float_buf  = nil

-- ── Path → breadcrumb ─────────────────────────────────────────────────────────

---@param path string  Absolute file or directory path.
---@return string plain, string highlighted
local function build(path)
  if not path or path == "" then return "", "" end

  -- Get project root for relative base
  local root
  local ok_pr, pr = require("filetree.features").load("project_root")
  if ok_pr and type(pr.find) == "function" then
    root = pr.find(path)
  else
    root = vim.fn.getcwd()
  end

  -- Compute parts relative to root
  local rel = path
  if root and path:sub(1, #root) == root then
    rel = path:sub(#root + 2)  -- skip trailing slash
  end

  local parts = {}
  for part in (rel .. "/"):gmatch("([^/\\]+)[/\\]") do
    parts[#parts + 1] = part
  end
  -- The last element might be the filename (no trailing slash in original)
  if vim.fn.isdirectory(path) == 0 then
    -- last part is a file — already in parts from above (rel ends without /)
    -- Actually re-parse correctly:
    parts = {}
    for part in rel:gmatch("[^/\\]+") do
      parts[#parts + 1] = part
    end
  end

  -- Depth limit
  if #parts > _cfg.max_depth then
    local trimmed = { "…" }
    for i = #parts - (_cfg.max_depth - 1), #parts do
      trimmed[#trimmed + 1] = parts[i]
    end
    parts = trimmed
  end

  if #parts == 0 then
    return vim.fn.fnamemodify(root or path, ":t"), ""
  end

  local plain = table.concat(parts, _cfg.separator)

  -- Build highlighted string for winbar (%#HlGroup#text resets at end)
  local hl_parts = {}
  for i, p in ipairs(parts) do
    local is_last = (i == #parts)
    local hl = is_last and _cfg.hl_file or _cfg.hl_dir
    hl_parts[#hl_parts + 1] = "%#" .. hl .. "#" .. p
    if not is_last then
      hl_parts[#hl_parts + 1] = "%#" .. _cfg.hl_sep .. "#" .. _cfg.separator
    end
  end
  local highlighted = table.concat(hl_parts) .. "%#" .. _cfg.winbar_hl .. "#"

  return plain, highlighted
end

-- ── Display modes ─────────────────────────────────────────────────────────────

local function update_winbar(highlighted, target_win)
  if not target_win or not vim.api.nvim_win_is_valid(target_win) then return end
  -- Set winbar on all non-tree, non-floating windows
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= target_win and vim.api.nvim_win_is_valid(win) then
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative == "" then  -- not floating
        local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
        if ft ~= "neo-tree" and ft ~= "NvimTree" then
          pcall(vim.api.nvim_set_option_value, "winbar",
            " " .. highlighted, { win = win })
        end
      end
    end
  end
end

local function close_float()
  if _float_win and vim.api.nvim_win_is_valid(_float_win) then
    pcall(vim.api.nvim_win_close, _float_win, true)
  end
  if _float_buf and vim.api.nvim_buf_is_valid(_float_buf) then
    pcall(vim.api.nvim_buf_delete, _float_buf, { force = true })
  end
  _float_win = nil
  _float_buf = nil
end

local function update_float(plain)
  if not _adapter then return end
  local tree_win = _adapter.get_winid and _adapter.get_winid() or -1
  if tree_win < 0 or not vim.api.nvim_win_is_valid(tree_win) then
    close_float()
    return
  end

  local pos   = vim.api.nvim_win_get_position(tree_win)
  local width = vim.api.nvim_win_get_width(tree_win)
  local text  = " " .. plain

  if not _float_buf or not vim.api.nvim_buf_is_valid(_float_buf) then
    _float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype",    "nofile", { buf = _float_buf })
    vim.api.nvim_set_option_value("bufhidden",  "wipe",   { buf = _float_buf })
    vim.api.nvim_set_option_value("modifiable", false,    { buf = _float_buf })
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = _float_buf })
  vim.api.nvim_buf_set_lines(_float_buf, 0, -1, false, { text })
  vim.api.nvim_set_option_value("modifiable", false, { buf = _float_buf })

  local float_cfg = {
    relative  = "editor",
    row       = pos[1],
    col       = pos[2],
    width     = math.max(width, #text + 1),
    height    = 1,
    style     = "minimal",
    border    = "none",
    focusable = false,
    zindex    = 10,
  }

  if _float_win and vim.api.nvim_win_is_valid(_float_win) then
    vim.api.nvim_win_set_config(_float_win, float_cfg)
  else
    _float_win = vim.api.nvim_open_win(_float_buf, false, float_cfg)
    vim.api.nvim_set_option_value("winhl",
      "Normal:" .. _cfg.winbar_hl, { win = _float_win })
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Recompute and display the breadcrumb for `path`.
---@param path string
function M.update(path)
  local plain, highlighted = build(path)
  _current = plain

  local mode = _cfg.mode
  if mode == "winbar" then
    local tree_win = _adapter and _adapter.get_winid and _adapter.get_winid() or -1
    update_winbar(highlighted, tree_win)
  elseif mode == "float" then
    update_float(plain)
  end
  -- "statusline" mode: consumers call M.component()
end

---Return the current breadcrumb as a plain string (for statusline use).
---@return string
function M.component()
  return _current
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeBreadcrumbsConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_breadcrumbs", { clear = true })

  -- Update when cursor moves in tree
  vim.api.nvim_create_autocmd("CursorMoved", {
    group   = _augroup,
    pattern = "*",
    callback = function()
      local ft = vim.bo.filetype
      if ft ~= "neo-tree" and ft ~= "NvimTree" then return end
      if not _adapter then return end
      local node = _adapter.get_current_node()
      if node then M.update(node.path) end
    end,
  })

  -- Update when editor buffer changes
  vim.api.nvim_create_autocmd("BufEnter", {
    group    = _augroup,
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" then return end
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if path and path ~= "" then M.update(path) end
    end,
  })

  -- Close float when tree is closed
  if _cfg.mode == "float" then
    vim.api.nvim_create_autocmd("WinClosed", {
      group    = _augroup,
      callback = function(ev)
        if not _adapter then return end
        local tree_win = _adapter.get_winid and _adapter.get_winid() or -1
        if tonumber(ev.match) == tree_win then close_float() end
      end,
    })
  end
end

function M.teardown()
  close_float()
  _current  = ""
  _adapter  = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
