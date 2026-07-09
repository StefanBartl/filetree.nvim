---@module 'filetree.adapter.mini_files'
---@brief mini.files adapter — implements the FiletreeAdapter interface for mini.files.

-- Imported as `pathutil` (not `path`) because `path` is used pervasively below as
-- a local parameter/variable name for a plain path string; importing under that
-- same name would silently shadow the module in every such function.
local pathutil = require("filetree.util.path")
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

-- `state.windows` is an array of `{ win_id, path }` TABLES (one per opened
-- branch column), not plain window handles — MiniFiles.get_explorer_state()'s
-- own docs spell this out ("Each element is a table with <win_id> ... and
-- <path> ..."). An earlier version of this adapter passed the table itself to
-- nvim_win_is_valid()/nvim_win_get_buf(), which errors ("Expected Lua number").
---@param state table  result of MiniFiles.get_explorer_state()
---@return integer?
local function last_win_id(state)
  local wins = state.windows
  if not wins or #wins == 0 then return nil end
  local entry = wins[#wins]
  return type(entry) == "table" and entry.win_id or nil
end

function M.is_open()
  local state = get_state()
  if state == nil then return false, nil end
  local win = last_win_id(state)
  if win and vim.api.nvim_win_is_valid(win) then
    return true, vim.api.nvim_win_get_buf(win)
  end
  -- Fallback: current buf if mini.files is active
  return true, nil
end

function M.get_winid()
  local state = get_state()
  if not state then return nil end
  local win = last_win_id(state)
  if win and vim.api.nvim_win_is_valid(win) then return win end
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
    -- MiniFiles.get_fs_entry(buf_id, line) takes positional args, not a table
    -- — an earlier version passed { buf = buf, line = line }, which fails
    -- get_fs_entry's own buffer-id validation (a table is never a valid
    -- buffer id) and throws, so this always returned zero entries (the pcall
    -- caught the error silently).
    local ok, entry = pcall(mf.get_fs_entry, buf, line)
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

-- mini.files' entry.path may not match a forward-slash query path style-for-style
-- (callers like cwd_sync/auto_reveal/current_hl source their path from
-- vim.api.nvim_buf_get_name()/expand("%:p")). Normalize both sides before
-- comparing, so a mismatched separator style can't cause a silent miss.
--
-- mini.files also has its own quirk on Windows: its internal path-join inserts
-- a doubled slash right after the drive letter (e.g. `mf.open("E:/repos")`
-- produces state.anchor/entry.path as "E://repos/..."), which a plain
-- backslash->forward-slash pass doesn't fix. Collapse any run of slashes that
-- follows a non-slash character down to one; a pattern requiring a preceding
-- character never touches a genuine leading UNC "//", so that stays intact.
---@param p string
---@return string
local function normalize_key(p)
  return (pathutil.slashify(p):gsub("(%S)/+", "%1/"))
end

function M.get_node_line(node_path)
  local query = normalize_key(node_path)
  local nodes = M.get_visible_nodes()
  for _, node in ipairs(nodes) do
    if node.path and normalize_key(node.path) == query then return node.line_number end
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
