---@module 'filetree.features.rename_batch'
---@brief Batch-rename visible tree nodes in a scratch buffer.
---@description
--- Opens a scratch buffer listing the names (not full paths) of all visible
--- file and directory nodes in the current tree. The user edits the names
--- in normal Vim; on write (:w) the module diffs old vs new and executes
--- the renames via vim.fn.rename(). Directories are renamed atomically.
---
--- Features:
---   - Order-preserving: line 1 = node 1 no matter what.
---   - Dry-run preview: shows the plan before executing.
---   - Undo: uses safety backup if safety feature is loaded.
---   - Conflict detection: refuses to rename if the target already exists.
---
--- Keymap (default): "R" in tree buffer.
--- User commands: :FiletreeRenameBatch

local notify = require("filetree.util.notify").create("[filetree.rename_batch]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeRenameBatchConfig
local _cfg = {
  enabled     = false,
  keymap      = "R",
  confirm     = true,
  use_safety  = true,
  dry_run     = false,
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Node snapshot ─────────────────────────────────────────────────────────────

---@class RenameEntry
---@field abs_dir  string  Parent directory.
---@field old_name string  Original filename (tail only).
---@field new_name string  Name after user edit.

---@return RenameEntry[]
local function snapshot_nodes()
  if not _adapter then return {} end
  local nodes = _adapter.get_visible_nodes and _adapter.get_visible_nodes() or {}
  local entries = {}
  for _, node in ipairs(nodes) do
    if node.type == "file" or node.type == "directory" then
      local abs_dir  = vim.fn.fnamemodify(node.path, ":h")
      local old_name = vim.fn.fnamemodify(node.path, ":t")
      entries[#entries + 1] = {
        abs_dir  = abs_dir,
        old_name = old_name,
        new_name = old_name,
      }
    end
  end
  return entries
end

-- ── Diff + execute ────────────────────────────────────────────────────────────

---@param entries RenameEntry[]
---@param new_names string[]  Edited lines from the scratch buffer.
---@return boolean ok
local function execute_renames(entries, new_names)
  -- Pair up and collect changes
  ---@type {src:string, dst:string}[]
  local plan = {}

  for i, entry in ipairs(entries) do
    local new = new_names[i] and vim.trim(new_names[i]) or ""
    if new == "" then
      notify.warn(string.format("Line %d is blank — skipping %s", i, entry.old_name))
    elseif new ~= entry.old_name then
      local src = entry.abs_dir .. "/" .. entry.old_name
      local dst = entry.abs_dir .. "/" .. new
      plan[#plan + 1] = { src = src, dst = dst }
    end
  end

  if #plan == 0 then
    notify.info("Nothing to rename")
    return true
  end

  -- Conflict check
  local blocked = false
  for _, op in ipairs(plan) do
    if vim.fn.filereadable(op.dst) == 1 or vim.fn.isdirectory(op.dst) == 1 then
      notify.error("Target already exists: " .. op.dst)
      blocked = true
    end
  end
  if blocked then return false end

  -- Dry-run
  if _cfg.dry_run then
    local lines = { "-- Rename plan (dry-run) --" }
    for _, op in ipairs(plan) do
      lines[#lines + 1] = "  " .. vim.fn.fnamemodify(op.src, ":t")
              .. " → " .. vim.fn.fnamemodify(op.dst, ":t")
    end
    notify.info(table.concat(lines, "\n"))
    return true
  end

  -- Confirm
  if _cfg.confirm then
    local q = string.format("Rename %d item(s)? [y/N] ", #plan)
    local answer = vim.fn.input(q)
    if answer:lower() ~= "y" then
      notify.info("Cancelled")
      return false
    end
  end

  -- Safety backup
  if _cfg.use_safety then
    local ok_s, safety = require("filetree.features").load("safety")
    if ok_s and safety then
      for _, op in ipairs(plan) do
        pcall(safety.before_move, op.src, op.dst)
      end
    end
  end

  -- Execute
  local errors = 0
  for _, op in ipairs(plan) do
    local rc = vim.fn.rename(op.src, op.dst)
    if rc ~= 0 then
      notify.error("Failed: " .. op.src .. " → " .. op.dst)
      errors = errors + 1
    end
  end

  local done = #plan - errors
  notify.info(string.format("Renamed %d/%d item(s)", done, #plan))

  -- Refresh tree
  if _adapter and _adapter.refresh then
    pcall(_adapter.refresh)
  end

  return errors == 0
end

-- ── Scratch buffer ────────────────────────────────────────────────────────────

function M.open()
  local entries = snapshot_nodes()
  if #entries == 0 then
    notify.warn("No visible nodes in tree")
    return
  end

  local names = {}
  for _, e in ipairs(entries) do names[#names + 1] = e.old_name end

  -- Open horizontal split with scratch buffer
  vim.cmd("new")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(bufnr, "filetree://rename")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, names)
  vim.api.nvim_set_option_value("buftype",  "acwrite", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden","wipe",    { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false,     { buf = bufnr })

  local augroup = au.group("filetree_rename_batch_" .. bufnr, true)

  -- BufWriteCmd fires when user does :w
  au.acmd("BufWriteCmd", {
    group  = augroup,
    buffer = bufnr,
    callback = function()
      local new_names = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local ok = execute_renames(entries, new_names)
      if ok then
        vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
        -- Close the scratch window
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end,
  })

  au.acmd("BufDelete", {
    group  = augroup,
    buffer = bufnr,
    once   = true,
    callback = function()
      au.del_group(augroup)
    end,
  })

  -- Header comment
  local header = string.format(
    "-- filetree: rename %d items. Edit names, then :w to apply or :bd to cancel.",
    #entries
  )
  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { header, "" })
  -- Offset entries by 2 lines (header + blank)
  -- Re-adjust entries reference to skip header offset in BufWriteCmd:
  -- The autocmd captures `entries` from the snapshot; new_names will have
  -- the header lines so we strip them:
  vim.api.nvim_buf_set_var(bufnr, "filetree_header_lines", 2)

  -- Override execute to handle header offset
  au.del_group(augroup)
  augroup = au.group("filetree_rename_batch_" .. bufnr, true)
  au.acmd("BufWriteCmd", {
    group  = augroup,
    buffer = bufnr,
    callback = function()
      local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local new_names = {}
      for i = 3, #all_lines do  -- skip 2-line header
        new_names[#new_names + 1] = all_lines[i]
      end
      local ok = execute_renames(entries, new_names)
      if ok then
        vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end,
  })
  au.acmd("BufDelete", {
    group  = augroup,
    buffer = bufnr,
    once   = true,
    callback = function()
      au.del_group(augroup)
    end,
  })

  -- Syntax: make header lines look like comments
  vim.cmd("syntax match Comment /^--.*$/")

  notify.info(string.format("Edit %d filenames. :w to apply, :bd to cancel.", #entries))
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeRenameBatchConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_rename_batch", true)

  if _cfg.keymap then
    au.acmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap, M.open, {
            buffer = buf,
            silent = true,
            desc   = "Filetree: open batch rename buffer",
          })
        end)
      end,
    })
  end

end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
