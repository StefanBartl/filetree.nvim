---@module 'filetree.adapter.mini_files'
---@brief mini.files adapter — implements the FiletreeAdapter interface for mini.files.

local registry = require("filetree.adapter")

---@class FiletreeMiniFilesAdapter : FiletreeAdapter
local M = { name = "mini_files", filetypes = { "minifiles" } }

local _ns = nil

local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_mini_files") end
  return _ns
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function get_mf()
  local ok, mf = pcall(require, "mini.files")
  if not ok then return nil end
  return mf
end

---Get explorer state (nil when mini.files is not open).
local function get_state()
  local mf = get_mf()
  if not mf or not mf.get_explorer_state then return nil end
  local ok, state = pcall(mf.get_explorer_state)
  if not ok then return nil end
  return state
end

-- ── Interface ─────────────────────────────────────────────────────────────────

function M.is_available()
  local ok = pcall(require, "mini.files")
  return ok
end

function M.is_open()
  local state = get_state()
  if state == nil then return false, nil end
  -- Get the focused buffer from state windows
  local wins = state.windows
  if wins and #wins > 0 then
    local win = wins[#wins]
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      return true, buf
    end
  end
  -- Fallback: current buf if mini.files is active
  return true, nil
end

function M.get_winid()
  local state = get_state()
  if not state then return nil end
  local wins = state.windows
  if wins and #wins > 0 then
    local win = wins[#wins]
    if vim.api.nvim_win_is_valid(win) then return win end
  end
  return nil
end

function M.get_bufnr()
  local _, buf = M.is_open()
  return buf
end

function M.get_root_path()
  local state = get_state()
  if not state then return vim.fn.getcwd() end
  -- anchor is the root directory opened
  if state.anchor and state.anchor ~= "" then return state.anchor end
  return vim.fn.getcwd()
end

function M.get_current_node()
  local mf = get_mf()
  if not mf or not mf.get_fs_entry then return nil end

  local ok, entry = pcall(mf.get_fs_entry)
  if not ok or not entry then return nil end

  local ntype = (entry.fs_type == "directory") and "directory" or "file"

  local win  = M.get_winid()
  local line_nr = win and vim.api.nvim_win_get_cursor(win)[1] or 0

  return {
    id          = entry.path,
    name        = entry.name,
    path        = entry.path,
    type        = ntype,
    depth       = 1,
    line_number = line_nr,
    is_expanded = ntype == "directory" and false or nil,
  }
end

function M.get_visible_nodes(filter)
  local mf = get_mf()
  if not mf or not mf.get_fs_entry then return {} end

  local win = M.get_winid()
  if not win then return {} end

  local buf    = vim.api.nvim_win_get_buf(win)
  local count  = vim.api.nvim_buf_line_count(buf)
  local nodes  = {}

  for line = 1, count do
    local ok, entry = pcall(mf.get_fs_entry, { buf = buf, line = line })
    if ok and entry then
      local ntype = (entry.fs_type == "directory") and "directory" or "file"
      local include = filter == nil or filter == "all"
        or (filter == "files"   and ntype == "file")
        or (filter == "folders" and ntype == "directory")
      if include then
        nodes[#nodes + 1] = {
          id          = entry.path,
          name        = entry.name,
          path        = entry.path,
          type        = ntype,
          depth       = 1,
          line_number = line,
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
  local mf = get_mf()
  if mf then pcall(mf.close) end
  mode = mode or "edit"
  local cmd_map = { edit = "edit", split = "split", vsplit = "vsplit", tab = "tabnew" }
  local cmd = cmd_map[mode] or "edit"
  local ok = pcall(vim.cmd, cmd .. " " .. vim.fn.fnameescape(path))
  return ok
end

function M.open_reveal(path, _parent_levels)
  local mf = get_mf()
  if not mf then return false end
  local dir = vim.fn.fnamemodify(path, ":h")
  local ok  = pcall(mf.open, dir)
  return ok
end

function M.set_root(path)
  local mf = get_mf()
  if not mf then return false end
  local ok = pcall(mf.open, path)
  return ok
end

function M.open_cwd()
  local mf = get_mf()
  if not mf then return false end
  local ok = pcall(mf.open, vim.fn.getcwd())
  return ok
end

function M.close()
  local mf = get_mf()
  if not mf then return false end
  local ok = pcall(mf.close)
  return ok
end

function M.refresh()
  local mf = get_mf()
  if not mf then return false end
  local root = M.get_root_path()
  local ok1  = pcall(mf.close)
  local ok2  = pcall(mf.open, root)
  return ok1 and ok2
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
