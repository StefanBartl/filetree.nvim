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
--- The single-item confirm popup also runs both directions of the reference
--- engine: incoming refs (other files pointing at the one being deleted —
--- offered to mark REF!) and outgoing asset links (files the one being
--- deleted points at, under a configured assets folder — offered for
--- cascade-deletion when nothing else still references them; see
--- docs/ROADMAP/IDEAS/Cascade_Delete_Assets.md). Neither exists for a
--- multi-item "delete all at once" batch, same as before this feature.
---
--- Keymaps (in tree buffer, default):
---   d            Trash current node (or all marked nodes)
---   U            Undo last trash operation
---   <leader>th   Show trash history

local trash_platform = require("filetree.features.fileops.trash.platform")
local undo = require("filetree.features.fileops.trash.undo")
local notify = require("filetree.util.notify").create("[filetree.trash]")

local buffer = require("filetree.util.buffer")
local confirm_choice = require("filetree.util.confirm_choice")
local ui_confirm = require("filetree.util.confirm")
local refs_picker = require("filetree.util.refs_picker")
-- References that would dangle once the file is gone (markdown links only —
-- see refs.for_delete), AND assets the file itself links out to that would be
-- orphaned by its deletion (refs.outgoing_assets — see
-- docs/ROADMAP/IDEAS/Cascade_Delete_Assets.md). This feature decides what to
-- do with both before the delete happens.
local refs = require("filetree.refs")
-- Optional: progress indicator for a multi-item batch (no other feedback
-- otherwise while several files are sent to trash one after another).
-- No-op (returns nil) when lib.nvim isn't installed.
local progress = require("filetree.util.progress")
-- Release neo-tree's directory-watcher handle before the external trash command
-- touches the path. No-op unless the handle_guard feature installed the registry.
local watch = require("lib.nvim.neotree.watch")
local bind = require("filetree.util.bind")

local M = {}

---@type FiletreeTrashConfig
local _cfg = {
  enabled = false,
  -- Deliberately true, unlike copy_move/rename_batch's confirm=false default:
  -- trashing is the one destructive action here whose target files aren't
  -- necessarily what the user thinks they are (mis-clicks on the wrong node,
  -- accidental multi-mark deletes) and it's meaningfully harder to notice/
  -- undo than a move or rename. Override with `confirmations = false` (or
  -- `features.trash.confirm = false`) to opt back out.
  confirm = true,
  use_safety = false,
  dry_run = false,
  -- How many trash operations stay undoable. 0 = unlimited.
  max_history = 50,
  keymap = "d",
  keymap_undo = "U",
  keymap_history = "<leader>th",
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

---Single-item y/N confirm for the SYNCHRONOUS `M.delete(path)` API path only
---(direct/programmatic callers, not the interactive `d` keymap — that goes
---through the nicer async `confirm_popup` below). Deliberately stays on the
---blocking native `vim.fn.confirm` rather than `kit.confirm`: `M.delete`
---returns a boolean synchronously, and kit.confirm is callback-based, so
---switching here would turn `M.delete` async and break its documented
---return contract for any external caller. Same category as the
---`replacer.nvim`/`diff.nvim` kit-migration exceptions — not a quick win.
---@param path string
---@return boolean confirmed
local function confirm(path)
  local answer = vim.fn.confirm("Send to trash?\n  " .. path, "&Yes\n&No", 2)
  return answer == 1
end

---Actually trash one path — NO confirmation (the caller has already handled
---that, at whatever granularity). Sends to trash, records undo, and force-closes
---any open buffer for the file (or, for a directory, nested under it) so a stale
---buffer never lingers pointing at a deleted file. Does NOT refresh the tree;
---callers refresh once after a whole batch.
---@param path string
---@param cb fun(ok: boolean)  invoked on the main loop once the trash attempt settled
---@return nil
local function do_trash(path, cb)
  if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
    notify.warn("path does not exist: " .. path)
    cb(false)
    return
  end

  if _cfg.dry_run then
    notify.info("[dry-run] would trash: " .. path)
    undo.record(path)
    cb(true)
    return
  end

  -- Optional pre-trash backup via safety feature
  if _cfg.use_safety then
    local ok_sf, safety = require("filetree.features").load("safety")
    if ok_sf and safety then pcall(safety.before_delete, path) end
  end

  local function spawn()
    trash_platform.send(path, function(result)
      if not result.ok then
        notify.error("Trash failed: " .. (result.err or "unknown error"))
        cb(false)
        return
      end

      undo.record(path)
      buffer.close_for_path(path) -- close any buffer(s) for the now-deleted file
      cb(true)
    end)
  end

  -- The trash command runs in a SEPARATE process (mv / trash / gio), so unlike
  -- cross.fs.mutate it has no on_retry retry seam. Instead, proactively release
  -- any neo-tree watcher holding `path` (or a subpath) open before spawning it —
  -- otherwise our own libuv handle causes the very Windows sharing violation the
  -- external move would then fail on. libuv closes handles asynchronously, so
  -- give the close a moment to land before the external process runs. This used
  -- to be a blocking `vim.wait(20)`; vim.defer_fn yields to the loop for the
  -- same 20ms without freezing the editor, which is what actually lets the
  -- close callbacks run.
  if watch.release(path) > 0 then
    vim.defer_fn(spawn, 20)
  else
    spawn()
  end
end

---Metadata lines for the confirm popup — reuses node_info's formatter so the
---popup shows the same Path/Size/Modified/Lines info as the `I` keymap.
---@param path string
---@return string[]
local function info_body(path)
  local ok, ni = require("filetree.features").load("node_info")
  if ok and ni and type(ni.info_lines) == "function" then
    local ok2, lines = pcall(ni.info_lines, path)
    if ok2 and type(lines) == "table" and #lines > 0 then return lines end
  end
  return { "  " .. path }
end

---@internal
---Basenames of `assets`, for a notify line — full paths would be noise once
---there is more than one.
---@param assets FiletreeAssetCandidate[]
---@return string[]
local function asset_basenames(assets)
  local out = {}
  for _, c in ipairs(assets) do
    out[#out + 1] = vim.fn.fnamemodify(c.resolved, ":t")
  end
  return out
end

---@internal
---Delete every approved asset through the same trash/undo path as the
---primary file (`do_trash`, defined above) — not a plain `fs_unlink` — so
---`:Filetree trash undo`/`U` can bring an asset back the same way it brings
---back the file that linked to it (Cascade_Delete_Assets.md §8: each asset
---still lands as its OWN undo entry, not grouped with the primary file's —
---undoing the whole batch as one unit is a follow-up, not built here).
---Sequential like `run_all`, for the same reason: parallel trashing would
---race the watcher-release dance `do_trash` does per path.
---@param candidates FiletreeAssetCandidate[]
---@param done fun()
local function delete_assets(candidates, done)
  local i = 0
  local function step()
    i = i + 1
    if i > #candidates then return done() end
    do_trash(candidates[i].resolved, function()
      step()
    end)
  end
  step()
end

---Show the nice info+yes/no popup for a single path. When the file has
---incoming references, outgoing links to now-orphaned assets, or both, a
---chooser replaces the plain yes/no — one dialog for both directions rather
---than two separate popups (Cascade_Delete_Assets.md §4).
---
---Unlike a rename, both scans have to finish *before* the dialog can be
---drawn — its text depends on what was found — so this waits for them
---rather than overlapping either with the delete itself. The two scans
---(incoming refs, outgoing assets) run concurrently with EACH OTHER, since
---neither depends on the other's result.
---@param path string
---@param cb fun(yes: boolean)
local function confirm_popup(path, cb)
  local name = vim.fn.fnamemodify(path, ":t")
  local pending = 2
  ---@type FiletreeRef[]?
  local incoming_refs
  ---@type FiletreeAssetCandidate[]?, FiletreeAssetCandidate[]?
  local deletable_assets, kept_assets

  local function proceed()
    if pending > 0 or not incoming_refs or not deletable_assets then return end

    -- An asset that qualifies (right root, right extension) but is still
    -- linked from some OTHER surviving file is never offered — but the user
    -- should still learn why an apparent orphan wasn't offered, rather than
    -- silently seeing nothing (§3, point 3).
    if #kept_assets > 0 then
      notify.info(
        string.format(
          "%d asset(s) still referenced elsewhere, left alone: %s",
          #kept_assets,
          table.concat(asset_basenames(kept_assets), ", ")
        )
      )
    end

    local has_refs = #incoming_refs > 0
    local has_assets = #deletable_assets > 0

    if not has_refs and not has_assets then
      ui_confirm({
        title = " Trash ",
        body = info_body(path),
        question = "Send to trash?",
        on_choice = cb,
      })
      return
    end

    if has_refs then
      notify.info(
        refs.ui.summary(incoming_refs)
          .. ": "
          .. table.concat(refs.ui.unique_files(incoming_refs), ", ")
      )
    end
    if has_assets then
      notify.info(
        string.format(
          "%d orphaned asset(s) found: %s",
          #deletable_assets,
          table.concat(asset_basenames(deletable_assets), ", ")
        )
      )
    end

    ---@internal
    ---Rewrite `refs_to_apply` (if any), then delete every approved asset (if
    ---any), then hand back. Both happen before `cb(true)`, same reasoning as
    ---the ref-only path this replaces: a cancelled delete must never leave a
    ---half-finished cleanup behind, and the file must still exist while refs
    ---to it are being rewritten.
    ---@param refs_to_apply FiletreeRef[]
    ---@param done fun()
    local function cleanup(refs_to_apply, done)
      local function after_refs()
        if has_assets then
          delete_assets(deletable_assets, done)
        else
          done()
        end
      end
      if #refs_to_apply > 0 then
        refs.apply.run(refs_to_apply, { label = "delete: " .. name }, after_refs)
      else
        after_refs()
      end
    end

    -- `refs.on_delete = "auto"` means "don't ask about the cleanup specifics"
    -- -- not "don't ask about the delete". So the ordinary confirmation still
    -- runs, and the cleanup happens only once it came back yes: a cancelled
    -- delete must not leave blanked-out links or half-deleted assets behind.
    --
    -- refs.on_delete and refs.outgoing_assets.on_delete are independent
    -- switches (step 4's config block) -- a direction that found nothing
    -- (has_refs/has_assets false) never gets a say, and between the two that
    -- did, "ask" from either wins over "auto" from the other: auto-applying
    -- a change the user asked to be asked about is the wrong default to err
    -- toward. A dialog that independently offers/withholds each direction
    -- (rather than "ask" promoting the WHOLE thing to asking) would need two
    -- separate toggles, not one chooser -- a real follow-up, not this step.
    local ref_wants_ask = has_refs and refs.mode("delete") == "ask"
    local asset_wants_ask = has_assets and refs.outgoing_assets_mode() == "ask"
    if not ref_wants_ask and not asset_wants_ask then
      local parts = {}
      if has_refs then
        parts[#parts + 1] = string.format("%d ref(s) will be marked REF!", #incoming_refs)
      end
      if has_assets then
        parts[#parts + 1] = string.format("%d asset(s) will be deleted", #deletable_assets)
      end
      ui_confirm({
        title = " Trash ",
        body = info_body(path),
        question = string.format("Send to trash? (%s)", table.concat(parts, "; ")),
        on_choice = function(yes)
          if yes then
            cleanup(incoming_refs, function()
              cb(true)
            end)
          else
            cb(false)
          end
        end,
      })
      return
    end

    local title_parts = {}
    if has_refs then title_parts[#title_parts + 1] = string.format("%d ref(s)", #incoming_refs) end
    if has_assets then
      title_parts[#title_parts + 1] = string.format("%d asset(s)", #deletable_assets)
    end
    local title = string.format("Trash %s (%s found)", name, table.concat(title_parts, ", "))

    -- Labels adapt to what was actually found, rather than a fixed fifth
    -- branch, so a ref-only or asset-only delete keeps reading exactly like
    -- it did before this feature existed.
    local delete_label = "Delete + remove refs"
    if has_refs and has_assets then
      delete_label = "Delete + clean up refs & assets"
    elseif has_assets then
      delete_label = "Delete + remove assets"
    end
    local keep_label = "Delete, keep refs"
    if has_refs and has_assets then
      keep_label = "Delete, keep refs & assets"
    elseif has_assets then
      keep_label = "Delete, keep assets"
    end

    -- "Inspect first" only ever selects among INCOMING refs (unchanged from
    -- before this feature) — a second, asset-specific picker is a follow-up,
    -- not part of wiring this into the existing dialog. It's left out of the
    -- option list entirely for an asset-only delete, where there is nothing
    -- incoming to inspect.
    local options = { delete_label }
    if has_refs then options[#options + 1] = "Inspect first" end
    options[#options + 1] = keep_label
    options[#options + 1] = "Cancel"

    confirm_choice(title, options, function(choice)
      if choice == delete_label then
        cleanup(incoming_refs, function()
          cb(true)
        end)
      elseif choice == "Inspect first" then
        refs_picker.pick(
          incoming_refs,
          {
            prefer = refs.config().picker,
            title = "References to " .. name .. (has_assets and string.format(
              " (%d asset(s) will also be cleaned up)",
              #deletable_assets
            ) or ""),
          },
          function(selected)
            -- Selecting zero refs to update still cascades the approved
            -- assets: "Inspect first" is selectivity over WHICH refs get
            -- rewritten, not an opt-out of the asset cleanup.
            cleanup(selected, function()
              cb(true)
            end)
          end,
          function()
            confirm_popup(path, cb)
          end -- Esc/cancel -> back to this same chooser
        )
      elseif choice == keep_label then
        cb(true)
      else
        cb(false)
      end
    end)
  end

  refs.for_delete({ path }, nil, function(found)
    incoming_refs = found
    pending = pending - 1
    proceed()
  end)

  refs.outgoing_assets(path, nil, function(candidates)
    deletable_assets, kept_assets = {}, {}
    for _, c in ipairs(candidates) do
      if c.is_asset then
        if c.still_referenced then
          kept_assets[#kept_assets + 1] = c
        else
          deletable_assets[#deletable_assets + 1] = c
        end
      end
    end
    pending = pending - 1
    proceed()
  end)
end

---Finalize a batch: clear marks + refresh the tree once (only when something was
---actually deleted), and report a single summary.
---@param ok_count integer
---@param total integer
---@param cancelled integer
local function finalize(ok_count, total, cancelled)
  if ok_count > 0 then
    local ok_m, marks = require("filetree.features").load("marks")
    if ok_m and marks then pcall(marks.clear_all) end
    if _adapter then pcall(_adapter.refresh) end
  end
  local parts = { string.format("Moved %d/%d to trash", ok_count, total) }
  if cancelled > 0 then parts[#parts + 1] = string.format("(%d skipped)", cancelled) end
  notify.info(table.concat(parts, " "))
end

---Delete every path with no further prompting (the "all" decision).
---@param paths string[]
local function run_all(paths)
  local prog = progress.create({ title = "[filetree.trash]" })
  local ok_count = 0

  -- do_trash() is asynchronous now, so the batch is a chain rather than a
  -- `for` loop: each path starts the next one from its own callback. Strictly
  -- sequential on purpose - trashing in parallel would race the watcher
  -- release/handle-close dance do_trash performs per path, and the progress
  -- indicator would no longer describe one identifiable file.
  local i = 0
  local function step()
    i = i + 1
    if i > #paths then
      if prog then prog:finish(string.format("Moved %d/%d to trash", ok_count, #paths)) end
      finalize(ok_count, #paths, 0)
      return
    end
    if prog then
      prog:update({ text = vim.fn.fnamemodify(paths[i], ":t"), current = i - 1, total = #paths })
    end
    do_trash(paths[i], function(ok)
      if ok then ok_count = ok_count + 1 end
      step()
    end)
  end
  step()
end

---Delete each path after its own info+yes/no popup (the "individual" decision).
---Async, chained one popup at a time so the flow stays modal-feeling.
---@param paths string[]
local function run_individual(paths)
  local prog = progress.create({ title = "[filetree.trash]" })
  local ok_count, cancelled = 0, 0
  local i = 0
  local function step()
    i = i + 1
    if i > #paths then
      if prog then prog:finish(string.format("Moved %d/%d to trash", ok_count, #paths)) end
      finalize(ok_count, #paths, cancelled)
      return
    end
    if prog then
      prog:update({ text = vim.fn.fnamemodify(paths[i], ":t"), current = i - 1, total = #paths })
    end
    confirm_popup(paths[i], function(yes)
      if not yes then
        cancelled = cancelled + 1
        step()
        return
      end
      do_trash(paths[i], function(ok)
        if ok then ok_count = ok_count + 1 end
        step()
      end)
    end)
  end
  step()
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Send the given path to the system trash (single-path API; confirms when the
---feature's `confirm` is on). Kept for direct/programmatic callers and the
---command dispatcher; the interactive `d` keymap goes through delete_current.
---BREAKING (async conversion): this no longer returns the outcome. Trashing
---goes through an external process, which is now spawned asynchronously, so the
---result is only known later - pass `on_done` to observe it.
---@param path string  Absolute path of the file or directory.
---@param on_done fun(ok: boolean)|nil  invoked once the trash attempt settled
---@return nil
function M.delete(path, on_done)
  local function done(ok)
    if on_done then on_done(ok) end
  end

  if not _cfg.enabled then
    notify.warn("trash feature is disabled")
    return done(false)
  end
  if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
    notify.warn("path does not exist: " .. path)
    return done(false)
  end
  if _cfg.confirm and not confirm(path) then return done(false) end
  do_trash(path, function(ok)
    if ok and _adapter then pcall(_adapter.refresh) end
    done(ok)
  end)
end

---Collect the paths to trash: all marked nodes if any are marked, else the
---node under the cursor. Does NOT clear marks (that happens after a successful
---delete, so a cancelled operation leaves the marks intact).
---@return string[]
local function gather_paths()
  local ok_m, marks = require("filetree.features").load("marks")
  if ok_m and marks and marks.count() > 0 then return marks.get_marked() end
  local node = _adapter and _adapter.get_current_node()
  return (node and node.path) and { node.path } or {}
end

---Trash the current node, or all marked nodes if any are marked.
---
--- - `confirm = false`: delete everything straight away, no prompt.
--- - a single item: one info+yes/no popup (util.confirm — a small float with the
---   file's metadata, not the native "more" prompt).
--- - multiple items: one batch chooser (hover_select float) offering
---   "delete all at once", "confirm each individually", or "cancel" — instead
---   of asking once per file. "individual" then shows the info popup per file.
function M.delete_current()
  if not _adapter then return end

  local paths = gather_paths()
  if #paths == 0 then
    notify.warn("No node selected")
    return
  end

  -- No confirmation configured → just delete everything.
  if not _cfg.confirm then
    run_all(paths)
    return
  end

  -- Single item → the nice info+yes/no popup.
  if #paths == 1 then
    confirm_popup(paths[1], function(yes)
      if yes then run_all(paths) end
    end)
    return
  end

  -- Multiple items → one chooser for the whole set (h/l to move, <CR> to
  -- pick, <Esc>/q to cancel).
  confirm_choice(
    string.format("Move %d items to trash", #paths),
    { "Delete all at once", "Confirm individually", "Cancel" },
    function(choice)
      if choice == "Delete all at once" then
        run_all(paths)
      elseif choice == "Confirm individually" then
        run_individual(paths)
      end
      -- "Cancel" or nil (dismissed) → do nothing, marks stay.
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

---@param config FiletreeTrashConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if not trash_platform.available() then
    notify.warn("No trash backend found on this platform. Feature disabled.")
    _cfg.enabled = false
    return
  end

  bind.bind("trash", _cfg, {
    { name = "trash", field = "keymap", rhs = M.delete_current, desc = "trash current node" },
    { name = "undo", field = "keymap_undo", rhs = M.undo_last, desc = "undo last trash" },
    {
      name = "history",
      field = "keymap_history",
      rhs = M.show_history,
      desc = "show trash history",
    },
  })
end

function M.teardown()
  _adapter = nil
  _cfg.enabled = false
end

return M
