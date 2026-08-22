---@module 'filetree.features.trash.platform'
---@brief Platform-specific "send to trash" implementations.

local platform = require("filetree.util.platform")

local M = {}

---@alias TrashResult { ok: boolean, err: string? }

---@internal
---Run `argv` without blocking the UI thread and hand the outcome to `cb`.
---
---Every backend below used to go through `lib.nvim.cross.run_argv.run_blocking`
---(and, for the AppleScript fallback, `os.execute`), all of which block the
---editor until the external process exits. On Windows that process is
---PowerShell, whose startup alone costs several hundred milliseconds -- so
---every single `d` in the tree froze Neovim, multiplied by the number of
---marked nodes in a batch. vim.system() reports back via callback instead.
---@param argv string[]
---@param err_msg string  message for a non-zero exit
---@param cb fun(result: TrashResult)
local function run(argv, err_msg, cb)
  if not vim.system then
    -- Neovim < 0.10: no async process API. Keep the old blocking behaviour
    -- rather than failing outright.
    local ok = require("lib.nvim.cross.run_argv").run_blocking(argv)
    cb({ ok = ok, err = not ok and err_msg or nil })
    return
  end

  vim.system(argv, { text = true }, function(res)
    -- vim.system callbacks run off the main loop; every caller of `cb` goes on
    -- to touch buffers, notify and the tree adapter.
    vim.schedule(function()
      cb({ ok = res.code == 0, err = res.code ~= 0 and err_msg or nil })
    end)
  end)
end

-- ── Windows ───────────────────────────────────────────────────────────────────

---@param path string
---@param cb fun(result: TrashResult)
local function trash_windows(path, cb)
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
  run(
    { "powershell", "-NoProfile", "-NonInteractive", "-Command", script },
    "PowerShell trash failed",
    cb
  )
end

-- ── macOS ─────────────────────────────────────────────────────────────────────

---@param path string
---@param cb fun(result: TrashResult)
local function trash_mac(path, cb)
  -- `trash` CLI (brew install trash) preferred; AppleScript fallback
  if vim.fn.executable("trash") == 1 then
    run({ "trash", path }, "trash CLI failed", cb)
    return
  end
  -- AppleScript fallback. This used to be an os.execute() shell string; as an
  -- argv list osascript gets the script as one argument and no shell is
  -- involved, so the path no longer has to survive shell quoting.
  run(
    { "osascript", "-e", string.format('tell app "Finder" to delete POSIX file "%s"', path:gsub('"', '\\"')) },
    "AppleScript trash failed",
    cb
  )
end

-- ── Linux ─────────────────────────────────────────────────────────────────────

---@param path string
---@param cb fun(result: TrashResult)
local function trash_linux(path, cb)
  -- Prefer gio (most widely available on modern desktops)
  if vim.fn.executable("gio") == 1 then
    run({ "gio", "trash", path }, "gio trash failed", cb)
    return
  end
  -- trash-cli fallback
  if vim.fn.executable("trash-put") == 1 then
    run({ "trash-put", path }, "trash-put failed", cb)
    return
  end
  -- Manual: move to XDG Trash
  local trash_dir = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")) .. "/Trash/files"
  if vim.fn.isdirectory(trash_dir) == 0 then
    vim.fn.mkdir(trash_dir, "p")
  end
  local base = vim.fn.fnamemodify(path, ":t")
  local dst  = trash_dir .. "/" .. base
  run({ "mv", path, dst }, "mv to XDG Trash failed", cb)
end

-- ── WSL ───────────────────────────────────────────────────────────────────────

---@param path string
---@param cb fun(result: TrashResult)
local function trash_wsl(path, cb)
  -- Convert to Windows path and use PowerShell Recycle Bin. Two chained
  -- spawns; both used to block.
  if not vim.system then
    local win_path = vim.fn.system({ "wslpath", "-w", path }):gsub("\n", "")
    if win_path == "" then
      cb({ ok = false, err = "wslpath conversion failed for: " .. path })
      return
    end
    trash_windows(win_path, cb)
    return
  end

  vim.system({ "wslpath", "-w", path }, { text = true }, function(res)
    local win_path = (res.stdout or ""):gsub("[\r\n]", "")
    vim.schedule(function()
      if res.code ~= 0 or win_path == "" then
        cb({ ok = false, err = "wslpath conversion failed for: " .. path })
        return
      end
      trash_windows(win_path, cb)
    end)
  end)
end

-- ── Dispatch ──────────────────────────────────────────────────────────────────

---Send a file or directory to the system trash.
---
---Asynchronous: the result arrives through `cb`, never as a return value.
---@param path string  Absolute path.
---@param cb fun(result: TrashResult)
---@return nil
function M.send(path, cb)
  if platform.is_wsl()     then return trash_wsl(path, cb)     end
  if platform.is_windows() then return trash_windows(path, cb) end
  if platform.is_mac()     then return trash_mac(path, cb)     end
  return trash_linux(path, cb)
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
