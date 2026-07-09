---@module 'filetree.adapter.nvimtree'
---@brief nvim-tree adapter — implements FiletreeAdapter for nvim-tree.lua.

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
    NvimTreeNormal      = "Normal",
    NvimTreeNormalNC    = "NormalNC",
    NvimTreeEndOfBuffer = "EndOfBuffer",
  },
}

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function api()
  local ok, a = pcall(require, "nvim-tree.api")
  if not ok then return nil end
  return a
end

-- ── Interface ─────────────────────────────────────────────────────────────────

function M.is_available()
  return pcall(require, "nvim-tree")
end

function M.is_open()
  local a = api()
  if not a then return false, nil end
  local ok, view = pcall(require, "nvim-tree.view")
  if not ok or not view then return false, nil end
  if not view.is_visible() then return false, nil end
  local ok2, bufnr = pcall(function() return view.get_bufnr() end)
  if ok2 and bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    return true, bufnr
  end
  return false, nil
end

function M.get_bufnr()
  local _, bufnr = M.is_open()
  return bufnr
end

function M.get_winid()
  local a = api()
  if not a then return nil end
  local ok, winid = pcall(function() return a.tree.winid() end)
  if ok and winid and vim.api.nvim_win_is_valid(winid) then
    return winid
  end
  return nil
end

function M.set_root(path)
  local a = api()
  if not a then return false end
  local ok = pcall(a.tree.change_root, path)
  return ok
end

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

function M.get_current_node()
  local a = api()
  if not a then return nil end
  local ok, node = pcall(function() return a.tree.get_node_under_cursor() end)
  if not ok or not node then return nil end
  local ntype = node.type == "directory" and "directory" or "file"
  return {
    id          = node.absolute_path or "",
    name        = node.name or "",
    path        = node.absolute_path or "",
    type        = ntype,
    depth       = node.level or 0,
    line_number = vim.fn.line("."),
    is_expanded = ntype == "directory" and (node.open or false) or nil,
  }
end

function M.get_visible_nodes(filter)
  local a = api()
  if not a then return {} end
  local ok, all = pcall(function()
    local nodes = {}
    local function walk(node, depth)
      if not node then return end
      local ntype = node.type == "directory" and "directory" or "file"
      local include = filter == nil or filter == "all"
        or (filter == "files"   and ntype == "file")
        or (filter == "folders" and ntype == "directory")
      if include then
        nodes[#nodes + 1] = {
          id          = node.absolute_path or "",
          name        = node.name or "",
          path        = node.absolute_path or "",
          type        = ntype,
          depth       = depth,
          line_number = #nodes + 1,
          is_expanded = ntype == "directory" and (node.open or false) or nil,
        }
      end
      if ntype == "directory" and node.open and node.nodes then
        for _, child in ipairs(node.nodes) do
          walk(child, depth + 1)
        end
      end
    end
    local tree = require("nvim-tree.core").get_explorer()
    if tree and tree.nodes then
      for _, node in ipairs(tree.nodes) do walk(node, 1) end
    end
    return nodes
  end)
  if not ok then
    notify.warn("get_visible_nodes failed: " .. tostring(all))
    return {}
  end
  return all
end

-- nvim-tree's node.absolute_path is native-separator (backslash on Windows),
-- while callers (cwd_sync/auto_reveal/current_hl) query with paths sourced from
-- vim.api.nvim_buf_get_name()/expand("%:p"), which return forward-slash paths on
-- this platform's Neovim build. Normalize both sides before comparing, or the
-- lookup silently misses on Windows. See adapter/neotree.lua's key_of() for the
-- same fix in that adapter.
function M.get_node_line(node_path)
  local query = pathutil.slashify(node_path)
  local nodes = M.get_visible_nodes()
  for _, n in ipairs(nodes) do
    if n.path and pathutil.slashify(n.path) == query then return n.line_number end
  end
  return nil
end

function M.expand_node(node)
  local a = api()
  if not a then return false end
  if node.type ~= "directory" then return false end
  local ok = pcall(function()
    local lib = require("nvim-tree.lib")
    local nvim_node = lib.get_node_at_cursor()
    if nvim_node and nvim_node.absolute_path == node.path then
      lib.expand_or_collapse(nvim_node)
    end
  end)
  return ok
end

function M.collapse_node(node)
  return M.expand_node(node) -- toggle-style; expand_node opens/closes
end

function M.open_file(path, mode)
  mode = mode or "edit"
  local cmd_map = {
    edit   = "edit",
    split  = "split",
    vsplit = "vsplit",
    tab    = "tabnew",
  }
  local cmd = cmd_map[mode] or "edit"
  local ok = pcall(vim.cmd, cmd .. " " .. vim.fn.fnameescape(path))
  return ok
end

function M.open_reveal(path, _parent_levels)
  local a = api()
  if not a then return false end
  if not M.is_open() then
    local ok1 = pcall(function() a.tree.open() end)
    if not ok1 then return false end
  end
  local ok2 = pcall(function() a.tree.find_file(path) end)
  return ok2
end

function M.open_cwd()
  local a = api()
  if not a then return false end
  local ok = pcall(function() a.tree.open({ path = vim.fn.getcwd() }) end)
  return ok
end

function M.close()
  local a = api()
  if not a then return false end
  local ok = pcall(function() a.tree.close() end)
  return ok
end

function M.refresh()
  local a = api()
  if not a then return false end
  local ok = pcall(function() a.tree.reload() end)
  return ok
end

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

local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_current_hl_nvimtree") end
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
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns(), id)
  _hl_marks[path] = nil
  return true
end

-- Self-register
registry.register(M)

return M
