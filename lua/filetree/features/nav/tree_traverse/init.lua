---@module 'filetree.features.tree_traverse'
---@brief Navigate up/down the directory tree with optional CWD sync.

local map = require("filetree.util.map")
local tree_attach = require("filetree.util.tree_attach")
local M = {}

---@type FiletreeTreeTraverseConfig
local _cfg = {}
---@type FiletreeAdapter?
local _adapter = nil

local notify = require("filetree.util.notify").create("[filetree.tree_traverse]")

---Change the tree root and optionally sync cwd.
---@param path string   Absolute directory path to navigate to.
local function go_to(path)
  if not _adapter then return end

  if type(_adapter.set_root) == "function" then
    pcall(_adapter.set_root, path)
  else
    -- Fallback: set cwd first, then re-open at cwd
    pcall(vim.cmd, "cd " .. vim.fn.fnameescape(path:gsub("\\", "/")))
    pcall(_adapter.open_cwd)
  end

  if _cfg.sync_cwd then
    local safe_path = path:gsub("\\", "/")
    pcall(vim.cmd, "cd " .. vim.fn.fnameescape(safe_path))
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

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type FiletreeTreeTraverseConfig
local DEFAULTS = {
  keymap_up   = "-",
  keymap_down = "+",
  sync_cwd    = false,
}

---@param cfg FiletreeTreeTraverseConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg     = vim.tbl_extend("force", DEFAULTS, cfg or {})
  cfg      = _cfg
  _adapter = adapter

  tree_attach.on_attach(function(buf)
    if cfg.keymap_up and cfg.keymap_up ~= "" then
      map("n", cfg.keymap_up, function()
        -- M.up() has no count parameter of its own (each call climbs exactly
        -- one level via go_to()), so a count prefix loops it.
        for _ = 1, vim.v.count1 do M.up() end
      end, { buffer = buf, desc = "filetree: traverse up (×count)", silent = true })
    end
    if cfg.keymap_down and cfg.keymap_down ~= "" then
      map("n", cfg.keymap_down, function()
        for _ = 1, vim.v.count1 do M.down() end
      end, { buffer = buf, desc = "filetree: traverse down (×count)", silent = true })
    end
  end)
end

function M.teardown()
  _adapter = nil
end

return M
