---@module 'filetree.features.trash.undo'
---@brief In-session trash history and restore support.

local notify   = require("filetree.util.notify").create("[filetree.trash.undo]")
local platform = require("filetree.util.platform")

local map = require("filetree.util.map")
local M = {}

local MAX_HISTORY = 50

---@class TrashEntry
---@field original_path string   Where the file/dir was before trashing.
---@field name          string   Filename only.
---@field trashed_at    string   Timestamp string.
---@field platform      string   "windows"|"wsl"|"mac"|"linux"

---@type TrashEntry[]
local _history = {}

---Record a successful trash operation.
---@param original_path string
function M.record(original_path)
  local entry = {
    original_path = original_path,
    name          = vim.fn.fnamemodify(original_path, ":t"),
    trashed_at    = os.date("%Y-%m-%d %H:%M:%S"),
    platform      = require("filetree.util.platform").current(),
  }
  table.insert(_history, 1, entry)
  if #_history > MAX_HISTORY then
    table.remove(_history, MAX_HISTORY + 1)
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
-- Fixed by: (1) matching the specific bin item via the
-- System.Recycle.DeletedFrom extended property (the item's original full
-- path) instead of just its bare filename, so a duplicate-named file trashed
-- earlier can't be restored by mistake; falling back to a name match only if
-- that property lookup is unavailable; and (2) enumerating the item's actual
-- .Verbs() collection and matching the restore verb by a small multi-language
-- caption list (stripping the "&" mnemonic-accelerator marker Windows menu
-- captions carry) instead of assuming the English string, then invoking that
-- verb object's .DoIt() directly. Exit codes are now distinct (0 = restored,
-- 1 = item not found in bin, 2 = found but no restore verb matched), so a
-- real failure is reported honestly instead of silently "succeeding".
local RESTORE_VERB_PATTERN =
  [[^(Restore|Wiederherstellen|Restaurer|Restaurar|Ripristina|Herstellen|Gjenopprett|Återställ|Palauta)$]]

local function restore_windows(name, original_path)
  -- PowerShell single-quoted strings escape an embedded quote by doubling it
  -- ('' not \').
  local win_path = original_path:gsub("/", "\\"):gsub("'", "''")
  local esc_name = name:gsub("'", "''")

  local ps = string.format(
    [[powershell -NoProfile -NonInteractive -Command "]]
    .. [[$sh = New-Object -ComObject Shell.Application; ]]
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
    .. [[$verb = $target.Verbs() | Where-Object { ($_.Name -replace '&','') -match '%s' } | Select-Object -First 1; ]]
    .. [[if (-not $verb) { exit 2 }; ]]
    .. [[$verb.DoIt(); ]]
    .. [[exit 0"]],
    win_path, esc_name, RESTORE_VERB_PATTERN
  )
  local code = os.execute(ps)
  if code == 1 then return false, "Item not found in Recycle Bin (may already be restored, or bin was emptied)" end
  if code == 2 then return false, "Found the item, but no localized \"restore\" verb matched -- restore it manually from the Recycle Bin" end
  if code ~= 0 then return false, "PowerShell restore failed (exit " .. tostring(code) .. ")" end
  return true, nil
end

local function restore_linux_mac(original_path)
  -- gio restore by original path (Linux only; gio encodes original path in .trashinfo)
  if vim.fn.executable("gio") == 1 then
    -- gio restore uses the trash:// URI — we find the .trashinfo file by name
    local name = vim.fn.fnamemodify(original_path, ":t")
    local info_dir = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")) .. "/Trash/info"
    local info_file = info_dir .. "/" .. name .. ".trashinfo"
    if vim.fn.filereadable(info_file) == 1 then
      local code = os.execute("gio trash --restore " .. vim.fn.shellescape("trash:///" .. vim.fn.fnameescape(name)))
      if code == 0 then return true, nil end
    end
    -- Direct restore from files dir
    local trash_files = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")) .. "/Trash/files/" .. name
    if vim.fn.filereadable(trash_files) == 1 or vim.fn.isdirectory(trash_files) == 1 then
      local code = os.execute(string.format("mv %s %s",
        vim.fn.shellescape(trash_files),
        vim.fn.shellescape(original_path)))
      if code == 0 then return true, nil end
    end
  end
  return false, "Could not restore — use your file manager's trash to restore manually"
end

---Restore the last trashed item.
---@return boolean ok
---@return string? err
function M.restore_last()
  local entry = _history[1]
  if not entry then
    return false, "Trash history is empty"
  end
  local ok, err = M.restore(entry)
  if ok then table.remove(_history, 1) end
  return ok, err
end

---Restore a specific history entry.
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
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("bufhidden", "wipe",     { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false,     { buf = buf })
  vim.api.nvim_set_option_value("filetype",  "filetree", { buf = buf })

  local width  = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 6)

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = math.floor((vim.o.lines - height) / 2),
    col      = math.floor((vim.o.columns - width) / 2),
    style    = "minimal",
    border   = "rounded",
    title    = " Trash History ",
    title_pos = "center",
  })

  map("n", "q",     "<cmd>close<cr>", { buffer = buf, silent = true })
  map("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

return M
