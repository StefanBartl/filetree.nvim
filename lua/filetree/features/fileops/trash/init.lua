---@module 'filetree.features.trash'
---@brief Send files to system trash with in-session undo support.
---@description
--- Provides M.delete(path) which moves the node's file/directory to the
--- system trash (platform-specific) and records it for later restoration.
--- Integrates with the safety feature for optional pre-trash backup.
---
--- Keymaps (in tree buffer, default):
---   d            Trash current node (or all marked nodes)
---   U            Undo last trash operation
---   <leader>th   Show trash history

local trash_platform = require("filetree.features.fileops.trash.platform")
local undo           = require("filetree.features.fileops.trash.undo")
local notify         = require("filetree.util.notify").create("[filetree.trash]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")

local M = {}

---@type FiletreeTrashConfig
local _cfg = {
  enabled        = false,
  confirm        = false,
  use_safety     = false,
  dry_run        = false,
  keymap         = "d",
  keymap_undo    = "U",
  keymap_history = "<leader>th",
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function confirm(path)
  local answer = vim.fn.confirm(
    "Send to trash?\n  " .. path,
    "&Yes\n&No", 2
  )
  return answer == 1
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Send the given path to the system trash.
---@param path string  Absolute path of the file or directory.
---@return boolean ok
function M.delete(path)
  if not _cfg.enabled then
    notify.warn("trash feature is disabled")
    return false
  end

  if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
    notify.warn("path does not exist: " .. path)
    return false
  end

  if _cfg.confirm and not confirm(path) then
    return false
  end

  if _cfg.dry_run then
    notify.info("[dry-run] would trash: " .. path)
    undo.record(path)
    return true
  end

  -- Optional pre-trash backup via safety feature
  if _cfg.use_safety then
    local ok_sf, safety = require("filetree.features").load("safety")
    if ok_sf then pcall(safety.before_delete, path) end
  end

  local result = trash_platform.send(path)
  if not result.ok then
    notify.error("Trash failed: " .. (result.err or "unknown error"))
    return false
  end

  undo.record(path)

  -- Refresh tree
  if _adapter then pcall(_adapter.refresh) end

  return true
end

---Trash the current node, or all marked nodes if any are marked.
function M.delete_current()
  if not _adapter then return end

  local paths
  local ok_m, marks = require("filetree.features").load("marks")
  if ok_m and marks and marks.count() > 0 then
    paths = marks.get_marked()
    marks.clear_all()
  else
    local node = _adapter.get_current_node()
    paths = node and { node.path } or {}
  end

  if #paths == 0 then
    notify.warn("No node selected")
    return
  end

  for _, path in ipairs(paths) do
    M.delete(path)
  end
end

---Restore the last trashed item.
---@return boolean ok
function M.undo_last()
  return undo.restore_last()
end

---Show the in-session trash history.
function M.show_history()
  undo.show_history()
end

---Toggle dry-run mode.
function M.toggle_dry_run()
  _cfg.dry_run = not _cfg.dry_run
  notify.info("dry-run: " .. (_cfg.dry_run and "ON" or "OFF"))
end

---Return true when the current platform has a supported trash backend.
---@return boolean
function M.available()
  return trash_platform.available()
end

---@type integer?
local _augroup = nil

---@param config FiletreeTrashConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if not trash_platform.available() then
    notify.warn("No trash backend found on this platform. Feature disabled.")
    _cfg.enabled = false
    return
  end

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_trash", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local function kmap(key, fn, desc)
          if key and key ~= "" then
            map("n", key, fn, { buffer = buf, silent = true, desc = "Filetree: " .. desc })
          end
        end
        kmap(_cfg.keymap,         M.delete_current, "trash current node")
        kmap(_cfg.keymap_undo,    M.undo_last,      "undo last trash")
        kmap(_cfg.keymap_history, M.show_history,   "show trash history")
      end)
    end,
  })
end

function M.teardown()
  _adapter = nil
  _cfg.enabled = false
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
