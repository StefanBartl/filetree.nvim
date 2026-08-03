---@module 'filetree.features.open_in_fm.reuse_win'
---@brief Windows only: reuse an already-open Explorer window instead of
---spawning another one.
---@description
--- Explorer's tab feature (Windows 11 22H2+) has no public scripting API to
--- add a tab to an EXISTING window from an outside process — there is no
--- documented COM or CLI hook for it. What IS reliably scriptable (classic
--- `Shell.Application` COM automation, unchanged since Windows XP) is
--- enumerating open Explorer folder windows and calling `.Navigate2(path)`
--- on one of them. That's the trade-off `reuse_existing` makes: fewer stray
--- windows, at the cost of replacing whatever the reused window was showing
--- rather than adding a tab alongside it.
---
--- Runs via a synchronous PowerShell shell-out (`vim.system(...):wait()`),
--- which is why this is opt-in rather than default-on: a cold PowerShell
--- start typically costs 100-300ms, added to every open_in_fm invocation.
---
--- Not exercised against a live Explorer instance by whoever wrote this —
--- verify it actually reuses a window before relying on it day to day.

local M = {}

---Build the PowerShell script that finds an existing Explorer folder window
---and navigates it to `win_dir`, or exits non-zero if none was found.
---Bringing the reused window to the foreground is best-effort (wrapped in
---its own try/catch): a failure there must never turn a successful
---Navigate2 into a reported failure.
---@param win_dir string  Absolute, backslash-separated Windows path.
---@return string
function M.build_script(win_dir)
  local escaped = win_dir:gsub("'", "''")
  return table.concat({
    "$shell = New-Object -ComObject Shell.Application;",
    "$win = $shell.Windows() | Where-Object { $_.Document -and $_.Document.Folder } | Select-Object -First 1;",
    "if ($null -eq $win) { exit 1 }",
    "$win.Navigate2('" .. escaped .. "');",
    "try {",
    "  Add-Type -Name Win32 -Namespace FiletreeOpenInFm",
    "    -MemberDefinition '[DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr hWnd);'",
    "    -ErrorAction SilentlyContinue;",
    "  [FiletreeOpenInFm.Win32]::SetForegroundWindow([IntPtr]$win.HWND) | Out-Null;",
    "} catch {}",
    "exit 0",
  }, " ")
end

---Try to reuse an already-open Explorer window for `dir`.
---@param dir string  Absolute directory path (either separator).
---@param dbg fun(msg: string)?  Optional debug logger (see open_in_fm's own).
---@return boolean reused
function M.try(dir, dbg)
  dbg = dbg or function() end
  local win_dir = (dir:gsub("/", "\\"))
  local script = M.build_script(win_dir)

  dbg("reuse_win: querying for an existing Explorer window")
  local ok, result = pcall(function()
    return vim.system(
      { "powershell", "-NoProfile", "-NonInteractive", "-Command", script },
      { text = true }
    ):wait(2000)
  end)

  if not ok then
    dbg("reuse_win: vim.system failed: " .. tostring(result))
    return false
  end
  if not result or result.code ~= 0 then
    dbg("reuse_win: no existing Explorer window found or reuse failed (code="
      .. tostring(result and result.code) .. ")")
    return false
  end

  dbg("reuse_win: navigated an existing Explorer window")
  return true
end

return M
