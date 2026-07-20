---@module 'filetree.adapter.neotree'
---@brief Neo-tree adapter — implements the FiletreeAdapter interface for neo-tree.nvim.

local notify = require("filetree.util.notify").create("[filetree.adapter.neotree]")
local registry = require("filetree.adapter")

-- Shared neo-tree node helpers live in lib.nvim (a declared dependency). We still
-- pcall it so filetree degrades gracefully to a local fallback if lib.nvim is
-- absent, matching the adapter's defensive style everywhere else.
local _ok_libnode, libnode = pcall(require, "lib.nvim.neotree.node")
if not _ok_libnode then libnode = nil end

---@class FiletreeNeotreeAdapter : FiletreeAdapter
local M = {
  name = "neotree",
  -- UI capabilities consumed by adapter-agnostic features.
  filetypes = { "neo-tree" },
  hl_groups = {
    NeoTreeNormal      = "Normal",
    NeoTreeNormalNC    = "NormalNC",
    NeoTreeEndOfBuffer = "EndOfBuffer",
  },
}

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function get_manager()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then return nil end
  return manager
end

local function get_state()
  local manager = get_manager()
  if not manager then return nil end
  local ok, state = pcall(manager.get_state, "filesystem")
  if not ok then return nil end
  return state
end

local function get_commands()
  local ok, commands = pcall(require, "neo-tree.command")
  if not ok then return nil end
  return commands
end

---@type table<string, true>
local VALID_POSITIONS = { left = true, right = true, float = true, current = true }

---Position the tree is currently at (or was last shown at), so system-triggered
---actions (reveal, re-root) preserve it instead of snapping back to a hardcoded
---default. Neo-tree keeps one shared state per source, not per position, so this
---is the only source of truth for "where is/was the tree". Falls back to "left"
---when there is no prior state (e.g. first show of the session) or an unexpected value.
---@return FiletreeTreePosition
local function get_current_position()
  local state = get_state()
  local pos = state and state.current_position
  if type(pos) == "string" and VALID_POSITIONS[pos] then return pos end
  return "left"
end

---Resolve a neo-tree node's filesystem path robustly.
---Prefers the canonical `node.path`, falls back to the node id (which for the
---filesystem source is the path). Returns nil for nodes without a real path
---(message / loading / virtual nodes), so callers can skip them.
---@param node table?
---@return string? path
local function node_path(node)
  if not node then return nil end
  -- Prefer the shared lib.nvim helper when available.
  if libnode then
    local p = libnode.get_path(node)
    return p ~= "" and p or nil
  end
  -- Fallback: canonical node.path, then the node id.
  local p = node.path
  if (type(p) ~= "string" or p == "") and node.get_id then
    local ok, id = pcall(node.get_id, node)
    if ok then p = id end
  end
  if type(p) ~= "string" or p == "" then return nil end
  return p
end

---Determine whether a node is a directory (uses node.type, falls back to a
---filesystem check when the field is absent).
---@param node table
---@param path string
---@return boolean
local function node_is_dir(node, path)
  if node.type == "directory" then return true end
  if node.type == "file" then return false end
  return vim.fn.isdirectory(path) == 1
end

-- ── Interface ─────────────────────────────────────────────────────────────────

function M.is_available()
  local ok = pcall(require, "neo-tree")
  return ok
end

function M.is_open()
  local state = get_state()
  if not state then return false, nil end
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    local bufnr = vim.api.nvim_win_get_buf(state.winid)
    if vim.api.nvim_buf_is_valid(bufnr) then
      return true, bufnr
    end
  end
  return false, nil
end

function M.get_bufnr()
  local _, bufnr = M.is_open()
  return bufnr
end

function M.get_winid()
  local state = get_state()
  if not state then return nil end
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    return state.winid
  end
  return nil
end

function M.get_root_path()
  local state = get_state()
  return state and state.path or nil
end

function M.get_current_node()
  local state = get_state()
  if not state or not state.tree then return nil end
  local ok, node = pcall(function()
    return state.tree:get_node()
  end)
  if not ok or not node then return nil end

  local path = node_path(node)
  if not path then return nil end   -- skip message / virtual nodes without a path

  local is_dir = node_is_dir(node, path)
  local ntype  = is_dir and "directory" or "file"
  return {
    id          = (node.get_id and node:get_id()) or node.id or path,
    name        = node.name or vim.fn.fnamemodify(path, ":t"),
    path        = path,
    type        = ntype,
    depth       = (node.get_depth and node:get_depth()) or 0,
    line_number = vim.fn.line("."),
    is_expanded = is_dir and ((node.is_expanded and node:is_expanded()) or false) or nil,
  }
end

---Extract filesystem paths (and display names) from a list of neo-tree nodes.
---Nodes without a real path are skipped. Useful for batch operations over
---marked nodes.
---@param nodes table[]
---@return string[] paths, string[] names
function M.extract_paths(nodes)
  if libnode then
    return libnode.extract_paths(nodes)
  end
  local paths, names = {}, {}
  for _, node in ipairs(nodes or {}) do
    local p = node_path(node)
    if p then
      paths[#paths + 1] = p
      names[#names + 1] = node.name or vim.fn.fnamemodify(p, ":t")
    end
  end
  return paths, names
end

-- Safety cap: the walk already only descends into *expanded* nodes (so it is
-- bounded by the rendered line count, not the filesystem), but a single directory
-- expanded with tens of thousands of entries could still be pathological. Stop
-- collecting past this many nodes — far more than any picker/marks use needs.
local MAX_VISIBLE = 5000

function M.get_visible_nodes(filter)
  local state = get_state()
  if not state or not state.tree then return {} end

  local nodes = {}
  local line_nr = 1
  local capped = false

  local function collect(node)
    if not node or #nodes >= MAX_VISIBLE then
      capped = capped or #nodes >= MAX_VISIBLE
      return
    end
    local depth = (node.get_depth and node:get_depth()) or 0
    if depth > 0 then
      local ntype = node.type == "directory" and "directory" or "file"
      local include = filter == nil or filter == "all"
        or (filter == "files"   and ntype == "file")
        or (filter == "folders" and ntype == "directory")

      if include then
        local id = (node.get_id and node:get_id()) or node.id or ""
        nodes[#nodes + 1] = {
          id          = id,
          name        = node.name or "",
          path        = id,
          type        = ntype,
          depth       = depth,
          line_number = line_nr,
          is_expanded = ntype == "directory" and ((node.is_expanded and node:is_expanded()) or false) or nil,
        }
      end
      line_nr = line_nr + 1
    end

    local expanded = node.is_expanded and node:is_expanded()
    local has_children = node.has_children and node:has_children()
    if expanded and has_children then
      local child_ids = (node.get_child_ids and node:get_child_ids()) or {}
      for _, cid in ipairs(child_ids) do
        local child = state.tree.get_node and state.tree:get_node(cid)
        if child then collect(child) end
      end
    end
  end

  local roots = state.tree.get_nodes and state.tree:get_nodes()
  if roots then
    for _, root in ipairs(roots) do collect(root) end
  end
  if capped then
    notify.debug("get_visible_nodes: capped at " .. MAX_VISIBLE .. " nodes")
  end
  return nodes
end

-- Cache the path→line map so repeated lookups (e.g. current_hl highlights the
-- current file AND its parent per event, and cwd_sync/auto_reveal reveal on
-- every buffer switch) don't each rebuild the full visible-node list. Keyed on
-- the tree buffer's changedtick: neo-tree bumps it whenever the rendered tree
-- changes (expand/collapse/refresh), which is exactly when the line map goes
-- stale — so a cursor move or file open that leaves the tree untouched is a hit.
---Normalize a path to forward slashes for use as a line-map key. Neo-tree's own
---node.path is native-separator (backslash on Windows), while callers querying
---the map (cwd_sync/auto_reveal/current_hl) source their path from
---`vim.api.nvim_buf_get_name()` / `vim.fn.expand("%:p")`, which return
---forward-slash paths on this platform's Neovim build. Without normalizing both
---sides to the same form, every lookup silently misses on Windows — the map
---builds fine but `get_node_line()` never finds an entry, forcing the
---(otherwise avoidable) slow reveal path on every call.
---@param p string
---@return string
local function key_of(p)
  return (p:gsub("\\", "/"))
end

---@type table<string, integer>?
local _line_map = nil
local _line_map_buf = -1
local _line_map_tick = -1

---Build (or reuse) the path→line map for the currently rendered tree.
---@return table<string, integer>?
local function line_map()
  local _, bufnr = M.is_open()
  if not bufnr then
    _line_map, _line_map_buf, _line_map_tick = nil, -1, -1
    return nil
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if _line_map and _line_map_buf == bufnr and _line_map_tick == tick then
    return _line_map
  end

  local map = {}
  for _, node in ipairs(M.get_visible_nodes()) do
    -- First occurrence wins (a path is rendered once); keep the earliest line.
    if node.path then
      local key = key_of(node.path)
      if map[key] == nil then
        map[key] = node.line_number
      end
    end
  end
  _line_map, _line_map_buf, _line_map_tick = map, bufnr, tick
  return map
end

function M.get_node_line(path)
  local map = line_map()
  return map and map[key_of(path)] or nil
end

function M.expand_node(node)
  local state = get_state()
  if not state or not state.tree then return false end
  local ok2, tree_node = pcall(function()
    return state.tree:get_node(node.id)
  end)
  if not ok2 or not tree_node then return false end
  if tree_node.is_expanded and not tree_node:is_expanded() and tree_node.expand then
    tree_node:expand()
    local ok3, renderer = pcall(require, "neo-tree.ui.renderer")
    if ok3 and renderer and renderer.redraw then
      pcall(renderer.redraw, state)
    end
  end
  return true
end

function M.collapse_node(node)
  local state = get_state()
  if not state or not state.tree then return false end
  local ok2, tree_node = pcall(function()
    return state.tree:get_node(node.id)
  end)
  if not ok2 or not tree_node then return false end
  if tree_node.is_expanded and tree_node:is_expanded() and tree_node.collapse then
    tree_node:collapse()
    local ok3, renderer = pcall(require, "neo-tree.ui.renderer")
    if ok3 and renderer and renderer.redraw then
      pcall(renderer.redraw, state)
    end
  end
  return true
end

function M.open_file(path, mode)
  mode = mode or "edit"
  local cmd_map = {
    edit    = "edit",
    split   = "split",
    vsplit  = "vsplit",
    tab     = "tabnew",
    preview = "split",
  }
  local cmd = cmd_map[mode]
  if not cmd then return false end
  local ok = pcall(vim.cmd, cmd .. " " .. vim.fn.fnameescape(path))
  return ok
end

function M.set_root(path)
  local commands = get_commands()
  if not commands then return false end
  local ok = pcall(commands.execute, {
    action   = "show",
    source   = "filesystem",
    position = get_current_position(),
    dir      = path,
  })
  return ok
end

function M.open_reveal(path, parent_levels, root_dir)
  local commands = get_commands()
  if not commands then return false end
  -- Explicit root_dir (e.g. the project root resolved by cwd_sync) wins: the tree
  -- is rooted there. Otherwise derive the root from the file by ascending
  -- `parent_levels` (legacy behaviour).
  local target = root_dir
  if not target or target == "" then
    target = path
    for _ = 1, (parent_levels or 0) do   -- fixed: was 0,n (ran n+1 times); now 1,n (runs n times)
      target = vim.fn.fnamemodify(target, ":h")
    end
  end
  -- `dir` is the tree root neo-tree navigates/tcd's to, so it MUST be a
  -- directory. With parent_levels = 0 (the default) and no root_dir, `target` is
  -- still the file itself — passing that made neo-tree run `tcd <file>` →
  -- E344/ENOTDIR. Ascend to the containing directory whenever target is not one.
  if vim.fn.isdirectory(target) ~= 1 then
    target = vim.fn.fnamemodify(target, ":h")
  end
  local ok = pcall(commands.execute, {
    action      = "show",
    source      = "filesystem",
    position    = get_current_position(),
    dir         = target,
    reveal_file = path,
  })
  return ok
end

function M.open_cwd()
  local commands = get_commands()
  if not commands then return false end
  local ok = pcall(commands.execute, {
    action   = "show",
    source   = "filesystem",
    position = get_current_position(),
  })
  return ok
end

---Toggle the tree at a given position, optionally revealing a file / setting root.
---@param position FiletreeTreePosition
---@param opts? FiletreeToggleOpts
---@return boolean
function M.toggle_at(position, opts)
  opts = opts or {}
  local commands = get_commands()
  if not commands then return false end
  return (pcall(commands.execute, {
    action      = "focus",
    source      = "filesystem",
    position    = position,
    toggle      = true,
    reveal      = opts.reveal == true,
    reveal_file = opts.reveal and opts.file or nil,
    dir         = opts.dir,
  }))
end

function M.close()
  local commands = get_commands()
  if not commands then return false end
  local ok = pcall(commands.execute, { action = "close", source = "filesystem" })
  return ok
end

function M.refresh()
  local commands = get_commands()
  if not commands then return false end
  local ok = pcall(commands.execute, { action = "refresh", source = "filesystem" })
  return ok
end

---Re-render the CURRENT tree from its existing state, without rescanning the
---filesystem (unlike refresh). Cheap enough to run on buffer open/close so
---neo-tree's `highlight_opened_files` decoration re-evaluates and stays in sync
---with which files are actually open. Returns false when the tree isn't open.
---@return boolean
function M.redraw()
  local state = get_state()
  if not state or not state.tree then return false end
  local ok_r, renderer = pcall(require, "neo-tree.ui.renderer")
  if not ok_r or type(renderer.redraw) ~= "function" then return false end
  return (pcall(renderer.redraw, state))
end

function M.scroll_to_line(line)
  local winid = M.get_winid()
  if not winid then return false end
  local l = math.max(1, math.floor(line))
  local ok = pcall(vim.api.nvim_win_set_cursor, winid, { l, 0 })
  return ok
end

-- Highlights are applied as extmarks on the tree buffer.
---@type table<string, integer>   path → extmark id
local _hl_marks = {}
local _ns = nil

local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_current_hl_neotree") end
  return _ns
end

function M.highlight_node(path, hl_group)
  local line = M.get_node_line(path)
  if not line then return false end
  local _, bufnr = M.is_open()
  if not bufnr then return false end
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns(), line - 1, 0, {
    line_hl_group = hl_group,
    priority      = 150,
  })
  if ok then _hl_marks[path] = id end
  return ok
end

function M.unhighlight_node(path)
  local id = _hl_marks[path]
  if not id then return true end
  local _, bufnr = M.is_open()
  if not bufnr then return false end
  local ok = pcall(vim.api.nvim_buf_del_extmark, bufnr, ns(), id)
  _hl_marks[path] = nil
  return ok
end

-- Sign-column markers (a separate namespace + mark table from the line
-- highlights above, so a node can carry both a line highlight AND a sign, and
-- either can be cleared independently).
---@type table<string, integer>   path → sign extmark id
local _sign_marks = {}
local _sign_ns = nil
local function sign_ns()
  if not _sign_ns then _sign_ns = vim.api.nvim_create_namespace("filetree_sign_neotree") end
  return _sign_ns
end

function M.sign_node(path, text, hl_group)
  local line = M.get_node_line(path)
  if not line then return false end
  local _, bufnr = M.is_open()
  if not bufnr then return false end
  M.unsign_node(path)
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, sign_ns(), line - 1, 0, {
    sign_text    = text,
    sign_hl_group = hl_group,
    priority     = 160,
  })
  if ok then _sign_marks[path] = id end
  return ok
end

function M.unsign_node(path)
  local id = _sign_marks[path]
  if not id then return true end
  local _, bufnr = M.is_open()
  if not bufnr then return false end
  local ok = pcall(vim.api.nvim_buf_del_extmark, bufnr, sign_ns(), id)
  _sign_marks[path] = nil
  return ok
end

-- ── Reveal-prompt guard ───────────────────────────────────────────────────────

---@type boolean
local _reveal_guard_installed = false

---Ensure `require("neo-tree.command").execute` never triggers neo-tree's own
---"File not in cwd. Change cwd to <dir>?" confirm prompt (see neo-tree's
---lua/neo-tree/command/init.lua, handle_reveal()).
---
---That prompt fires whenever a reveal is requested — explicitly via
---`reveal = true`, or IMPLICITLY whenever `filesystem.follow_current_file.enabled`
---is on and `reveal` was left unset — without an explicit `dir` and without
---`reveal_force_cwd`, and the file to reveal isn't under the tree's current
---(possibly stale) root. `reveal_force_cwd` is a per-call flag with no
---persistent `filesystem.follow_current_file.*` config equivalent, so setting
---it on every one of filetree.nvim's own calls isn't enough — ANY code that
---calls neo-tree's command API directly (a user's own custom keymaps, a
---plugin, neo-tree's own internals) can just as easily trigger it, and missing
---even one call site (this is exactly how the original bug report happened —
---several sites were correctly guarded, one was overlooked) brings the prompt
---back. Since every caller shares the same `neo-tree.command` module table,
---wrapping `execute` once here protects all of them, current and future,
---without needing to audit every call site by hand.
---
---Only touches calls that would otherwise be at risk: an explicit
---`reveal = false`, or a call that already sets `dir` or `reveal_force_cwd`
---itself, is left completely alone — this never changes behavior for a call
---that already knows what it wants.
function M.install_reveal_guard()
  if _reveal_guard_installed then return end
  local ok, commands = pcall(require, "neo-tree.command")
  if not ok or type(commands.execute) ~= "function" then return end

  local original_execute = commands.execute
  commands.execute = function(args, ...)
    if type(args) == "table"
      and args.dir == nil
      and args.reveal_force_cwd == nil
      and args.reveal ~= false then
      args.reveal_force_cwd = true
    end
    return original_execute(args, ...)
  end

  _reveal_guard_installed = true
end

-- Self-register
registry.register(M)

return M
