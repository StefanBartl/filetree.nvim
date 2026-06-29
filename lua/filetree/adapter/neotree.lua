---@module 'filetree.adapter.neotree'
---@brief Neo-tree adapter — implements the FiletreeAdapter interface for neo-tree.nvim.

local notify = require("filetree.util.notify").create("[filetree.adapter.neotree]")
local registry = require("filetree.adapter")

---@class FiletreeNeotreeAdapter : FiletreeAdapter
local M = { name = "neotree" }

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
  local id = (node.get_id and node:get_id()) or node.id or ""
  local ntype = node.type == "directory" and "directory" or "file"
  return {
    id          = id,
    name        = node.name or "",
    path        = id,
    type        = ntype,
    depth       = (node.get_depth and node:get_depth()) or 0,
    line_number = vim.fn.line("."),
    is_expanded = ntype == "directory" and ((node.is_expanded and node:is_expanded()) or false) or nil,
  }
end

function M.get_visible_nodes(filter)
  local state = get_state()
  if not state or not state.tree then return {} end

  local nodes = {}
  local line_nr = 1

  local function collect(node)
    if not node then return end
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
  return nodes
end

function M.get_node_line(path)
  local nodes = M.get_visible_nodes()
  for _, node in ipairs(nodes) do
    if node.path == path then return node.line_number end
  end
  return nil
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

function M.open_reveal(path, parent_levels)
  local commands = get_commands()
  if not commands then return false end
  local target = path
  for _ = 0, (parent_levels or 0) do
    target = vim.fn.fnamemodify(target, ":h")
  end
  local ok = pcall(commands.execute, {
    action      = "show",
    source      = "filesystem",
    position    = "left",
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
    position = "left",
  })
  return ok
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

-- Self-register
registry.register(M)

return M
