---@module 'filetree.features.tree_traverse'
---@brief Navigate up/down the directory tree with optional CWD sync.

local M = {}

---@type FiletreeTreeTraverseConfig
local _cfg = {}
---@type FiletreeAdapter?
local _adapter = nil
---@type integer?
local _augroup = nil

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

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_tree_traverse", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group    = _augroup,
    pattern  = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if cfg.keymap_up and cfg.keymap_up ~= "" then
          vim.keymap.set("n", cfg.keymap_up, function() M.up() end,
            { buffer = buf, desc = "filetree: traverse up", silent = true })
        end
        if cfg.keymap_down and cfg.keymap_down ~= "" then
          vim.keymap.set("n", cfg.keymap_down, function() M.down() end,
            { buffer = buf, desc = "filetree: traverse down", silent = true })
        end
      end)
    end,
  })
end

function M.teardown()
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
