---@module 'filetree.adapter.oil'
---@brief oil.nvim adapter — implements the FiletreeAdapter interface for oil.nvim.

local registry = require("filetree.adapter")

---@class FiletreeOilAdapter : FiletreeAdapter
local M = { name = "oil" }

local _ns = nil

local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_oil") end
  return _ns
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function get_oil()
  local ok, oil = pcall(require, "oil")
  if not ok then return nil end
  return oil
end

---Find the first open oil buffer.
---@return integer?
local function find_oil_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].filetype == "oil"
    then
      return buf
    end
  end
  return nil
end

---Find the window for a buffer.
---@param bufnr integer
---@return integer?
local function buf_to_win(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

-- ── Interface ─────────────────────────────────────────────────────────────────

function M.is_available()
  local ok = pcall(require, "oil")
  return ok
end

function M.is_open()
  local buf = find_oil_buf()
  if buf then return true, buf end
  return false, nil
end

function M.get_winid()
  local buf = find_oil_buf()
  if not buf then return nil end
  return buf_to_win(buf)
end

function M.get_bufnr()
  return (select(2, M.is_open()))
end

function M.get_root_path()
  local oil = get_oil()
  if not oil then return vim.fn.getcwd() end
  local ok, dir = pcall(oil.get_current_dir)
  if ok and dir then return dir end
  return vim.fn.getcwd()
end

function M.get_current_node()
  local oil = get_oil()
  if not oil then return nil end

  local ok, entry = pcall(oil.get_cursor_entry)
  if not ok or not entry then return nil end

  local dir_ok, dir = pcall(oil.get_current_dir)
  local current_dir = (dir_ok and dir) or vim.fn.getcwd()

  local path = current_dir .. entry.name
  local ntype = (entry.type == "directory") and "directory" or "file"

  local buf = find_oil_buf()
  local win = buf and buf_to_win(buf)
  local line_nr = win and vim.api.nvim_win_get_cursor(win)[1] or 0

  return {
    id          = path,
    name        = entry.name,
    path        = path,
    type        = ntype,
    depth       = 1,
    line_number = line_nr,
    is_expanded = ntype == "directory" and false or nil,
  }
end

function M.get_visible_nodes(filter)
  local oil = get_oil()
  if not oil then return {} end

  local buf = find_oil_buf()
  if not buf then return {} end

  local ok, current_dir = pcall(oil.get_current_dir)
  local dir = (ok and current_dir) or vim.fn.getcwd()

  -- Try oil's entries API first
  local entries_ok, entries = pcall(oil.get_entries_for_url or function() return nil end, dir)
  if entries_ok and entries then
    local nodes = {}
    for i, entry in ipairs(entries) do
      local ntype = (entry.type == "directory") and "directory" or "file"
      local include = filter == nil or filter == "all"
        or (filter == "files"   and ntype == "file")
        or (filter == "folders" and ntype == "directory")
      if include then
        local path = dir .. entry.name
        nodes[#nodes + 1] = {
          id          = path,
          name        = entry.name,
          path        = path,
          type        = ntype,
          depth       = 1,
          line_number = i,
          is_expanded = nil,
        }
      end
    end
    return nodes
  end

  -- Fallback: parse buffer lines
  local lines  = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local nodes  = {}
  local line_n = 0
  for _, line in ipairs(lines) do
    line_n = line_n + 1
    local name = line:match("^%s*(.-)%s*$")
    if name and name ~= "" then
      local is_dir = name:sub(-1) == "/"
      local clean  = is_dir and name:sub(1, -2) or name
      local ntype  = is_dir and "directory" or "file"
      local include = filter == nil or filter == "all"
        or (filter == "files"   and ntype == "file")
        or (filter == "folders" and ntype == "directory")
      if include then
        local path = dir .. clean
        nodes[#nodes + 1] = {
          id          = path,
          name        = clean,
          path        = path,
          type        = ntype,
          depth       = 1,
          line_number = line_n,
          is_expanded = nil,
        }
      end
    end
  end
  return nodes
end

function M.get_node_line(path)
  local nodes = M.get_visible_nodes()
  for _, node in ipairs(nodes) do
    if node.path == path then return node.line_number end
  end
  return nil
end

function M.expand_node(_node) return false end
function M.collapse_node(_node) return false end

function M.open_file(path, mode)
  local oil = get_oil()
  if oil then pcall(oil.close) end
  mode = mode or "edit"
  local cmd_map = { edit = "edit", split = "split", vsplit = "vsplit", tab = "tabnew" }
  local cmd = cmd_map[mode] or "edit"
  local ok = pcall(vim.cmd, cmd .. " " .. vim.fn.fnameescape(path))
  return ok
end

function M.open_reveal(path, _parent_levels)
  local oil = get_oil()
  if not oil then return false end
  local dir = vim.fn.fnamemodify(path, ":h")
  local ok  = pcall(oil.open, dir)
  return ok
end

function M.set_root(path)
  local oil = get_oil()
  if not oil then return false end
  local ok = pcall(oil.open, path)
  return ok
end

function M.open_cwd()
  local oil = get_oil()
  if not oil then return false end
  local ok = pcall(oil.open, vim.fn.getcwd())
  return ok
end

function M.close()
  local oil = get_oil()
  if not oil then return false end
  local ok = pcall(oil.close)
  return ok
end

function M.refresh()
  local oil = get_oil()
  if not oil then return false end
  -- discard_all_changes forces a reload
  if oil.discard_all_changes then
    local ok = pcall(oil.discard_all_changes)
    return ok
  end
  local buf = find_oil_buf()
  if not buf then return false end
  local ok = pcall(vim.cmd, "edit")
  return ok
end

function M.scroll_to_line(line)
  local win = M.get_winid()
  if not win then return false end
  local l = math.max(1, math.floor(line))
  local ok = pcall(vim.api.nvim_win_set_cursor, win, { l, 0 })
  return ok
end

---@type table<string, integer>
local _hl_marks = {}

function M.highlight_node(path, hl_group)
  local line = M.get_node_line(path)
  if not line then return false end
  local buf = M.get_bufnr()
  if not buf then return false end
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns(), line - 1, 0, {
    line_hl_group = hl_group,
    priority      = 150,
  })
  if ok then _hl_marks[path] = id end
  return ok
end

function M.unhighlight_node(path)
  local id = _hl_marks[path]
  if not id then return true end
  local buf = M.get_bufnr()
  if not buf then return false end
  local ok = pcall(vim.api.nvim_buf_del_extmark, buf, ns(), id)
  _hl_marks[path] = nil
  return ok
end

-- Self-register
registry.register(M)

return M
