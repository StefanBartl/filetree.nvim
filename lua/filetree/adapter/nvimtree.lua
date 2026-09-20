---@module 'filetree.adapter.nvimtree'
--- nvim-tree adapter — implements FiletreeAdapter for nvim-tree.lua.

local notify = require("filetree.util.notify").create("[filetree.adapter.nvimtree]")
-- Imported as `pathutil` (not `path`) because `path` is used pervasively below as
-- a local parameter/variable name for a plain path string; importing under that
-- same name would silently shadow the module in every such function.
local pathutil = require("filetree.util.path")
local registry = require("filetree.adapter")

---@class FiletreeNvimtreeAdapter : FiletreeAdapter
local M = {
  name = "nvimtree",
  filetypes = { "NvimTree" },
  hl_groups = {
    NvimTreeNormal = "Normal",
    NvimTreeNormalNC = "NormalNC",
    NvimTreeEndOfBuffer = "EndOfBuffer",
  },
}

-- ── Internal helpers ──────────────────────────────────────────────────────────

---@internal
local function api()
  local ok, a = pcall(require, "nvim-tree.api")
  if not ok then return nil end
  return a
end

-- ── Interface ─────────────────────────────────────────────────────────────────

---@return boolean
function M.is_available()
  return pcall(require, "nvim-tree")
end

---@return boolean, integer? bufnr
function M.is_open()
  local a = api()
  if not a then return false, nil end
  local ok, view = pcall(require, "nvim-tree.view")
  if not ok or not view then return false, nil end
  if not view.is_visible() then return false, nil end
  local ok2, bufnr = pcall(function()
    return view.get_bufnr()
  end)
  if ok2 and bufnr and vim.api.nvim_buf_is_valid(bufnr) then return true, bufnr end
  return false, nil
end

---@return integer? bufnr
function M.get_bufnr()
  local _, bufnr = M.is_open()
  return bufnr
end

---@return integer? winid
function M.get_winid()
  local a = api()
  if not a then return nil end
  local ok, winid = pcall(function()
    return a.tree.winid()
  end)
  if ok and winid and vim.api.nvim_win_is_valid(winid) then return winid end
  return nil
end

---Which side nvim-tree's sidebar is configured for, so features can place new
---windows clear of it (util.window.open_editor_window). nvim-tree exposes this
---only as an internal (`nvim-tree.view`'s `View.side`, moved around across
---versions), so this is best-effort: anything unexpected returns nil and the
---caller falls back to reading the tree window's own column.
---@return FiletreeTreePosition?
function M.get_position()
  local ok, view = pcall(require, "nvim-tree.view")
  if not ok or type(view) ~= "table" then return nil end
  local side = (type(view.View) == "table" and view.View.side) or view.side
  if side == "left" or side == "right" then return side end
  return nil
end

---@param path string
---@return boolean
function M.set_root(path)
  local a = api()
  if not a then return false end
  local ok = pcall(a.tree.change_root, path)
  return ok
end

---@return string root_path
function M.get_root_path()
  -- The actual configured tree root, not "parent of whatever node the cursor
  -- happens to be on" (an earlier version used get_node_under_cursor() for
  -- this, which is a different — and largely meaningless — concept: it drifts
  -- with cursor movement instead of reflecting nvim-tree's real root, breaking
  -- any caller that uses get_root_path() to decide whether a file is "under
  -- the current root", e.g. auto_reveal's re-root guard).
  local ok, core = pcall(require, "nvim-tree.core")
  if ok and core.get_cwd then
    local root = core.get_cwd()
    if root and root ~= "" then return root end
  end
  return vim.fn.getcwd()
end

-- ── Line → node ───────────────────────────────────────────────────────────────

---@internal
---Depth of a node, counted through its parent chain.
---
---nvim-tree's nodes carry no depth/level field of their own (see
---`node/init.lua`'s class definition), so the previous `node.level or 0` was
---always 0 — a contract field reporting a constant lie. The chain is short and
---this is only walked for lines a caller actually asks about.
---@param node table
---@return integer
local function depth_of(node)
  local depth, cur = 0, node.parent
  while cur do
    depth = depth + 1
    cur = cur.parent
  end
  return depth
end

---Convert one nvim-tree node into the adapter contract's node shape.
---
---Every field comes off the node table, so this never touches the filesystem —
---worth stating, because the neo-tree side had to be fixed for doing exactly
---that (a stat per node per render, via a path helper that computes an
---is-directory flag its caller discards).
---
---Directory-ness is `node.nodes ~= nil`, not `node.type == "directory"`:
---nvim-tree's `type` is `"file"|"directory"|"link"`, and a symlink pointing at
---a directory is a `DirectoryLinkNode` with `type == "link"`. Testing the type
---string called every such symlink a file.
---@internal
---@param node table?
---@param line_number integer
---@return FiletreeNode?
local function to_filetree_node(node, line_number)
  if not node then return nil end
  local path = node.absolute_path
  if type(path) ~= "string" or path == "" then return nil end
  local is_dir = node.nodes ~= nil
  return {
    id = path,
    name = node.name or vim.fn.fnamemodify(path, ":t"),
    path = path,
    type = is_dir and "directory" or "file",
    depth = depth_of(node),
    line_number = line_number,
    is_expanded = is_dir and (node.open or false) or nil,
  }
end

---@internal
---Fallback line→node walk, for an nvim-tree without `Explorer:get_nodes_by_line`
---and without the older `utils.get_nodes_by_line`. Mirrors what those do.
---
---`group_next` is the part that is easy to get wrong: with `renderer.group_empty`
---on, a chain of single-child directories (`a/b/c`) renders as ONE line, and
---nvim-tree gives that line to the LAST node of the chain. Assigning a line to
---each node of the chain instead shifts everything below it by one per chain.
---@param nodes table[]
---@param line integer  1-based line the first node is drawn on
---@return table<integer, table>
local function walk_lines(nodes, line)
  local by_line = {}
  local function iter(list)
    for _, node in ipairs(list or {}) do
      if node.group_next then
        iter({ node.group_next }) -- the chain shares one line; the tail owns it
      else
        by_line[line] = node
        line = line + 1
        if node.open and node.nodes and #node.nodes > 0 then iter(node.nodes) end
      end
    end
  end
  iter(nodes)
  return by_line
end

-- The four features that call `get_node_at_line` each walk EVERY line of the
-- tree buffer per render, so rebuilding the map per lookup would make each
-- render quadratic in the rendered line count -- and there are four of them.
-- Cached on the buffer's changedtick, the same invalidation the neo-tree
-- adapter's line_map() uses: nvim-tree bumps it whenever what it drew changes
-- (expand/collapse/refresh/live-filter), which is exactly when the map is stale.
---@type table<integer, table>?
local _lines = nil
local _lines_buf = -1
local _lines_tick = -1

---@internal
---Build (or reuse) the line→node map for the currently rendered tree.
---@param bufnr integer
---@return table<integer, table>?
local function lines_map(bufnr)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if _lines and _lines_buf == bufnr and _lines_tick == tick then return _lines end

  local ok, map = pcall(function()
    local core = require("nvim-tree.core")
    local explorer = core.get_explorer()
    if not explorer then return nil end

    -- How many lines nvim-tree draws BEFORE the first node: the root-folder
    -- label and the live-filter prompt are both optional and both shift every
    -- node down by one. nvim-tree computes that offset itself -- reproducing
    -- the conditions here would mean re-deriving two of its display options
    -- and getting them wrong whenever it gains a third.
    local start = 1
    if type(core.get_nodes_starting_line) == "function" then
      local n = core.get_nodes_starting_line()
      if type(n) == "number" and n >= 1 then start = n end
    end

    -- nvim-tree's own mapping -- it is what `Explorer:get_node_at_cursor`
    -- resolves the cursor through, so this stays exactly as correct as
    -- nvim-tree's own cursor handling. The method moved off `utils` onto the
    -- Explorer class, so both spellings are tried before the local walk.
    local result
    if type(explorer.get_nodes_by_line) == "function" then
      result = explorer:get_nodes_by_line(start)
    else
      local ok_utils, utils = pcall(require, "nvim-tree.utils")
      if ok_utils and type(utils.get_nodes_by_line) == "function" then
        result = utils.get_nodes_by_line(explorer.nodes, start)
      else
        result = walk_lines(explorer.nodes, start)
      end
    end
    if type(result) ~= "table" then return nil end

    -- The root-folder label, when shown, is line 1 and is absent from that map
    -- -- nvim-tree's own cursor handler special-cases it back to the explorer,
    -- which IS a node (RootNode: DirectoryNode). Decorating the root the same
    -- way neo-tree does is the consistent behaviour; leaving it nil would make
    -- "the tree's own root" the one undecoratable line on one backend only.
    --
    -- `start > 1` alone is NOT "the root label is on line 1": `start` (from
    -- `get_nodes_starting_line` above) is bumped by TWO independent, additive
    -- reasons -- the root label being shown, and the live filter/search prompt
    -- being active -- so `root_folder_label = false` plus an active live
    -- filter also produces `start == 2`, indistinguishable from "label shown,
    -- no filter" by that number alone. In that state line 1 is really
    -- nvim-tree's own "[FILTER]: /query/" prompt, not a node, and stamping the
    -- root onto it made every decorating feature attach the root's data to
    -- that prompt line instead. Ask the exact question `get_nodes_starting_line`
    -- itself asks -- `view.is_root_folder_visible`, not a number derived from
    -- it -- so this stays correct regardless of why `start` moved.
    local ok_view, view = pcall(require, "nvim-tree.view")
    local root_shown = ok_view and view.is_root_folder_visible(explorer.absolute_path)
    if result[1] == nil and root_shown and type(explorer.absolute_path) == "string" then
      result[1] = explorer
    end
    return result
  end)

  if not ok or type(map) ~= "table" then
    -- Debug rather than warn: this is called once per rendered line, so a
    -- visible notification would arrive hundreds of times for one bad render.
    if not ok then notify.debug("lines_map failed: " .. tostring(map)) end
    _lines, _lines_buf, _lines_tick = nil, -1, -1
    return nil
  end
  _lines, _lines_buf, _lines_tick = map, bufnr, tick
  return map
end

---Node rendered on one line of the tree buffer.
---
---`linenr` is **0-based** — the contract states it, and it is what every caller
---has: all five (git_status, lsp_diagnostics, size_info, copy_move's clipboard
---marker, filter's dim fallback) walk `0 .. line_count - 1` to place extmarks,
---which are 0-based too. nvim-tree numbers its lines 1-based, hence the `+ 1`
---here and nowhere else.
---
---A line that renders no node — the live-filter prompt — is absent from the map
---and resolves to nil, rather than shifting every node below it by one.
---Every node the tree is currently showing, in render order.
---
---`line_number` comes from the same map `get_node_at_line` uses, not from
---counting nodes. Counting was wrong three ways on this backend: it ignored
---the root-folder label (so EVERY line was off by one under the default
---config), it gave a grouped `renderer.group_empty` chain one line per node
---when the chain renders as one line, and it advanced only for nodes the
---`filter` argument kept, so asking for `"files"` renumbered them 1..n. Marks
---and live_search place extmarks with these numbers, and `get_node_line` feeds
---reveal/`scroll_to_line`, so each of those put its decoration on a neighbour.
---@param filter? FiletreeFilterMode
---@return FiletreeNode[]
function M.get_visible_nodes(filter)
  local _, bufnr = M.is_open()
  local map = bufnr and lines_map(bufnr) or nil
  if not map then return {} end -- nothing is rendered, so nothing is visible

  local out = {}
  for line, raw in pairs(map) do
    local node = to_filetree_node(raw, line)
    if node then
      local include = filter == nil
        or filter == "all"
        or (filter == "files" and node.type == "file")
        or (filter == "folders" and node.type == "directory")
      if include then out[#out + 1] = node end
    end
  end
  table.sort(out, function(a, b)
    return a.line_number < b.line_number
  end)
  return out
end

-- nvim-tree's node.absolute_path is native-separator (backslash on Windows),
-- while callers (cwd_sync/auto_reveal/current_hl) query with paths sourced from
-- vim.api.nvim_buf_get_name()/expand("%:p"), which return forward-slash paths on
-- this platform's Neovim build. Normalize both sides before comparing, or the
-- lookup silently misses on Windows. See adapter/neotree.lua's key_of() for the
-- same fix in that adapter.
---The line `path` is rendered on — the exact inverse of `get_node_at_line`,
---and read through the same map, so revealing a file cannot land the cursor on
---its neighbour.
---@param node_path string
---@return integer? line_number
function M.get_node_line(node_path)
  local _, bufnr = M.is_open()
  if not bufnr then return nil end
  local map = lines_map(bufnr)
  if not map then return nil end

  local query = pathutil.slashify(node_path)
  for line, raw in pairs(map) do
    local p = raw and raw.absolute_path
    if type(p) == "string" and pathutil.slashify(p) == query then return line end
  end
  return nil
end

---@return FiletreeNode?
function M.get_current_node()
  local a = api()
  if not a then return nil end
  local ok, node = pcall(function()
    return a.tree.get_node_under_cursor()
  end)
  if not ok then return nil end
  return to_filetree_node(node, vim.fn.line("."))
end

---@param bufnr integer
---@param linenr integer  0-based buffer line
---@return FiletreeNode?
function M.get_node_at_line(bufnr, linenr)
  -- is_open() has already validated the buffer it reports, so there is no
  -- second nvim_buf_is_valid here.
  local _, tree_bufnr = M.is_open()
  if not tree_bufnr then
    -- The map holds nvim-tree's node objects by reference, i.e. the whole
    -- rendered graph. Nothing else drops it, so a closed tree would keep that
    -- alive for the rest of the session.
    _lines, _lines_buf, _lines_tick = nil, -1, -1
    return nil
  end
  if tree_bufnr ~= bufnr then return nil end

  local map = lines_map(bufnr)
  if not map then return nil end
  return to_filetree_node(map[linenr + 1], linenr + 1)
end

---@param node FiletreeNode
---@return boolean
function M.expand_node(node)
  local a = api()
  if not a then return false end
  if node.type ~= "directory" then return false end
  local ok = pcall(function()
    local lib = require("nvim-tree.lib")
    local nvim_node = lib.get_node_at_cursor()
    if nvim_node and nvim_node.absolute_path == node.path then lib.expand_or_collapse(nvim_node) end
  end)
  return ok
end

---@param node FiletreeNode
---@return boolean
function M.collapse_node(node)
  return M.expand_node(node) -- toggle-style; expand_node opens/closes
end

---@param path string
---@param mode? FiletreeOpenMode
---@return boolean
function M.open_file(path, mode)
  mode = mode or "edit"
  local cmd_map = {
    edit = "edit",
    split = "split",
    vsplit = "vsplit",
    tab = "tabnew",
  }
  local cmd = cmd_map[mode] or "edit"
  local ok = pcall(function()
    vim.cmd(cmd .. " " .. vim.fn.fnameescape(path))
  end)
  return ok
end

---@param path string
---@param _parent_levels? integer
---@return boolean
function M.open_reveal(path, _parent_levels)
  local a = api()
  if not a then return false end
  if not M.is_open() then
    local ok1 = pcall(function()
      a.tree.open()
    end)
    if not ok1 then return false end
  end
  local ok2 = pcall(function()
    -- Modern Opts form -- the legacy string form still works internally
    -- (nvim-tree wraps it into { buf = path } itself either way), but this
    -- is the form the current @param actually declares.
    a.tree.find_file({ buf = path })
  end)
  return ok2
end

---@return boolean
function M.open_cwd()
  local a = api()
  if not a then return false end
  local ok = pcall(function()
    a.tree.open({ path = vim.fn.getcwd() })
  end)
  return ok
end

---@return boolean
function M.close()
  local a = api()
  if not a then return false end
  local ok = pcall(function()
    a.tree.close()
  end)
  return ok
end

---@return boolean
function M.refresh()
  local a = api()
  if not a then return false end
  local ok = pcall(function()
    a.tree.reload()
  end)
  return ok
end

---@param line integer
---@return boolean
function M.scroll_to_line(line)
  local winid = M.get_winid()
  if not winid then return false end
  local ok = pcall(vim.api.nvim_win_set_cursor, winid, { math.max(1, line), 0 })
  return ok
end

-- Highlights via extmarks (agnostic to nvim-tree internals)
---@type table<string, integer>
local _hl_marks = {}
local _ns = nil

---@internal
local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_current_hl_nvimtree") end
  return _ns
end

---@param path string
---@param hl_group string
---@return boolean
function M.highlight_node(path, hl_group)
  local line = M.get_node_line(path)
  if not line then return false end
  local _, bufnr = M.is_open()
  if not bufnr then return false end
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns(), line - 1, 0, {
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
  local _, bufnr = M.is_open()
  if not bufnr then return false end
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns(), id)
  _hl_marks[path] = nil
  return true
end

-- Self-register
registry.register(M)

return M
