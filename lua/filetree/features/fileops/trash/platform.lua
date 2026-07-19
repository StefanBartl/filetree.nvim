---@module 'filetree.features.trash.platform'
---@brief Platform-specific "send to trash" implementations.

local notify   = require("filetree.util.notify").create("[filetree.trash.platform]")
local platform = require("filetree.util.platform")

local M = {}

---@alias TrashResult { ok: boolean, err: string? }

-- ── Windows ───────────────────────────────────────────────────────────────────

local function trash_windows(path)
  -- Shell.Application's ParseName resolves paths against the shell namespace,
  -- which needs native backslash separators — a forward-slash path (the form
  -- Neovim usually hands us) yields $null and the item is never trashed. And
  -- PowerShell single-quoted strings escape an embedded quote by doubling it
  -- ('' not \'), so a path containing ' breaks the script otherwise. Both are
  -- handled the same way in trash/undo.lua's restore_windows.
  local win_path = path:gsub("/", "\\"):gsub("'", "''")

  -- Shell.Application COM via PowerShell — moves item to Recycle Bin.
  -- Passed as a single argv element (not a shell command line), so the
  -- outer OS shell never re-parses/re-quotes it.
  local script = string.format(
    "$sh = New-Object -ComObject Shell.Application; "
    .. "$item = $sh.Namespace(0).ParseName('%s'); "
    .. "if ($item) { $item.InvokeVerb('delete') } "
    .. "else { exit 1 }",
    win_path
  )
  local ok = require("lib.nvim.cross.run_argv").run_blocking(
    { "powershell", "-NoProfile", "-NonInteractive", "-Command", script }
  )
  return { ok = ok, err = not ok and "PowerShell trash failed" or nil }
end

-- ── macOS ─────────────────────────────────────────────────────────────────────

local function trash_mac(path)
  -- `trash` CLI (brew install trash) preferred; AppleScript fallback
  if vim.fn.executable("trash") == 1 then
    local ok = require("lib.nvim.cross.run_argv").run_blocking({ "trash", path })
    return { ok = ok, err = not ok and "trash CLI failed" or nil }
  end
  -- AppleScript fallback
  local script = string.format(
    'osascript -e \'tell app "Finder" to delete POSIX file "%s"\'',
    path:gsub('"', '\\"')
  )
  local code = os.execute(script)
  return { ok = code == 0, err = code ~= 0 and "AppleScript trash failed" or nil }
end

-- ── Linux ─────────────────────────────────────────────────────────────────────

local function trash_linux(path)
  local run_argv = require("lib.nvim.cross.run_argv")
  -- Prefer gio (most widely available on modern desktops)
  if vim.fn.executable("gio") == 1 then
    local ok = run_argv.run_blocking({ "gio", "trash", path })
    return { ok = ok, err = not ok and "gio trash failed" or nil }
  end
  -- trash-cli fallback
  if vim.fn.executable("trash-put") == 1 then
    local ok = run_argv.run_blocking({ "trash-put", path })
    return { ok = ok, err = not ok and "trash-put failed" or nil }
  end
  -- Manual: move to XDG Trash
  local trash_dir = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")) .. "/Trash/files"
  if vim.fn.isdirectory(trash_dir) == 0 then
    vim.fn.mkdir(trash_dir, "p")
  end
  local base = vim.fn.fnamemodify(path, ":t")
  local dst  = trash_dir .. "/" .. base
  local ok = run_argv.run_blocking({ "mv", path, dst })
  return { ok = ok, err = not ok and "mv to XDG Trash failed" or nil }
end

-- ── WSL ───────────────────────────────────────────────────────────────────────

local function trash_wsl(path)
  -- Convert to Windows path and use PowerShell Recycle Bin
  local win_path = vim.fn.system({ "wslpath", "-w", path }):gsub("\n", "")
  if win_path == "" then
    return { ok = false, err = "wslpath conversion failed for: " .. path }
  end
  return trash_windows(win_path)
end

-- ── Dispatch ──────────────────────────────────────────────────────────────────

---Send a file or directory to the system trash.
---@param path string  Absolute path.
---@return TrashResult
function M.send(path)
  if platform.is_wsl()     then return trash_wsl(path)     end
  if platform.is_windows() then return trash_windows(path)  end
  if platform.is_mac()     then return trash_mac(path)      end
  return trash_linux(path)
end

---Return true when a trash CLI is available on the current platform.
---@return boolean
function M.available()
  if platform.is_windows() or platform.is_wsl() or platform.is_mac() then return true end
  return vim.fn.executable("gio") == 1
    or vim.fn.executable("trash-put") == 1
    or vim.fn.executable("trash") == 1
end

---Return a short description of the platform's trash backend.
---@return string
function M.backend_name()
  if platform.is_wsl()     then return "PowerShell Recycle Bin (via WSL)" end
  if platform.is_windows() then return "PowerShell Recycle Bin" end
  if platform.is_mac()     then return vim.fn.executable("trash") == 1 and "trash CLI" or "AppleScript Finder" end
  if vim.fn.executable("gio") == 1       then return "gio" end
  if vim.fn.executable("trash-put") == 1 then return "trash-cli" end
  return "XDG Trash (mv)"
end

return M
