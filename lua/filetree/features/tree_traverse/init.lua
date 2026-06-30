---@module 'filetree.features.tree_traverse'
---@brief Navigate up/down the directory tree with optional CWD sync.

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

  -- Try open_reveal with depth 0 as the mechanism to change root
  local ok = pcall(_adapter.open_reveal, path, 0)
  if not ok then
    pcall(_adapter.open_cwd)
  end

  if _cfg.sync_cwd then
    local safe_path = path:gsub("\\", "/")
    pcall(vim.cmd, "cd " .. vim.fn.fnameescape(safe_path))
    notify.info("cwd → " .. path)
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

---@param cfg FiletreeTreeTraverseConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg     = cfg
  _adapter = adapter

  local function set_keymaps(buf)
    if cfg.keymap_up then
      vim.keymap.set("n", cfg.keymap_up, function() M.up() end,
        { buffer = buf, desc = "filetree: traverse up", silent = true })
    end
    if cfg.keymap_down then
      vim.keymap.set("n", cfg.keymap_down, function() M.down() end,
        { buffer = buf, desc = "filetree: traverse down", silent = true })
    end
  end

  local winid = adapter.get_winid and adapter.get_winid()
  if winid then
    set_keymaps(vim.api.nvim_win_get_buf(winid))
  else
    vim.api.nvim_create_autocmd("FileType", {
      pattern  = { "neo-tree", "NvimTree" },
      callback = function(ev)
        set_keymaps(ev.buf)
      end,
    })
  end
end

function M.teardown()
  _adapter = nil
end

return M
