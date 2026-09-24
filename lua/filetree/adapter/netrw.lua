---@module 'filetree.adapter.netrw'
--- netrw adapter — implements the FiletreeAdapter interface for Neovim's built-in netrw.

-- Imported as `pathutil` (not `path`) because `path` is used pervasively below as
-- a local parameter/variable name for a plain path string; importing under that
-- same name would silently shadow the module in every such function.
local pathutil = require("filetree.util.path")
local registry = require("filetree.adapter")

---@class FiletreeNetrwAdapter : FiletreeAdapter
local M = { name = "netrw", filetypes = { "netrw" } }

local _ns = nil

---@internal
local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_netrw") end
  return _ns
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

---Find the first open netrw buffer.
---@internal
---@return integer?  bufnr
local function find_netrw_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "netrw" then return buf end
  end
  return nil
end

---Find the window displaying a given buffer.
---@internal
---@param bufnr integer
---@return integer?  winid
local function buf_to_win(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then return win end
  end
  return nil
end

---netrw's per-entry type-suffix markers (glob-style listing): "/" a plain
---directory, "@" a symlink, "*" an executable file, "=" a socket, "|" a FIFO.
---@internal
local SUFFIX_MARKERS = { ["/"] = true, ["@"] = true, ["*"] = true, ["="] = true, ["|"] = true }

---Split netrw's raw entry text into its real name and type.
---
---A symlink always gets netrw's "@" suffix, never "/", even when it points at
---a directory -- netrw's own listing code checks `getftype() == "link"`
---before `isdirectory()` (see `s:NetrwLocalListingList` in netrw.vim), so "@"
---says nothing about what the link actually resolves to. Resolved here via a
---real stat (follows the symlink) so `type` reflects the target, matching how
---a symlinked directory behaves everywhere else in this plugin (e.g.
---`open_variants`'s `<S-CR>` collapsing it rather than adding it to the buffer
---list).
---
---Every marker is stripped from `clean_name` regardless of which one it is,
---not just "/" -- left in place it silently corrupted `path` (and therefore
---`id`) for every symlink/executable/socket/fifo entry, not only their `type`.
---@internal
---@param root string
---@param raw_name string
---@return string clean_name, string path, "file"|"directory" ntype
local function resolve_netrw_entry(root, raw_name)
  local suffix = raw_name:sub(-1)
  local clean_name = SUFFIX_MARKERS[suffix] and raw_name:sub(1, -2) or raw_name
  local path = root .. "/" .. clean_name

  local ntype = "file"
  if suffix == "/" then
    ntype = "directory"
  elseif suffix == "@" then
    local uv = vim.uv or vim.loop
    local ok, stat = pcall(uv.fs_stat, path)
    if ok and stat and stat.type == "directory" then ntype = "directory" end
  end

  return clean_name, path, ntype
end

---Parse a netrw buffer line to extract the filename.
---netrw renders filenames in the last column; directories end with /.
---@internal
---@param line string
---@return string?
local function parse_netrw_line(line)
  -- Skip header/banner lines (start with "\" or are blank)
  if line:match("^%s*$") or line:match("^%s*\\") then return nil end
  -- netrw lines: entries start after leading whitespace
  local name = line:match("^%s*(.-)%s*$")
  if not name or name == "" then return nil end
  -- Skip sort/filter header lines
  if name:match('^"') or name:match("^%-%-") then return nil end
  return name
end

-- ── Interface ─────────────────────────────────────────────────────────────────

---netrw is always available — it is built in to Neovim.
---@return boolean
function M.is_available()
  return true
end

---@return boolean, integer? bufnr
function M.is_open()
  local buf = find_netrw_buf()
  if buf then return true, buf end
  return false, nil
end

---@return integer? winid
function M.get_winid()
  local buf = find_netrw_buf()
  if not buf then return nil end
  return buf_to_win(buf)
end

---@return integer? bufnr
function M.get_bufnr()
  return (select(2, M.is_open()))
end

---@return string? root_path
function M.get_root_path()
  local buf = find_netrw_buf()
  if not buf then return vim.fn.getcwd() end
  local curdir = vim.b[buf] and vim.b[buf].netrw_curdir
  if curdir and curdir ~= "" then return curdir end
  return vim.fn.getcwd()
end

---@return FiletreeNode?
function M.get_current_node()
  local buf = find_netrw_buf()
  if not buf then return nil end
  local win = buf_to_win(buf)
  if not win then return nil end

  local line_nr = vim.api.nvim_win_get_cursor(win)[1]
  local line = vim.api.nvim_buf_get_lines(buf, line_nr - 1, line_nr, false)[1] or ""
  local name = parse_netrw_line(line)
  if not name then return nil end

  local root = M.get_root_path()
  local clean_name, path, ntype = resolve_netrw_entry(root, name)

  return {
    id = path,
    name = clean_name,
    path = path,
    type = ntype,
    depth = 1,
    line_number = line_nr,
    is_expanded = nil,
  }
end

---@param filter? FiletreeFilterMode
---@return FiletreeNode[]
function M.get_visible_nodes(filter)
  local buf = find_netrw_buf()
  if not buf then return {} end

  local root = M.get_root_path()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local nodes = {}
  local line_nr = 0

  for _, line in ipairs(lines) do
    line_nr = line_nr + 1
    local name = parse_netrw_line(line)
    if name then
      local clean, path, ntype = resolve_netrw_entry(root, name)

      local include = filter == nil
        or filter == "all"
        or (filter == "files" and ntype == "file")
        or (filter == "folders" and ntype == "directory")

      if include then
        nodes[#nodes + 1] = {
          id = path,
          name = clean,
          path = path,
          type = ntype,
          depth = 1,
          line_number = line_nr,
          is_expanded = nil,
        }
      end
    end
  end

  return nodes
end

-- netrw builds node.path as `root .. "/" .. name`, where root can come from
-- vim.fn.getcwd() (native-separator, e.g. backslash on Windows) — while callers
-- (cwd_sync/auto_reveal/current_hl) query with forward-slash paths sourced from
-- vim.api.nvim_buf_get_name()/expand("%:p"). Normalize both sides before
-- comparing, or the lookup silently misses on Windows.
---@param node_path string
---@return integer? line_number
function M.get_node_line(node_path)
  local query = pathutil.slashify(node_path)
  local nodes = M.get_visible_nodes()
  for _, node in ipairs(nodes) do
    if node.path and pathutil.slashify(node.path) == query then return node.line_number end
  end
  return nil
end

---@param _node FiletreeNode
---@return boolean
function M.expand_node(_node)
  -- netrw doesn't have a tree expand concept; navigating into dir is the equivalent
  return false
end

---@param _node FiletreeNode
---@return boolean
function M.collapse_node(_node)
  return false
end

---@param path string
---@param mode? FiletreeOpenMode
---@return boolean
function M.open_file(path, mode)
  mode = mode or "edit"
  local cmd_map = { edit = "edit", split = "split", vsplit = "vsplit", tab = "tabnew" }
  local cmd = cmd_map[mode] or "edit"
  local ok = pcall(function()
    vim.cmd(cmd .. " " .. vim.fn.fnameescape(path))
  end)
  return ok
end

---Run `:Explore <dir>`, targeting the existing netrw window when one is open
---instead of whatever window happens to be current. `:Explore` reuses the
---CURRENT window — unlike neo-tree/nvim-tree/oil/mini_files, which manage a
---dedicated tree window internally regardless of focus, plain netrw has no such
---concept. Without this, a reveal triggered while the user's focus is in the
---editor (e.g. from cwd_sync/auto_reveal on BufEnter) would silently hijack the
---EDITOR window into a directory listing instead of updating the netrw split.
---@param dir string
---@return boolean
---@internal
local function explore_in_tree_win(dir)
  local cur_win = vim.api.nvim_get_current_win()
  local tree_win = M.get_winid()
  if tree_win and tree_win ~= cur_win and vim.api.nvim_win_is_valid(tree_win) then
    vim.api.nvim_set_current_win(tree_win)
  end
  local ok = pcall(function()
    vim.cmd("Explore " .. vim.fn.fnameescape(dir))
  end)
  if tree_win and tree_win ~= cur_win and vim.api.nvim_win_is_valid(cur_win) then
    vim.api.nvim_set_current_win(cur_win)
  end
  return ok
end

---@param path string
---@param _parent_levels? integer
---@return boolean
function M.open_reveal(path, _parent_levels)
  local dir = vim.fn.fnamemodify(path, ":h")
  return explore_in_tree_win(dir)
end

---@param path string
---@return boolean
function M.set_root(path)
  return explore_in_tree_win(path)
end

---@return boolean
function M.open_cwd()
  return explore_in_tree_win(vim.fn.getcwd())
end

---@return boolean
function M.close()
  local buf = find_netrw_buf()
  if not buf then return false end

  -- The netrw buffer is always displayed somewhere when it can be found at
  -- all (same find_netrw_buf/buf_to_win pair M.refresh below relies on) --
  -- its window must be closed before the buffer is deleted (UI-55), or
  -- `:bdelete` leaves the window open with an automatically created empty
  -- scratch buffer instead of actually closing it. Every other adapter's
  -- M.close() closes the tree's window via its own native command; closing
  -- the window here (not just deleting the buffer) matches that contract.
  local win = buf_to_win(buf)
  local ok = true
  if win and vim.api.nvim_win_is_valid(win) then ok = pcall(vim.api.nvim_win_close, win, true) end

  pcall(function()
    if vim.api.nvim_buf_is_valid(buf) then vim.cmd("bdelete " .. buf) end
  end)
  return ok
end

---@return boolean
function M.refresh()
  local buf = find_netrw_buf()
  if not buf then return false end
  local win = buf_to_win(buf)
  if not win then return false end
  -- Save cursor, re-edit
  local cursor = vim.api.nvim_win_get_cursor(win)
  local ok = pcall(function()
    vim.api.nvim_set_current_win(win)
    vim.cmd("edit")
    vim.api.nvim_win_set_cursor(win, cursor)
  end)
  return ok
end

---@param line integer
---@return boolean
function M.scroll_to_line(line)
  local win = M.get_winid()
  if not win then return false end
  local l = math.max(1, math.floor(line))
  local ok = pcall(vim.api.nvim_win_set_cursor, win, { l, 0 })
  return ok
end

---@type table<string, integer>
local _hl_marks = {}

---@param path string
---@param hl_group string
---@return boolean
function M.highlight_node(path, hl_group)
  local line = M.get_node_line(path)
  if not line then return false end
  local buf = M.get_bufnr()
  if not buf then return false end
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns(), line - 1, 0, {
    line_hl_group = hl_group,
    priority = 150,
  })
  if ok then _hl_marks[path] = id end
  return ok
end

---@param path string
---@return boolean
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
