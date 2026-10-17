---@module 'filetree.features.nav.tree_traverse'
---@brief Navigate up/down the directory tree with optional CWD sync.

local M = {}

---@type FiletreeTreeTraverseConfig
local _cfg = {}
---@type FiletreeAdapter?
local _adapter = nil

local notify = require("filetree.util.notify").create("[filetree.tree_traverse]")
local bind = require("filetree.util.bind")

---Change the tree root and optionally sync cwd.
---@param path string   Absolute directory path to navigate to.
local function go_to(path)
  if not _adapter then return end

  if type(_adapter.set_root) == "function" then
    pcall(_adapter.set_root, path)
  else
    -- Fallback: set cwd first, then re-open at cwd
    pcall(function()
      vim.cmd("cd " .. vim.fn.fnameescape(path:gsub("\\", "/")))
    end)
    pcall(_adapter.open_cwd)
  end

  if _cfg.sync_cwd then
    local safe_path = path:gsub("\\", "/")
    pcall(function()
      vim.cmd("cd " .. vim.fn.fnameescape(safe_path))
    end)
    notify.info("cwd → " .. safe_path)
  end

  -- Re-rooting here is a deliberate act, and it is the one thing a cwd lock
  -- must not fight: without this the lock would revert the cwd right after the
  -- user pressed `+`, leaving the tree and the cwd pointing at different
  -- directories. cwd_mode moves its pin instead (see lock.follow_manual_root).
  local mode = require("filetree.features").require("cwd_mode")
  if mode and type(mode.notify_manual_root) == "function" then
    pcall(mode.notify_manual_root, path)
  end
end

---Navigate to the parent directory.
function M.up()
  if not _adapter then return end

  local root = _adapter.get_root_path()
  if not root then
    notify.warn("No root path available")
    return
  end

  local parent = vim.fn.fnamemodify(root, ":h")
  if parent == root then
    notify.warn("Already at filesystem root")
    return
  end

  go_to(parent)
end

---Navigate into the current directory node (set it as new root).
function M.down()
  if not _adapter then return end

  local node = _adapter.get_current_node()
  if not node then
    notify.warn("No current node")
    return
  end

  if node.type ~= "directory" then
    notify.warn("Current node is not a directory")
    return
  end

  go_to(node.path)
end

---Navigate the tree root directly to an explicit directory path.
---@param path string  Absolute (or CWD-relative) directory path.
function M.go_to(path)
  if not _adapter then return end

  if type(path) ~= "string" or path == "" then
    notify.warn("no directory given")
    return
  end

  if vim.fn.isdirectory(path) ~= 1 then
    notify.warn("not a directory: " .. path)
    return
  end

  go_to(path)
end

-- ── Sibling jumps ─────────────────────────────────────────────────────────────

---Index of the cursor node in the rendered node list: by line, else by path.
---@param nodes FiletreeNode[]
---@param cur FiletreeNode
---@return integer?
local function index_of(nodes, cur)
  for i, n in ipairs(nodes) do
    if cur.line_number and n.line_number == cur.line_number then return i end
  end
  for i, n in ipairs(nodes) do
    if n.path == cur.path then return i end
  end
  return nil
end

---Target of a sibling jump from the cursor node, without moving anything.
---
---Siblings are the rendered nodes at the cursor's depth between the nearest
---shallower node above it and the nearest shallower node below it, so the
---children of an expanded sibling are skipped. Flat listings (mini.files,
---netrw, oil report depth 1 for every entry) degrade to plain next/previous.
---@param step integer   +1 = next sibling, -1 = previous sibling.
---@param count? integer Number of siblings to move (default 1).
---@return FiletreeNode?
function M.sibling_target(step, count)
  if not _adapter then return nil end
  local cur = _adapter.get_current_node()
  if not cur then return nil end
  local nodes = vim.deepcopy(_adapter.get_visible_nodes() or {})
  table.sort(nodes, function(a, b)
    return (a.line_number or 0) < (b.line_number or 0)
  end)
  local idx = index_of(nodes, cur)
  if not idx then return nil end

  local depth = nodes[idx].depth or 1
  local first, last = idx, idx
  while first > 1 and (nodes[first - 1].depth or 1) >= depth do
    first = first - 1
  end
  while last < #nodes and (nodes[last + 1].depth or 1) >= depth do
    last = last + 1
  end

  local siblings, pos = {}, nil
  for i = first, last do
    if (nodes[i].depth or 1) == depth then
      siblings[#siblings + 1] = nodes[i]
      if i == idx then pos = #siblings end
    end
  end
  if not pos or #siblings < 2 then return nil end

  local target = pos + step * (count or 1)
  if _cfg.sibling_wrap then
    target = (target - 1) % #siblings + 1
  else
    target = math.max(1, math.min(#siblings, target))
  end
  if target == pos then return nil end
  return siblings[target]
end

---Move the cursor to the next (`step` = 1) or previous (`step` = -1) sibling.
---@param step integer
---@param count? integer
---@return boolean moved
function M.sibling(step, count)
  local target = M.sibling_target(step, count)
  if not _adapter or not target or not target.line_number then return false end
  return _adapter.scroll_to_line(target.line_number) == true
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type FiletreeTreeTraverseConfig
local DEFAULTS = {
  keymap_up = "-",
  keymap_down = "+",
  keymap_next_sibling = "]s",
  keymap_prev_sibling = "[s",
  sibling_wrap = false,
  sync_cwd = false,
}

---Option schema (see `filetree.config.schema`): exactly what
---`features.tree_traverse` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {
  keymap_up = "keymap",
  keymap_down = "keymap",
  keymap_next_sibling = "keymap",
  keymap_prev_sibling = "keymap",
  sibling_wrap = "boolean",
  sync_cwd = "boolean",
}

---@param cfg FiletreeTreeTraverseConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg = vim.tbl_extend("force", DEFAULTS, cfg or {})
  cfg = _cfg
  _adapter = adapter

  bind.bind("tree_traverse", cfg, {
    {
      name = "up",
      field = "keymap_up",
      desc = "traverse up (×count)",
      rhs = function()
        -- M.up() has no count parameter of its own (each call climbs exactly
        -- one level via go_to()), so a count prefix loops it.
        for _ = 1, vim.v.count1 do
          M.up()
        end
      end,
    },
    {
      name = "down",
      field = "keymap_down",
      desc = "traverse down (×count)",
      rhs = function()
        for _ = 1, vim.v.count1 do
          M.down()
        end
      end,
    },
    {
      name = "next_sibling",
      field = "keymap_next_sibling",
      desc = "next sibling (×count)",
      rhs = function()
        M.sibling(1, vim.v.count1)
      end,
    },
    {
      name = "prev_sibling",
      field = "keymap_prev_sibling",
      desc = "previous sibling (×count)",
      rhs = function()
        M.sibling(-1, vim.v.count1)
      end,
    },
  })
end

function M.teardown()
  _adapter = nil
end

return M
