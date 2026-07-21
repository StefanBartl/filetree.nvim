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
--- Keymap (default): "<leader>rb" in tree buffer.
--- User commands: :FiletreeRenameBatch
---
--- NOTE: does not default to "R" -- that's left free for the adapter's own
--- native refresh command (neo-tree's window.mappings default binds "R" to
--- refresh; overriding it here would silently shadow that far more commonly
--- expected action).

local notify = require("filetree.util.notify").create("[filetree.rename_batch]")

local map         = require("filetree.util.map")
local au          = require("filetree.util.autocmd")
local buffer      = require("filetree.util.buffer")
local ui_select   = require("filetree.util.select")
local refs_util   = require("filetree.util.markdown_refs")
local refs_picker = require("filetree.util.refs_picker")

-- Central FS-mutation chokepoint (libuv-based, no shell): retries transient
-- Windows sharing locks. A batch rename touches many watched paths in a row, so
-- it is a prime lock trigger. `watch.release` frees neo-tree's watcher on the
-- source before each retry (no-op unless handle_guard installed the registry).
local fsops = require("lib.nvim.cross.fs.mutate")
local watch = require("lib.nvim.neotree.watch")

local M = {}

---@type FiletreeRenameBatchConfig
local _cfg = {
  enabled             = false,
  keymap              = "<leader>rb",
  confirm             = false,
  use_safety          = true,
  dry_run             = false,
  check_markdown_refs = true,
  refs_picker_prefer  = "auto",
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

-- ── Markdown reference update (post-batch) ──────────────────────────────────────
-- Same soft-dep + chooser UX as trash/smart_rename, but aggregated: refs from
-- every renamed item in the batch are collected first, then offered as ONE
-- chooser instead of one popup per file. Each ref already carries its own
-- `.new_target` (computed against whichever item it was found for), so the
-- "update all" and "inspect" paths both just call refs_util.update() directly.

---@param all_refs table[]  MarkdownFileRef[], each with `.new_target` pre-set.
local function handle_batch_markdown_refs(all_refs)
  if not _cfg.check_markdown_refs or #all_refs == 0 then return end

  local files = refs_util.unique_files(all_refs)
  notify.info(string.format(
    "%d markdown reference(s) found in: %s", #all_refs, table.concat(files, ", ")
  ))

  ui_select(
    {
      "✓  Update all references to their new paths",
      "◐  Inspect references first",
      "✗  Leave references as-is",
    },
    { prompt = string.format(" %d ref(s) across the renamed batch ", #all_refs) },
    function(_, idx)
      if idx == 1 then
        refs_util.update(all_refs)
      elseif idx == 2 then
        refs_picker.pick(
          all_refs,
          { prefer = _cfg.refs_picker_prefer, title = "References across the renamed batch" },
          function(selected) if #selected > 0 then refs_util.update(selected) end end,
          function() end
        )
      end
    end
  )
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

  -- Capture markdown references for every planned source BEFORE renaming,
  -- while the files still exist on disk (so cwd-relative and every other link
  -- style resolve correctly — resolution probes the filesystem). Keyed by plan
  -- index so a source whose rename later fails contributes no stale refs.
  local refs_by_idx = {}
  if _cfg.check_markdown_refs then
    for i, op in ipairs(plan) do
      refs_by_idx[i] = refs_util.find(op.src)
    end
  end

  -- Execute
  local errors    = 0
  local relocated = 0
  local all_refs  = {}
  for i, op in ipairs(plan) do
    local ok, err = fsops.rename_file(op.src, op.dst, {
      on_retry = function() watch.release(op.src) end,
    })
    -- uv.fs_rename cannot cross filesystems/drives (EXDEV, not retried); fall
    -- back to vim.fn.rename, which copies+deletes internally — same guard as
    -- copy_move's do_move.
    if not ok and type(err) == "string" and err:match("^EXDEV") then
      ok = (vim.fn.rename(op.src, op.dst) == 0)
    end
    if not ok then
      notify.error("Failed: " .. op.src .. " → " .. op.dst)
      errors = errors + 1
    else
      -- Repoint any open buffer(s) at the old path (or nested under it, for a
      -- renamed directory) so a stale buffer for the old name doesn't linger
      -- alongside a second, disconnected buffer for the new one.
      relocated = relocated + buffer.relocate(op.src, op.dst)

      for _, r in ipairs(refs_by_idx[i] or {}) do
        r.new_target = refs_util.retarget(r, op.dst)
        all_refs[#all_refs + 1] = r
      end
    end
  end

  local done = #plan - errors
  local msg  = string.format("Renamed %d/%d item(s)", done, #plan)
  if relocated > 0 then
    msg = msg .. string.format(" (%d open buffer(s) repointed)", relocated)
  end
  notify.info(msg)

  handle_batch_markdown_refs(all_refs)

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
