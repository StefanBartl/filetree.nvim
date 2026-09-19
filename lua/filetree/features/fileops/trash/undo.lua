---@module 'filetree.features.fileops.trash.undo'
---@brief In-session trash history and restore support.
---
--- A delete is not only the file: when it had incoming references, `trash`
--- rewrites those to the provider's broken-link marker (`REF!`) right after
--- the file is gone. Undoing the delete therefore has to undo both halves, so
--- each history entry can carry the refs undo token of its own rewrite
--- (`M.attach_refs`), which `M.restore` reverts once the file is back.

local notify = require("filetree.util.notify").create("[filetree.trash.undo]")
local platform = require("filetree.util.platform")

local kit = require("ui.kit")
local M = {}

---How many trash operations stay undoable.
---
---A preference, not a safety limit: the history is a small JSON file, and
---"how far back do I want to reach" is the user's call. `features.trash.
---max_history`; 0 keeps everything.
---@return integer
local function max_history()
  local ok, ft = pcall(require, "filetree.config")
  if not ok or not ft.get then return 50 end
  local cfg = (ft.get().features or {}).trash or {}
  local n = cfg.max_history
  if type(n) ~= "number" or n < 0 then return 50 end
  return n
end

---@class TrashEntry
---@field original_path string   Where the file/dir was before trashing.
---@field name          string   Filename only.
---@field trashed_at    string   Timestamp string.
---@field platform      string   "windows"|"wsl"|"mac"|"linux"
---@field refs_undo_id  integer? Undo token of the `REF!` rewrite this delete triggered (see `M.attach_refs`).
---@field refs_count    integer? How many references that rewrite touched.

---@type TrashEntry[]
local _history = {}

---Record a successful trash operation.
---@param original_path string
function M.record(original_path)
  local entry = {
    original_path = original_path,
    name = vim.fn.fnamemodify(original_path, ":t"),
    trashed_at = os.date("%Y-%m-%d %H:%M:%S"),
    platform = platform.current(),
  }
  table.insert(_history, 1, entry)
  local cap = max_history()
  if cap > 0 and #_history > cap then table.remove(_history, cap + 1) end
end

---Link the reference rewrite a delete triggered to that delete's history
---entry, so restoring the file also puts the `REF!` markers back.
---
---A separate call rather than an argument to `M.record`, because of the order
---the two happen in: the file is trashed first and only *then* are the now
---dangling references rewritten (a cleanup that must not run ahead of a trash
---that might still fail), so the token does not exist yet when the entry is
---recorded.
---
---Matches the newest entry for `original_path` rather than blindly taking
---`_history[1]`: the cascade may trash orphaned assets right after, and a
---mis-attached token would revert one delete's refs while restoring another's
---file. No matching entry (permanent delete, history trimmed) is a no-op.
---@param original_path string
---@param refs_undo_id integer
---@param refs_count integer
function M.attach_refs(original_path, refs_undo_id, refs_count)
  for _, entry in ipairs(_history) do
    if entry.original_path == original_path then
      entry.refs_undo_id = refs_undo_id
      entry.refs_count = refs_count
      return
    end
  end
end

---Return the full trash history (newest first).
---@return TrashEntry[]
function M.history()
  return vim.deepcopy(_history)
end

---@return TrashEntry?
function M.last()
  return _history[1]
end

-- ── Platform restore ──────────────────────────────────────────────────────────

-- The Recycle Bin's "restore" context-menu verb is a *localized caption*, not
-- a stable canonical name -- InvokeVerb('restore') silently matches nothing
-- (and calls nothing) on any non-English Windows install (e.g. German
-- "Wiederherstellen"), yet the PowerShell script still exits 0 since no
-- terminating error was raised. That made restore_last() report success and
-- drop the history entry despite never actually restoring anything.
--
-- A hardcoded list of translated captions (an earlier version of this fix)
-- only trades "broken on every non-English install" for "broken on every
-- install whose language isn't in the list" -- Windows ships 100+ language
-- packs, and no fixed list ever covers them all.
--
-- The actual fix avoids verb captions entirely: a "restore" is just moving
-- the item's real backing file (Namespace(0xa) is a genuine filesystem
-- folder, so FolderItem.Path is the real, physical "$R…" path inside
-- `$Recycle.Bin\<SID>\`) back to its original location -- a plain
-- Move-Item, which has no locale dependence at all since it never touches a
-- menu/verb of any kind. The bin item itself is still located via the
-- System.Recycle.DeletedFrom extended property (a stable internal property
-- key, not a caption) matching the original full path, rather than just the
-- bare filename, so a duplicate-named file trashed earlier can't get
-- restored by mistake; falling back to a name match only if that property
-- lookup is unavailable. The verb-caption approach is kept as a last-resort
-- fallback only if the direct move itself fails for some reason.
-- Exit codes: 0 = restored, 1 = item not found in bin, 2 = found but neither
-- the move nor the verb fallback worked, 3 = target path already exists
-- (refused, to avoid silently overwriting something now there).
local RESTORE_VERB_PATTERN =
  [[^(Restore|Wiederherstellen|Restaurer|Restaurar|Ripristina|Herstellen|Gjenopprett|Återställ|Palauta)$]]

local function restore_windows(name, original_path)
  -- PowerShell single-quoted strings escape an embedded quote by doubling it
  -- ('' not \').
  local win_path = original_path:gsub("/", "\\"):gsub("'", "''")
  local esc_name = name:gsub("'", "''")

  -- Passed as a single argv element (not a shell command line), so the
  -- outer OS shell never re-parses/re-quotes it.
  local script = string.format(
    [[$sh = New-Object -ComObject Shell.Application; ]]
      .. [[$bin = $sh.Namespace(0xa); ]]
      .. [[$target = $null; ]]
      .. [[foreach ($item in $bin.Items()) { ]]
      .. [[  try { $df = $item.ExtendedProperty('System.Recycle.DeletedFrom') } catch { $df = $null }; ]]
      .. [[  if ($df -and ($df -eq '%s')) { $target = $item; break } ]]
      .. [[}; ]]
      .. [[if (-not $target) { ]]
      .. [[  foreach ($item in $bin.Items()) { if ($item.Name -eq '%s') { $target = $item; break } } ]]
      .. [[}; ]]
      .. [[if (-not $target) { exit 1 }; ]]
      .. [[$dst = '%s'; ]]
      .. [[if (Test-Path -LiteralPath $dst) { exit 3 }; ]]
      .. [[$moved = $false; ]]
      .. [[try { ]]
      .. [[  $src = $target.Path; ]]
      .. [[  $dstDir = Split-Path -Parent $dst; ]]
      .. [[  if ($dstDir -and -not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }; ]]
      .. [[  Move-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop; ]]
      .. [[  $moved = $true ]]
      .. [[} catch { $moved = $false }; ]]
      .. [[if (-not $moved) { ]]
      .. [[  $verb = $target.Verbs() | Where-Object { ($_.Name -replace '&','') -match '%s' } | Select-Object -First 1; ]]
      .. [[  if ($verb) { $verb.DoIt(); $moved = (Test-Path -LiteralPath $dst) } ]]
      .. [[}; ]]
      .. [[if ($moved) { exit 0 } else { exit 2 }]],
    win_path,
    esc_name,
    win_path,
    RESTORE_VERB_PATTERN
  )
  local ok, err = require("lib.nvim.cross.run_argv").run_blocking({
    "powershell",
    "-NoProfile",
    "-NonInteractive",
    "-Command",
    script,
  })
  if ok then return true, nil end
  -- The script has no stderr output of its own, so on failure run_argv's
  -- err is exactly "exit code N" -- recover our script's exit code from it
  -- to keep the specific, actionable messages below.
  local code = tonumber((err or ""):match("exit code (%d+)"))
  if code == 1 then
    return false, "Item not found in Recycle Bin (may already be restored, or bin was emptied)"
  end
  if code == 2 then
    return false,
      "Found the item, but could not move it back (and no restore verb matched either) -- restore it manually from the Recycle Bin"
  end
  if code == 3 then
    return false, "A file already exists at the original location -- not overwriting it"
  end
  return false, "PowerShell restore failed: " .. (err or "unknown error")
end

local function restore_linux_mac(original_path)
  local run_argv = require("lib.nvim.cross.run_argv")
  -- gio restore by original path (Linux only; gio encodes original path in .trashinfo)
  if vim.fn.executable("gio") == 1 then
    -- gio restore uses the trash:// URI — we find the .trashinfo file by name
    local name = vim.fn.fnamemodify(original_path, ":t")
    local info_dir = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")) .. "/Trash/info"
    local info_file = info_dir .. "/" .. name .. ".trashinfo"
    if vim.fn.filereadable(info_file) == 1 then
      local ok = run_argv.run_blocking({
        "gio",
        "trash",
        "--restore",
        "trash:///" .. vim.fn.fnameescape(name),
      })
      if ok then return true, nil end
    end
    -- Direct restore from files dir
    local trash_files = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share"))
      .. "/Trash/files/"
      .. name
    if vim.fn.filereadable(trash_files) == 1 or vim.fn.isdirectory(trash_files) == 1 then
      local ok = run_argv.run_blocking({ "mv", trash_files, original_path })
      if ok then return true, nil end
    end
  end
  return false, "Could not restore — use your file manager's trash to restore manually"
end

---Restore the last trashed item.
---@return boolean ok
---@return string? err
function M.restore_last()
  local entry = _history[1]
  if not entry then return false, "Trash history is empty" end
  local ok, err = M.restore(entry)
  if ok then table.remove(_history, 1) end
  return ok, err
end

---@internal
---Put back the `REF!` markers this delete's cleanup wrote — the mirror of the
---rewrite `trash` ran once the file was gone. Undoing the delete without this
---leaves every referencing file pointing at `REF!` for a file that is back.
---
---Strictly after the file itself is restored, mirroring the delete's own
---order (trash first, refs after), and only for a token that is still on the
---refs undo stack: an already-reverted or trimmed-off token is reported, not
---silently treated as done, since those references stay broken and the user
---has to fix them by hand.
---@param entry TrashEntry
local function restore_refs(entry)
  local id = entry.refs_undo_id
  if not id then return end

  local ok_refs, apply = pcall(require, "filetree.refs.apply")
  if not ok_refs then return end

  if not apply.has_token(id) then
    notify.warn(
      string.format(
        "%d reference(s) marked REF! for this delete could not be restored "
          .. "(already reverted, or dropped from the refs undo history)",
        entry.refs_count or 0
      )
    )
    return
  end

  apply.undo_by_id(id, function(restored, files, _, skipped)
    if restored > 0 then
      local msg = string.format("Restored %d reference line(s) in %d file(s)", restored, files)
      -- Partial restores are the normal outcome once a line was rewritten
      -- again by a LATER operation (one line can hold links to several files):
      -- putting the old target back would undo that newer change too, so the
      -- line is left as it is -- and said so, because it still reads REF!.
      if skipped > 0 then
        notify.warn(msg .. string.format("; %d line(s) changed since, left as-is", skipped))
      else
        notify.info(msg)
      end
    else
      notify.warn("References were not restored (files changed since the delete?)")
    end
  end)
end

---Restore a specific history entry, together with the references that
---delete marked `REF!` (see `M.attach_refs`).
---@param entry TrashEntry
---@return boolean ok
---@return string? err
function M.restore(entry)
  local plat = entry.platform
  local ok, err
  if plat == "windows" or plat == "wsl" then
    ok, err = restore_windows(entry.name, entry.original_path)
  else
    ok, err = restore_linux_mac(entry.original_path)
  end
  if ok then
    notify.info("Restored: " .. entry.original_path)
    -- Only once the file is actually back: reference cleanup follows the file,
    -- never the other way round (a failed restore must not un-break links to
    -- something that is still deleted).
    restore_refs(entry)
  else
    notify.error("Restore failed: " .. (err or "unknown error"))
  end
  return ok, err
end

---Display history in a floating scratch buffer.
function M.show_history()
  if #_history == 0 then
    notify.info("Trash history is empty")
    return
  end

  local lines = { "Trash History (newest first)", string.rep("─", 50) }
  for i, e in ipairs(_history) do
    lines[#lines + 1] = string.format("[%02d] %s  (%s)", i, e.name, e.trashed_at)
    lines[#lines + 1] = "      " .. e.original_path
    if (e.refs_count or 0) > 0 then
      lines[#lines + 1] = string.format("      + %d reference(s) marked REF!", e.refs_count)
    end
  end

  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 6)

  kit.viewer({
    lines = lines,
    title = "Trash History",
    filetype = "filetree",
    width = width,
    height = height,
  })
end

return M
