---@module 'filetree.adapter.neotree'
--- Neo-tree adapter — implements the FiletreeAdapter interface for neo-tree.nvim.

local notify = require("filetree.util.notify").create("[filetree.adapter.neotree]")
local registry = require("filetree.adapter")

-- Shared neo-tree node helpers live in lib.nvim (a hard dependency).
local libnode = require("lib.nvim.neotree.node")

---@class FiletreeNeotreeAdapter : FiletreeAdapter
local M = {
  name = "neotree",
  -- UI capabilities consumed by adapter-agnostic features.
  filetypes = { "neo-tree" },
  hl_groups = {
    NeoTreeNormal = "Normal",
    NeoTreeNormalNC = "NormalNC",
    NeoTreeEndOfBuffer = "EndOfBuffer",
  },
}

-- ── Internal helpers ──────────────────────────────────────────────────────────

---@internal
local function get_manager()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then return nil end
  return manager
end

---@internal
local function get_state()
  local manager = get_manager()
  if not manager then return nil end
  local ok, state = pcall(manager.get_state, "filesystem")
  if not ok then return nil end
  return state
end

---@internal
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
---@internal
---@return FiletreeTreePosition
local function get_current_position()
  local state = get_state()
  local pos = state and state.current_position
  if type(pos) == "string" and VALID_POSITIONS[pos] then
    -- VALID_POSITIONS narrows out "bottom" (added upstream, not supported
    -- here) at runtime; the table lookup does not narrow the type itself.
    ---@cast pos FiletreeTreePosition
    return pos
  end
  return "left"
end

---Where the tree is (or was last) shown — see `get_current_position`. Public so
---features can place new windows clear of the sidebar's side instead of relying
---on 'splitright' (util.window.open_editor_window).
---@return FiletreeTreePosition
function M.get_position()
  return get_current_position()
end

---Resolve a neo-tree node's filesystem path robustly.
---Prefers the canonical `node.path`, falls back to the node id (which for the
---filesystem source is the path). Returns nil for nodes without a real path
---(message / loading / virtual nodes), so callers can skip them.
---
---`lib.nvim`'s `get_path` is the shared helper for this, and it returns
---`path, is_dir` — computing that second value with a `vim.fn.isdirectory()`,
---i.e. a filesystem stat, which this function then throws away. Measured at
---~19us per call on Windows, against ~0us for reading `node.path` directly.
---That was invisible while this ran once per cursor move; `get_node_at_line`
---calls it once per rendered line per decorating feature, where it is ~100ms
---per render on a 1000-line tree.
---
---So the plain field goes first and the helper stays as the fallback. Nothing
---is lost by the order: `get_path`'s own path resolution is `node.path`, then
---`node:get_id()` — exactly the two steps below it.
---@internal
---@param node table?
---@return string? path
local function node_path(node)
  if not node then return nil end

  local p = node.path
  if (type(p) ~= "string" or p == "") and node.get_id then
    local ok, id = pcall(node.get_id, node)
    if ok then p = id end
  end
  if type(p) == "string" and p ~= "" then return p end

  local lp = libnode.get_path(node)
  return lp ~= "" and lp or nil
end

---Determine whether a node is a directory (uses node.type, falls back to a
---filesystem check only when the field is absent).
---
---neo-tree already resolves a symlink's real type when it can: a `"link"`
---node only keeps that type when its target could not be `uv.fs_stat`'d at
---all -- i.e. a dangling symlink, which by definition is not a directory. The
---same holds for `"unknown"` (its own `uv.fs_lstat` already failed). Both
---used to fall through to the `vim.fn.isdirectory()` stat below, which was
---always going to fail too, on a real filesystem check per rendered line for
---every dangling link in the tree. Any *other* non-nil type is equally
---conclusive -- only a genuinely absent field means neo-tree told us nothing.
---@internal
---@param node table
---@param path string
---@return boolean
local function node_is_dir(node, path)
  if node.type == "directory" then return true end
  if node.type ~= nil then return false end
  return vim.fn.isdirectory(path) == 1
end

---Convert one neo-tree (nui) node into the adapter contract's node shape.
---
---Shared by `get_current_node` and `get_node_at_line`: the two differ only in
---how they FIND the node, and a second hand-rolled copy of this mapping is how
---the two drift apart (a `depth` of 0 here and `node.level` there, say) for no
---reason the caller can see.
---
---`line_number` is the contract's 1-based line, and is the caller's to supply
---— it is the one field that does not come from the node itself.
---
---Neo-tree's `type = "message"` nodes — the `(N hidden items)` /
---`(empty folder)` lines — are not nodes in the contract's sense and come back
---nil. They carry a synthetic id (`…/.git_hidden_message`) that `node_path`
---happily reports as a path, which then makes every caller treat a notice as a
---file: a stat of something that does not exist per render, and, on
---`get_current_node`, a `d`/rename aimed at it.
---
---`is_link`/`link_to` cost nothing extra here: neo-tree's own scan
---(`file-items.lua`) already calls `uv.fs_readlink()` for every symlink it
---finds and stores the result on the item as `is_link`/`link_to`, which
---`ui/renderer.lua` then copies onto the nui node unchanged. Reading those two
---fields is a plain table access, same cost class as `node.name` above — not a
---filesystem call, so it does not reintroduce the per-node `stat` this module
---was fixed to avoid (see `node_is_dir`'s comment and
---`docs/FEATURES/BACKENDS.md`'s "Line-resolved decorations").
---
---`link_broken`: a symlink's `node.type` stays the literal `"link"` only when
---neo-tree's own `uv.fs_stat()` of the target failed (see `node_is_dir`'s
---comment above) — i.e. exactly the dangling-link case. Any other type on a
---link node means neo-tree resolved it fine.
---@internal
---@param node table?
---@param line_number integer
---@return FiletreeNode?
local function to_filetree_node(node, line_number)
  if not node or node.type == "message" then return nil end
  local path = node_path(node)
  if not path then return nil end -- other virtual nodes without a real path

  local is_dir = node_is_dir(node, path)
  local is_link = node.is_link == true
  return {
    id = (node.get_id and node:get_id()) or node.id or path,
    name = node.name or vim.fn.fnamemodify(path, ":t"),
    path = path,
    type = is_dir and "directory" or "file",
    depth = (node.get_depth and node:get_depth()) or 0,
    line_number = line_number,
    is_expanded = is_dir and ((node.is_expanded and node:is_expanded()) or false) or nil,
    is_link = is_link or nil,
    link_to = (is_link and type(node.link_to) == "string" and node.link_to) or nil,
    link_broken = (is_link and node.type == "link") or nil,
  }
end

-- ── Interface ─────────────────────────────────────────────────────────────────

---@return boolean
function M.is_available()
  local ok = pcall(require, "neo-tree")
  return ok
end

---@return boolean, integer? bufnr
function M.is_open()
  local state = get_state()
  if not state then return false, nil end
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    local bufnr = vim.api.nvim_win_get_buf(state.winid)
    if vim.api.nvim_buf_is_valid(bufnr) then return true, bufnr end
  end
  return false, nil
end

---@return integer? bufnr
function M.get_bufnr()
  local _, bufnr = M.is_open()
  return bufnr
end

---@return integer? winid
function M.get_winid()
  local state = get_state()
  if not state then return nil end
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then return state.winid end
  return nil
end

---@return string? root_path
function M.get_root_path()
  local state = get_state()
  return state and state.path or nil
end

---@return FiletreeNode?
function M.get_current_node()
  local state = get_state()
  if not state or not state.tree then return nil end
  local ok, node = pcall(function()
    return state.tree:get_node()
  end)
  if not ok then return nil end
  return to_filetree_node(node, vim.fn.line("."))
end

---Node rendered on one line of the tree buffer.
---
---`linenr` is **0-based** — the contract states it, and it is what every
---caller has: all five (git_status, lsp_diagnostics, size_info, copy_move's
---clipboard marker, filter's dim fallback) walk `0 .. line_count - 1` to place
---extmarks, which are 0-based too. Neo-tree renders through a nui tree, whose
---line numbers are 1-based buffer lines, hence the `+ 1` here and nowhere else.
---
---The lookup is nui's own line→node mapping rather than a reconstruction from
---`get_visible_nodes`: nui knows which lines it actually drew, so a line it
---drew for something that is not a node resolves to nil instead of silently
---shifting every node below it by one. It also memoizes that mapping after the
---second lookup, which is what keeps the callers' per-line loop linear rather
---than quadratic. Neo-tree's root IS a node and resolves like any other; its
---`(N hidden items)`/`(empty folder)` notices are the lines that come back
---nil.
---
---`bufnr` is checked against the live tree buffer instead of being ignored: a
---caller holding a stale bufnr (its tree closed and reopened between render
---and callback) would otherwise get nodes decorated onto the wrong buffer.
---The check reads `state.winid` directly rather than calling `M.is_open()`,
---which would resolve the source state a second time for the same answer —
---cheap once, not free once per rendered line per feature.
---@param bufnr integer
---@param linenr integer  0-based buffer line
---@return FiletreeNode?
function M.get_node_at_line(bufnr, linenr)
  local state = get_state()
  if not state or not state.tree then return nil end
  if not state.winid or not vim.api.nvim_win_is_valid(state.winid) then return nil end
  if vim.api.nvim_win_get_buf(state.winid) ~= bufnr then return nil end

  local ok, node = pcall(function()
    return state.tree:get_node(linenr + 1)
  end)
  if not ok then return nil end
  return to_filetree_node(node, linenr + 1)
end

---Extract filesystem paths (and display names) from a list of neo-tree nodes.
---Nodes without a real path are skipped. Useful for batch operations over
---marked nodes.
---@param nodes table[]
---@return string[] paths, string[] names
function M.extract_paths(nodes)
  return libnode.extract_paths(nodes)
end

-- Safety cap: the walk already only descends into *expanded* nodes (so it is
-- bounded by the rendered line count, not the filesystem), but a single directory
-- expanded with tens of thousands of entries could still be pathological. Stop
-- collecting past this many nodes — far more than any picker/marks use needs.
---@return integer
local function max_visible()
  local ok, ft = pcall(require, "filetree.config")
  if not ok or not ft.get then return 5000 end
  local n = ft.get().max_visible_nodes
  return (type(n) == "number" and n > 0) and n or 5000
end

---@param filter? FiletreeFilterMode
---@return FiletreeNode[]
function M.get_visible_nodes(filter)
  local state = get_state()
  if not state or not state.tree then return {} end

  local nodes = {}
  local line_nr = 1
  local capped = false
  local cap = max_visible()

  ---@internal
  local function collect(node)
    if not node or #nodes >= cap then
      capped = capped or #nodes >= cap
      return
    end
    local depth = (node.get_depth and node:get_depth()) or 0
    if depth > 0 then
      local ntype = node.type == "directory" and "directory" or "file"
      local include = filter == nil
        or filter == "all"
        or (filter == "files" and ntype == "file")
        or (filter == "folders" and ntype == "directory")

      if include then
        local id = (node.get_id and node:get_id()) or node.id or ""
        nodes[#nodes + 1] = {
          id = id,
          name = node.name or "",
          path = id,
          type = ntype,
          depth = depth,
          line_number = line_nr,
          is_expanded = ntype == "directory"
              and ((node.is_expanded and node:is_expanded()) or false)
            or nil,
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
    for _, root in ipairs(roots) do
      collect(root)
    end
  end
  if capped then notify.debug("get_visible_nodes: capped at " .. cap .. " nodes") end
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
---@internal
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
---@internal
---@return table<string, integer>?
local function line_map()
  local _, bufnr = M.is_open()
  if not bufnr then
    _line_map, _line_map_buf, _line_map_tick = nil, -1, -1
    return nil
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if _line_map and _line_map_buf == bufnr and _line_map_tick == tick then return _line_map end

  local map = {}
  for _, node in ipairs(M.get_visible_nodes()) do
    -- First occurrence wins (a path is rendered once); keep the earliest line.
    if node.path then
      local key = key_of(node.path)
      if map[key] == nil then map[key] = node.line_number end
    end
  end
  _line_map, _line_map_buf, _line_map_tick = map, bufnr, tick
  return map
end

---@param path string
---@return integer? line_number
function M.get_node_line(path)
  local map = line_map()
  return map and map[key_of(path)] or nil
end

---@param node FiletreeNode
---@return boolean
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
    if ok3 and renderer and renderer.redraw then pcall(renderer.redraw, state) end
  end
  return true
end

---@internal
---Nearest ancestor of `tree_node` that is itself collapsible (has children),
---stopping before the tree root -- collapsing the root would hide the whole
---tree, not just back out one level.
---@param state neotree.State
---@param tree_node table
---@return table? parent
local function collapsible_parent(state, tree_node)
  local ok_id, parent_id = pcall(function()
    return tree_node.get_parent_id and tree_node:get_parent_id()
  end)
  if not ok_id or not parent_id then return nil end

  local ok_parent, parent = pcall(function()
    return state.tree:get_node(parent_id)
  end)
  if not ok_parent or not parent then return nil end

  local ok_root, root = pcall(function()
    return state.tree:get_nodes()[1]
  end)
  local is_root = ok_root and root and parent.get_id and parent:get_id() == root:get_id()
  if is_root then return nil end

  if parent.has_children and parent:has_children() then return parent end
  return nil
end

---Whether `node` is currently displayed as a `group_empty_dirs` merged line
---(neo-tree's single-line display for a chain of directories holding nothing
---but another single directory, e.g. "personal/All/Finish") rather than an
---ordinary directory.
---
---The node's own display name IS the tell: `to_filetree_node` copies it
---verbatim from neo-tree's own `node.name` (see this file's `name = node.name`),
---and a merged node's name is literally the chain's separator-joined path
---segments, never a bare basename the way an ordinary directory's is --
---confirmed against a real neo-tree. `is_expanded()`/`has_children()` cannot
---make this call: a merged node mid-chain (not yet drilled into further)
---reports `false`/`false`, identically to an ordinary directory that was
---simply never opened, and a merged node drilled all the way to a real file
---reports `true`/`true`, identically to a genuinely expanded ordinary
---directory -- the name is the only signal an ordinary directory never has.
---@param node FiletreeNode
---@return boolean
local function is_group_empty_dirs_merge(node)
  return node.type == "directory"
    and type(node.name) == "string"
    and (node.name:find("/", 1, true) or node.name:find("\\", 1, true)) ~= nil
end

---Collapse `node`, falling back to its nearest collapsible ancestor when the
---node itself isn't expanded.
---
---A `group_empty_dirs` merged node (see `is_group_empty_dirs_merge`) always
---goes straight to `M.refresh()` regardless of its own `is_expanded()` state,
---checked FIRST, before any of the structural collapse logic below: neo-tree
---rebuilds that node from scratch on every lazy-loaded level (see
---`ui/renderer.lua:show_nodes`, the `state.group_empty_dirs` branch), spliced
---in via `tree:set_nodes()` directly rather than the usual `node:expand()`
---call -- so collapsing the node itself (or its structural parent) only ever
---hides whatever it most recently drilled into, leaving the display still
---merged on the very same line, not genuinely back to e.g. "personal". Each
---merge step also re-parents the replacement onto the *grandparent* of the
---directory it just absorbed (see `show_nodes`: `parentId =
---parent:get_parent_id()`), not onto anything still visible in between -- so
---a chain merged all the way from a top-level directory ends up parented
---directly on the tree root, where there is no structural ancestor left to
---collapse to at all. `M.refresh()` sidesteps both problems at once: it
---re-scans from disk and rebuilds the top level fresh, unmerged and collapsed
---because the merged node was never actually marked expanded to begin with.
---
---For an ordinary directory, the fallback mirrors neo-tree's own `close_node`
---command (bound to `C` by default): collapse the node itself if it is
---expanded-with-children, else its nearest collapsible ancestor stopping
---before the tree root -- collapsing root would hide the whole tree, and (for
---an ordinary directory, unlike a merged one) there is nothing there to fix
---with a refresh either, so this is a no-op instead.
---@param node FiletreeNode
---@return boolean
function M.collapse_node(node)
  local state = get_state()
  if not state or not state.tree then return false end
  local ok2, tree_node = pcall(function()
    return state.tree:get_node(node.id)
  end)
  if not ok2 or not tree_node then return false end

  if is_group_empty_dirs_merge(node) then
    -- Collapse the node itself FIRST when it is currently expanded (the
    -- "drilled all the way to a real file" state, e.g. Finish showing
    -- leaf.txt): neo-tree's own refresh preserves expand state across a
    -- rescan by re-walking `renderer.get_expanded_nodes(state.tree, ...)`
    -- and re-loading exactly those same ids (see fs_scan.lua's
    -- `handle_refresh_or_up`) -- so calling M.refresh() while this node's
    -- `is_expanded()` still reads true just rebuilds it right back into the
    -- same drilled-open state, a no-op in practice even though a real
    -- filesystem rescan happened. Collapsing first clears that flag so the
    -- rescan actually lands on a clean, collapsed "personal".
    if tree_node.is_expanded and tree_node:is_expanded() and tree_node.collapse then
      pcall(function()
        tree_node:collapse()
      end)
    end
    return M.refresh()
  end

  local target
  if
    tree_node.is_expanded
    and tree_node:is_expanded()
    and tree_node.has_children
    and tree_node:has_children()
  then
    target = tree_node
  else
    target = collapsible_parent(state, tree_node)
  end

  if target and target.collapse then
    target:collapse()
    local ok3, renderer = pcall(require, "neo-tree.ui.renderer")
    if ok3 and renderer then
      if renderer.redraw then pcall(renderer.redraw, state) end
      if renderer.focus_node and target.get_id then
        pcall(renderer.focus_node, state, target:get_id())
      end
    end
    return true
  end

  return false
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
    preview = "split",
  }
  local cmd = cmd_map[mode]
  if not cmd then return false end
  local ok = pcall(function()
    vim.cmd(cmd .. " " .. vim.fn.fnameescape(path))
  end)
  return ok
end

---@param path string
---@return boolean
function M.set_root(path)
  local commands = get_commands()
  if not commands then return false end
  local ok = pcall(commands.execute, {
    action = "show",
    source = "filesystem",
    position = get_current_position(),
    dir = path,
  })
  return ok
end

---@param path string
---@param parent_levels? integer
---@param root_dir? string
---@return boolean
function M.open_reveal(path, parent_levels, root_dir)
  local commands = get_commands()
  if not commands then return false end
  -- Explicit root_dir (e.g. the project root resolved by cwd_sync) wins: the tree
  -- is rooted there. Otherwise derive the root from the file by ascending
  -- `parent_levels` (legacy behaviour).
  local target = root_dir
  if not target or target == "" then
    target = path
    for _ = 1, (parent_levels or 0) do -- fixed: was 0,n (ran n+1 times); now 1,n (runs n times)
      target = vim.fn.fnamemodify(target, ":h")
    end
  end
  -- `dir` is the tree root neo-tree navigates/tcd's to, so it MUST be a
  -- directory. With parent_levels = 0 (the default) and no root_dir, `target` is
  -- still the file itself — passing that made neo-tree run `tcd <file>` →
  -- E344/ENOTDIR. Ascend to the containing directory whenever target is not one.
  if vim.fn.isdirectory(target) ~= 1 then target = vim.fn.fnamemodify(target, ":h") end
  local ok = pcall(commands.execute, {
    action = "show",
    source = "filesystem",
    position = get_current_position(),
    dir = target,
    reveal_file = path,
  })
  return ok
end

---@return boolean
function M.open_cwd()
  local commands = get_commands()
  if not commands then return false end
  local ok = pcall(commands.execute, {
    action = "show",
    source = "filesystem",
    position = get_current_position(),
  })
  return ok
end

---Toggle the tree at a given position, optionally revealing a file / setting root.
---
---Self-heals one neo-tree race. Toggling again before the (debounced)
---`filesystem_navigate` scan of a previous toggle has settled -- a keypress
---that lands right after startup is the easiest way -- makes
---`nvim_buf_set_name` collide inside `renderer.acquire_window()` (E95: a
---buffer with this name already exists). Left alone, that leaves a blank,
---unfocusable "neo-tree" window that re-errors on every redraw; the manual
---remedy was to press the key again, which opened a second, working window
---next to the dead one. So on failure any window still showing an unnamed
---(never rendered) neo-tree buffer is closed and the toggle is retried once.
---@param position FiletreeTreePosition
---@param opts? FiletreeToggleOpts
---@return boolean
function M.toggle_at(position, opts)
  opts = opts or {}
  local commands = get_commands()
  if not commands then return false end
  local exec_opts = {
    action = "focus",
    source = "filesystem",
    position = position,
    toggle = true,
    reveal = opts.reveal == true,
    reveal_file = opts.reveal and opts.file or nil,
    reveal_force_cwd = opts.reveal == true and opts.reveal_force_cwd == true,
    dir = opts.dir,
  }
  if pcall(commands.execute, exec_opts) then return true end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "neo-tree" and vim.api.nvim_buf_get_name(buf) == "" then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  local ok, err = pcall(commands.execute, exec_opts)
  if not ok then notify.warn("toggle failed: " .. tostring(err)) end
  return ok
end

---@return boolean
function M.close()
  local commands = get_commands()
  if not commands then return false end
  local ok = pcall(commands.execute, { action = "close", source = "filesystem" })
  return ok
end

---Re-scan the filesystem and re-render the tree — the same thing neo-tree's own
---`R` mapping does.
---
---Deliberately routed through `sources.manager.refresh` rather than
---`neo-tree.command.execute`: `execute` only ever understands the "show",
---"focus" and "close" actions, so an `action = "refresh"` fell straight through
---`do_show_or_focus` without matching either branch and did nothing at all —
---while still reporting success, since nothing threw. A newly created directory
---then only appeared when some *unrelated* event happened to re-navigate the
---tree (opening a file right after a create, follow_current_file firing, ...),
---which is why a manual `R` was needed roughly half the time.
---@return boolean
function M.refresh()
  local manager = get_manager()
  if not manager or type(manager.refresh) ~= "function" then return false end
  return (pcall(manager.refresh, "filesystem"))
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

---@param line integer
---@return boolean
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

---@internal
local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_current_hl_neotree") end
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
---@internal
local function sign_ns()
  if not _sign_ns then _sign_ns = vim.api.nvim_create_namespace("filetree_sign_neotree") end
  return _sign_ns
end

---@param path string
---@param text string
---@param hl_group string
---@return boolean
function M.sign_node(path, text, hl_group)
  local line = M.get_node_line(path)
  if not line then return false end
  local _, bufnr = M.is_open()
  if not bufnr then return false end
  M.unsign_node(path)
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, sign_ns(), line - 1, 0, {
    sign_text = text,
    sign_hl_group = hl_group,
    priority = 160,
  })
  if ok then _sign_marks[path] = id end
  return ok
end

---@param path string
---@return boolean
function M.unsign_node(path)
  local id = _sign_marks[path]
  if not id then return true end
  local _, bufnr = M.is_open()
  if not bufnr then return false end
  local ok = pcall(vim.api.nvim_buf_del_extmark, bufnr, sign_ns(), id)
  _sign_marks[path] = nil
  return ok
end

-- ── Render-event bridge ───────────────────────────────────────────────────────

-- Neo-tree redraws its buffer on its own schedule, not just when filetree asks
-- it to: a git-status fetch landing, a filesystem-watcher event, a background
-- diagnostics update, `follow_current_file`, all rewrite the tree buffer from
-- scratch. Any decoration drawn as an extmark on the previous render (marks'
-- checkmarks, most visibly -- see the bug this fixes: a checkmark surviving
-- only until the next such redraw, which reads as "vanishes after a second")
-- gets wiped along with it. Callers that need to redraw a decoration in sync
-- with neo-tree's OWN render cycle -- not just filetree's BufEnter/BufWritePost
-- dispatch -- subscribe here instead of guessing at a poll interval.
---@type table<fun(), true>
local _render_listeners = {}
---@type boolean
local _render_hook_installed = false

---@internal
---@return boolean installed
local function install_render_hook()
  if _render_hook_installed then return true end
  local ok, events = pcall(require, "neo-tree.events")
  if not ok then return false end
  local handler = {
    event = events.AFTER_RENDER,
    id = "filetree_neotree_after_render",
    handler = function()
      for callback in pairs(_render_listeners) do
        pcall(callback)
      end
    end,
  }
  -- Unsubscribe first: neo-tree's event queue does not dedupe by id, so a
  -- second subscribe (e.g. filetree.setup() re-running) would otherwise fire
  -- the same handler twice per render.
  pcall(events.unsubscribe, handler)
  pcall(events.subscribe, handler)
  _render_hook_installed = true
  return true
end

---Subscribe `callback` to fire every time neo-tree finishes (re)rendering the
---filesystem tree. Neo-tree may not be loaded yet (cmd-lazy), so installation
---is retried a few times, mirroring sidebar_guard's deferred install.
---@param callback fun()
---@return fun() unsubscribe
function M.on_render(callback)
  local cancelled = false
  if install_render_hook() then
    _render_listeners[callback] = true
  else
    local tries = 0
    local function retry()
      if cancelled then return end
      tries = tries + 1
      if install_render_hook() then
        if not cancelled then _render_listeners[callback] = true end
        return
      end
      if tries < 20 then vim.defer_fn(retry, 150) end
    end
    vim.defer_fn(retry, 150)
  end
  return function()
    cancelled = true
    _render_listeners[callback] = nil
  end
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
---@return nil
function M.install_reveal_guard()
  if _reveal_guard_installed then return end
  local ok, commands = pcall(require, "neo-tree.command")
  if not ok or type(commands.execute) ~= "function" then return end

  local original_execute = commands.execute
  -- Deliberate monkeypatch of neo-tree's own module table, not a
  -- redefinition -- see the doc-comment on install_reveal_guard above.
  ---@diagnostic disable-next-line: duplicate-set-field
  commands.execute = function(args, ...)
    if
      type(args) == "table"
      and args.dir == nil
      and args.reveal_force_cwd == nil
      and args.reveal ~= false
    then
      args.reveal_force_cwd = true
    end
    return original_execute(args, ...)
  end

  _reveal_guard_installed = true
end

-- Self-register
registry.register(M)

return M
