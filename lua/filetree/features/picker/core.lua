---@module 'filetree.features.picker.core'
---@brief Picker mode state machine — handles digit input, mode switching, node selection.

local renderer = require("filetree.features.picker.renderer")
local keymaps  = require("filetree.features.picker.keymaps")
local notify   = require("filetree.util.notify").create("[filetree.picker]")

local M = {}

---@class PickerState
---@field active        boolean
---@field adapter_name  string?
---@field bufnr         integer?
---@field winid         integer?
---@field current_mode  string
---@field filter_mode   FiletreeFilterMode
---@field input_buffer  string
---@field visible_nodes FiletreeNode[]
---@field saved_maps    table
---@field timer         any?

---@type PickerState
M.state = {
  active        = false,
  adapter_name  = nil,
  bufnr         = nil,
  winid         = nil,
  current_mode  = "edit",
  filter_mode   = "all",
  input_buffer  = "",
  visible_nodes = {},
  saved_maps    = {},
  timer         = nil,
}

---@type FiletreePickerConfig
local _cfg = {}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Timer ─────────────────────────────────────────────────────────────────────

local function cancel_timer()
  if M.state.timer then
    pcall(function()
      M.state.timer:stop()
      M.state.timer:close()
    end)
    M.state.timer = nil
  end
end

local function start_timer()
  cancel_timer()
  local uv = vim.uv or vim.loop
  M.state.timer = uv.new_timer()
  M.state.timer:start((_cfg.timeout_ms or 3000), 0, vim.schedule_wrap(function()
    if M.state.active then M.exit() end
  end))
end

-- ── State machine ─────────────────────────────────────────────────────────────

function M.update_nodes()
  if not M.state.active or not _adapter then return end
  M.state.visible_nodes = _adapter.get_visible_nodes(M.state.filter_mode)
  if M.state.bufnr and M.state.winid then
    renderer.update(M.state.bufnr, M.state.winid, M.state.visible_nodes, M.state.current_mode)
  end
end

---Enter picker mode.
---@param bufnr integer
---@param winid integer
function M.enter(bufnr, winid)
  if M.state.active then M.exit() end

  M.state.active        = true
  M.state.bufnr         = bufnr
  M.state.winid         = winid
  M.state.current_mode  = "edit"
  M.state.filter_mode   = "all"
  M.state.input_buffer  = ""
  M.state.visible_nodes = {}
  M.state.saved_maps    = keymaps.save(bufnr)

  keymaps.install(bufnr, {
    on_digit        = function(d) M.handle_digit(d) end,
    on_mode_prefix  = function(k) M.handle_mode_prefix(k) end,
    on_escape       = function()  M.exit() end,
    on_cycle_filter = function()  M.cycle_filter() end,
    on_scroll_up    = function()  M.scroll(-1) end,
    on_scroll_down  = function()  M.scroll(1) end,
  })

  M.update_nodes()
  start_timer()
end

function M.exit()
  if not M.state.active then return end
  cancel_timer()
  if M.state.bufnr then
    renderer.clear(M.state.bufnr)
    keymaps.restore(M.state.bufnr, M.state.saved_maps)
  end
  M.state.active        = false
  M.state.bufnr         = nil
  M.state.winid         = nil
  M.state.adapter_name  = nil
  M.state.input_buffer  = ""
  M.state.visible_nodes = {}
  M.state.saved_maps    = {}
end

function M.handle_mode_prefix(key)
  if not M.state.active then return end
  if #M.state.input_buffer > 0 and not keymaps.is_mode_prefix(M.state.input_buffer:sub(1, 1)) then
    return
  end
  local mode = keymaps.mode_from_prefix(key)
  if mode then
    M.state.current_mode = mode
    M.state.input_buffer = key
    if M.state.bufnr and M.state.winid then
      renderer.update(M.state.bufnr, M.state.winid, M.state.visible_nodes, mode)
    end
    start_timer()
  end
end

function M.handle_digit(digit)
  if not M.state.active then return end
  M.state.input_buffer = M.state.input_buffer .. digit

  -- Strip leading mode prefix if present
  local raw = M.state.input_buffer
  if keymaps.is_mode_prefix(raw:sub(1, 1)) then
    raw = raw:sub(2)
  end

  local width = _cfg.index_width or 2
  if #raw >= width then
    local idx = tonumber(raw:sub(-width))
    if idx then
      M.handle_selection(idx)
    else
      start_timer()
    end
  else
    start_timer()
  end
end

function M.handle_selection(index)
  if not M.state.active or not _adapter then return end
  local node = M.state.visible_nodes[index]
  if not node then
    M.exit()
    return
  end

  if node.type == "file" then
    _adapter.open_file(node.path, M.state.current_mode)
    M.exit()
  elseif node.type == "directory" then
    if node.is_expanded then
      _adapter.collapse_node(node)
    else
      _adapter.expand_node(node)
    end
    vim.defer_fn(function()
      M.state.input_buffer = ""
      M.update_nodes()
      start_timer()
    end, 100)
  end
end

function M.cycle_filter()
  if not M.state.active then return end
  local cycle = { all = "files", files = "folders", folders = "all" }
  M.state.filter_mode = cycle[M.state.filter_mode] or "all"
  M.update_nodes()
  start_timer()
end

function M.scroll(direction)
  if not M.state.active or not _adapter then return end
  local winid = M.state.winid or _adapter.get_winid()
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end
  local cur = vim.api.nvim_win_get_cursor(winid)
  local new_line = math.max(1, cur[1] + direction)
  pcall(vim.api.nvim_win_set_cursor, winid, { new_line, 0 })
  start_timer()
end

-- ── Public setup ──────────────────────────────────────────────────────────────

---@param config  FiletreePickerConfig
---@param adapter FiletreeAdapter
function M.init(config, adapter)
  _cfg     = config
  _adapter = adapter
end

---Start picker in reveal mode (reveal current buffer's file).
---@param parent_levels? integer
function M.start_reveal(parent_levels)
  if not _adapter then
    notify.warn("no adapter configured")
    return
  end
  local file = vim.fn.expand("%:p")
  if file == "" then
    notify.warn("no file in current buffer")
    return
  end

  local ok = _adapter.open_reveal(file, parent_levels or 0)
  if not ok then
    notify.error("reveal failed")
    return
  end

  vim.defer_fn(function()
    local is_open, bufnr = _adapter.is_open()
    local winid = _adapter.get_winid()
    if is_open and bufnr and winid then
      M.enter(bufnr, winid)
    end
  end, 200)
end

---Start picker at current working directory.
function M.start_cwd()
  if not _adapter then return end
  local ok = _adapter.open_cwd()
  if not ok then return end
  vim.defer_fn(function()
    local is_open, bufnr = _adapter.is_open()
    local winid = _adapter.get_winid()
    if is_open and bufnr and winid then
      M.enter(bufnr, winid)
    end
  end, 200)
end

return M
