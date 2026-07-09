---@module 'filetree.adapter.oil'
---@brief oil.nvim adapter — implements the FiletreeAdapter interface for oil.nvim.

-- Imported as `pathutil` (not `path`) because `path` is used pervasively below as
-- a local parameter/variable name for a plain path string; importing under that
-- same name would silently shadow the module in every such function.
local pathutil = require("filetree.util.path")
local registry = require("filetree.adapter")

---@class FiletreeOilAdapter : FiletreeAdapter
local M = { name = "oil", filetypes = { "oil" } }

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

  -- Parse each rendered line via oil's own public parser (get_entry_on_line),
  -- the same API get_current_node()/get_cursor_entry() already relies on.
  -- oil buffers are NOT plain "one name per line" text: oil always prepends an
  -- internal entry id to the real buffer line ("Id is automatically added at
  -- the beginning" per oil's own config docs) — an earlier version of this
  -- function tried a non-existent `oil.get_entries_for_url` API and then fell
  -- back to naively trimming the raw line, which included that id prefix in
  -- every parsed name (e.g. "/001 init.lua"), corrupting every path built from
  -- it. get_entry_on_line strips the id correctly.
  local line_count = vim.api.nvim_buf_line_count(buf)
  local nodes = {}
  for line_n = 1, line_count do
    local ok_entry, entry = pcall(oil.get_entry_on_line, buf, line_n)
    if ok_entry and entry and entry.name then
      local ntype  = (entry.type == "directory") and "directory" or "file"
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
          line_number = line_n,
          is_expanded = nil,
        }
      end
    end
  end
  return nodes
end

-- oil builds node.path as `dir .. entry.name`, where dir comes from
-- oil.get_current_dir() — while callers (cwd_sync/auto_reveal/current_hl) query
-- with forward-slash paths sourced from
-- vim.api.nvim_buf_get_name()/expand("%:p"). Normalize both sides before
-- comparing, so a mismatched separator style can't cause a silent miss.
function M.get_node_line(node_path)
  local query = pathutil.slashify(node_path)
  local nodes = M.get_visible_nodes()
  for _, node in ipairs(nodes) do
    if node.path and pathutil.slashify(node.path) == query then return node.line_number end
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

---Call `oil.open(dir)`, targeting the existing oil window when one is open
---instead of whatever window happens to be current. `oil.open()` runs
---`vim.cmd.edit()` internally, which acts on the CURRENT window — unlike
---neo-tree/nvim-tree, which manage a dedicated tree window internally
---regardless of focus, oil has no such concept (every oil buffer is a normal
---buffer in whatever window you open it from). Without this, a reveal
---triggered while the user's focus is in the editor (e.g. from
---cwd_sync/auto_reveal on BufEnter) would silently hijack the EDITOR window
---into a directory listing instead of updating the oil split.
---@param oil table
---@param dir string
---@return boolean
local function open_in_tree_win(oil, dir)
  local cur_win = vim.api.nvim_get_current_win()
  local tree_win = M.get_winid()
  if tree_win and tree_win ~= cur_win and vim.api.nvim_win_is_valid(tree_win) then
    vim.api.nvim_set_current_win(tree_win)
  end
  local ok = pcall(oil.open, dir)
  if tree_win and tree_win ~= cur_win and vim.api.nvim_win_is_valid(cur_win) then
    vim.api.nvim_set_current_win(cur_win)
  end
  return ok
end

function M.open_reveal(path, _parent_levels)
  local oil = get_oil()
  if not oil then return false end
  local dir = vim.fn.fnamemodify(path, ":h")
  return open_in_tree_win(oil, dir)
end

function M.set_root(path)
  local oil = get_oil()
  if not oil then return false end
  return open_in_tree_win(oil, path)
end

function M.open_cwd()
  local oil = get_oil()
  if not oil then return false end
  return open_in_tree_win(oil, vim.fn.getcwd())
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
