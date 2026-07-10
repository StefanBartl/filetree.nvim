---@module 'filetree.features.trash'
---@brief Send files to system trash with in-session undo support.
---@description
--- Moves the node's file/directory to the system trash (platform-specific) and
--- records it for later restoration. Integrates with the safety feature for
--- optional pre-trash backup.
---
--- Deleting `d` (current node, or all marked nodes if any are marked):
---   - `confirm = false`: deletes everything straight away, no prompt.
---   - a single item: one y/N.
---   - multiple items: ONE batch chooser (via the shared hover_select float)
---     offering "delete all at once" / "confirm each individually" / "cancel",
---     instead of prompting once per file.
--- Every successful delete force-closes any buffer still open for the deleted
--- file (or, for a directory, nested under it) so a stale buffer never lingers
--- pointing at a file that no longer exists (see util.buffer.close_for_path).
---
--- Keymaps (in tree buffer, default):
---   d            Trash current node (or all marked nodes)
---   U            Undo last trash operation
---   <leader>th   Show trash history

local trash_platform = require("filetree.features.fileops.trash.platform")
local undo           = require("filetree.features.fileops.trash.undo")
local notify         = require("filetree.util.notify").create("[filetree.trash]")

local map       = require("filetree.util.map")
local au        = require("filetree.util.autocmd")
local buffer    = require("filetree.util.buffer")
local ui_select = require("filetree.util.select")

local M = {}

---@type FiletreeTrashConfig
local _cfg = {
  enabled        = false,
  -- Deliberately true, unlike copy_move/rename_batch's confirm=false default:
  -- trashing is the one destructive action here whose target files aren't
  -- necessarily what the user thinks they are (mis-clicks on the wrong node,
  -- accidental multi-mark deletes) and it's meaningfully harder to notice/
  -- undo than a move or rename. Override with `confirmations = false` (or
  -- `features.trash.confirm = false`) to opt back out.
  confirm        = true,
  use_safety     = false,
  dry_run        = false,
  keymap         = "d",
  keymap_undo    = "U",
  keymap_history = "<leader>th",
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

---Single-item y/N confirm (used for a single node, and per-item in the batch
---chooser's "individual" mode).
---@param path string
---@return boolean confirmed
local function confirm(path)
  local answer = vim.fn.confirm(
    "Send to trash?\n  " .. path,
    "&Yes\n&No", 2
  )
  return answer == 1
end

---Actually trash one path — NO confirmation (the caller has already handled
---that, at whatever granularity). Sends to trash, records undo, and force-closes
---any open buffer for the file (or, for a directory, nested under it) so a stale
---buffer never lingers pointing at a deleted file. Does NOT refresh the tree;
---callers refresh once after a whole batch.
---@param path string
---@return boolean ok
local function do_trash(path)
  if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
    notify.warn("path does not exist: " .. path)
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
  buffer.close_for_path(path)   -- close any buffer(s) for the now-deleted file
  return true
end

---Run a whole batch of already-decided deletions. In "individual" mode each
---item still gets its own y/N; in "all" mode none do. Clears marks and refreshes
---the tree ONCE at the end (only when something was actually deleted), and
---reports a single summary instead of one message per file.
---@param paths string[]
---@param mode "all"|"individual"
local function run_batch(paths, mode)
  local ok_count, cancelled = 0, 0
  for _, path in ipairs(paths) do
    if mode == "individual" and not confirm(path) then
      cancelled = cancelled + 1
    elseif do_trash(path) then
      ok_count = ok_count + 1
    end
  end

  if ok_count > 0 then
    local ok_m, marks = require("filetree.features").load("marks")
    if ok_m and marks then pcall(marks.clear_all) end
    if _adapter then pcall(_adapter.refresh) end
  end

  local parts = { string.format("Moved %d/%d to trash", ok_count, #paths) }
  if cancelled > 0 then parts[#parts + 1] = string.format("(%d skipped)", cancelled) end
  notify.info(table.concat(parts, " "))
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Send the given path to the system trash (single-path API; confirms when the
---feature's `confirm` is on). Kept for direct/programmatic callers and the
---command dispatcher; the interactive `d` keymap goes through delete_current.
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
  local ok = do_trash(path)
  if ok and _adapter then pcall(_adapter.refresh) end
  return ok
end

---Collect the paths to trash: all marked nodes if any are marked, else the
---node under the cursor. Does NOT clear marks (that happens after a successful
---delete, so a cancelled operation leaves the marks intact).
---@return string[]
local function gather_paths()
  local ok_m, marks = require("filetree.features").load("marks")
  if ok_m and marks and marks.count() > 0 then
    return marks.get_marked()
  end
  local node = _adapter and _adapter.get_current_node()
  return (node and node.path) and { node.path } or {}
end

---Trash the current node, or all marked nodes if any are marked.
---
--- - `confirm = false`: delete everything straight away, no prompt.
--- - a single item: one y/N.
--- - multiple items: one batch chooser (hover_select float) offering
---   "delete all at once", "confirm each individually", or "cancel" — instead
---   of asking once per file.
function M.delete_current()
  if not _adapter then return end

  local paths = gather_paths()
  if #paths == 0 then
    notify.warn("No node selected")
    return
  end

  -- No confirmation configured → just delete everything.
  if not _cfg.confirm then
    run_batch(paths, "all")
    return
  end

  -- Single item → a lightweight y/N (no need for the batch chooser).
  if #paths == 1 then
    if confirm(paths[1]) then
      run_batch(paths, "all")
    end
    return
  end

  -- Multiple items → one chooser for the whole set. It renders as a navigable
  -- hover_select float (j/k or arrows to move, <CR> to pick, <Esc>/q to
  -- cancel). Leading markers use plain dingbats (✓/•/✗) rather than emoji
  -- (some, e.g. 🗑, don't render in every font/terminal) or nerd-font glyphs
  -- (not everyone has them); ✓ is already used by the marks feature, so it's
  -- known-good here.
  ui_select(
    {
      "✓  Delete all at once",
      "•  Confirm each individually",
      "✗  Cancel",
    },
    { prompt = string.format(" Move %d items to trash ", #paths) },
    function(_, idx)
      if idx == 1 then
        run_batch(paths, "all")
      elseif idx == 2 then
        run_batch(paths, "individual")
      end
      -- idx == 3 (Cancel) or nil (dismissed) → do nothing, marks stay.
    end
  )
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
