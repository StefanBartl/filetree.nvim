---@module 'filetree.features.marks'
---@brief Node marking system — toggle marks, visual indicators, batch operations.
---@description
--- Marks are stored per-session as a set of absolute paths. Visual indicators
--- are rendered as extmarks in the tree buffer. Marked paths are exposed for
--- use in batch operations (copy, move, delete, etc.).

local notify = require("filetree.util.notify").create("[filetree.marks]")

local M = {}

---@type FiletreeMarksConfig
local _cfg = {
  enabled   = false,
  indicator = "✓",
  hl_group  = "DiagnosticOk",
  keymap    = "m",
}

---@type FiletreeAdapter?
local _adapter = nil

---@type table<string, boolean>  absolute path → marked
local _marks = {}

local _ns = nil
local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_marks") end
  return _ns
end

-- ── Internal ──────────────────────────────────────────────────────────────────

local function redraw()
  if not _adapter then return end
  local is_open, bufnr = _adapter.is_open()
  if not is_open or not bufnr then return end

  vim.api.nvim_buf_clear_namespace(bufnr, ns(), 0, -1)

  local nodes = _adapter.get_visible_nodes()
  for _, node in ipairs(nodes) do
    if _marks[node.path] then
      local line = node.line_number - 1
      if line >= 0 then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns(), line, 0, {
          virt_text     = { { _cfg.indicator .. " ", _cfg.hl_group } },
          virt_text_pos = "overlay",
          priority      = 100,
        })
      end
    end
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Toggle the mark on `path`.
---@param path string
---@return boolean  New marked state.
function M.toggle(path)
  if _marks[path] then
    _marks[path] = nil
  else
    _marks[path] = true
  end
  redraw()
  return _marks[path] == true
end

---Toggle mark on the node currently under the cursor.
---@return boolean?  New marked state, or nil when no node is found.
function M.toggle_current()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()
  if not node then
    notify.warn("no node under cursor")
    return nil
  end
  return M.toggle(node.path)
end

---Return true when `path` is marked.
---@param path string
---@return boolean
function M.is_marked(path)
  return _marks[path] == true
end

---Return all currently marked paths.
---@return string[]
function M.get_marked()
  local out = {}
  for p in pairs(_marks) do out[#out + 1] = p end
  table.sort(out)
  return out
end

---Return the count of marked items.
---@return integer
function M.count()
  local n = 0
  for _ in pairs(_marks) do n = n + 1 end
  return n
end

---Clear all marks.
function M.clear_all()
  _marks = {}
  redraw()
end

---Mark all currently visible nodes.
function M.mark_all_visible()
  if not _adapter then return end
  local nodes = _adapter.get_visible_nodes()
  for _, node in ipairs(nodes) do
    _marks[node.path] = true
  end
  redraw()
end

---Show a floating summary of all marked paths.
function M.show()
  local marked = M.get_marked()
  if #marked == 0 then
    notify.info("No nodes marked")
    return
  end

  local lines = {
    string.format("Marked nodes (%d)", #marked),
    string.rep("─", 50),
  }
  for i, p in ipairs(marked) do
    lines[#lines + 1] = string.format("[%02d] %s", i, p)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("bufhidden", "wipe",     { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false,     { buf = buf })

  local width  = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 1, vim.o.lines - 6)

  vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = math.floor((vim.o.lines - height) / 2),
    col       = math.floor((vim.o.columns - width) / 2),
    style     = "minimal",
    border    = "rounded",
    title     = " Marked Nodes ",
    title_pos = "center",
  })
  vim.keymap.set("n", "q",     "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeMarksConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_marks", { clear = true })

  -- Redraw marks whenever the tree buffer is entered/refreshed
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group    = _augroup,
    pattern  = "*",
    callback = function()
      vim.defer_fn(redraw, 50)
    end,
  })

  -- Keymap inside tree buffer to toggle mark on current node
  if _cfg.keymap then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        vim.keymap.set("n", _cfg.keymap, function()
          M.toggle_current()
        end, { buffer = ev.buf, silent = true, desc = "Filetree: toggle mark" })
      end,
    })
  end

end

function M.teardown()
  _marks = {}
  if _adapter then
    local _, bufnr = _adapter.is_open()
    if bufnr then
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns(), 0, -1)
    end
  end
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
  _adapter = nil
end

return M
