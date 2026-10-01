---@module 'filetree.features.system.file_clipboard.backend'
---@brief Put files on the OS clipboard as a file list -- what Ctrl+C does in a file manager.
---@description
--- A chat window, a mail client or a file manager that receives Ctrl+V reads
--- the clipboard's FILE LIST, not text. Neovim's `+` register only ever holds
--- text, so this goes through the one tool per platform that can write a file
--- list:
---
---   * Windows  `powershell.exe` + `Set-Clipboard -LiteralPath` (a FileDrop list)
---   * macOS    `osascript`, `set the clipboard to {POSIX file ...}`
---   * Linux    `wl-copy` (Wayland) or `xclip` (X11), MIME `text/uri-list`
---   * WSL      not supported (the Windows clipboard wants Windows paths)
---
--- `build()` is pure: it turns a platform and a list of paths into the command
--- to run, so what is handed to each tool can be asserted without spawning
--- anything. `copy()` is `build()` plus the spawn.
---
--- No path is ever interpolated into a script or a shell string. They travel as
--- argv (macOS), as stdin (Linux) or in an environment variable (Windows),
--- where a name with a quote, `&`, `$`, `[` or an umlaut is just data. The
--- Windows script itself is one fixed string.

local platform = require("filetree.util.platform")

local M = {}

---Environment variable that carries the newline-separated paths to PowerShell.
---A file name cannot contain a newline on Windows, so the split is exact.
M.ENV_VAR = "FILETREE_CLIPBOARD_PATHS"

---How long a spawned tool may take before it is killed and reported (ms). A
---cold `powershell.exe` start can take seconds; a hung one (clipboard owner
---not answering) must not leave `gy` silent forever.
M.TIMEOUT_MS = 15000

---The whole Windows script: no path appears in it. The first statement makes
---PowerShell write stderr as UTF-8 -- a redirected `powershell.exe` otherwise
---uses the OEM codepage, and umlauts in an error message would reach Neovim as
---invalid UTF-8; `try` keeps a host without a console from breaking the script.
---`Stop` makes a failing `Set-Clipboard` (clipboard locked by another process)
---a terminating error, and the `catch` turns it into ONE line on stderr plus
---exit 1: left alone, PowerShell prints a multi-line error record whose message
---it hard-wraps at the console width (mid-path), so a toast built from "the
---first line" would lose the actual reason.
M.WINDOWS_SCRIPT = "try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}; "
  .. "$ErrorActionPreference = 'Stop'; "
  .. "try { Set-Clipboard -LiteralPath ($env:"
  .. M.ENV_VAR
  .. " -split [char]10) } "
  .. "catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }"

---@class FiletreeFileClipboardCmd
---@field argv           string[]
---@field stdin?         string                  Fed to the tool's stdin.
---@field env?           table<string, string>   Added to the inherited environment.
---@field capture_stderr boolean                 false for tools that fork a selection-owning daemon (`xclip`, `wl-copy`): the daemon inherits stderr and keeps the pipe open, so `vim.system` would not call back until the clipboard is taken over.
---@field tool           string                  For messages: what ran.
---@field count          integer                 How many distinct paths the command carries.

---@class FiletreeFileClipboardProbe
---@field has     fun(exe: string): boolean   Is the executable on PATH?
---@field wayland boolean                     Is a Wayland session running?

---@internal
---The probe for the machine this runs on.
---@return FiletreeFileClipboardProbe
local function real_probe()
  return {
    has = platform.has_executable,
    wayland = (vim.env.WAYLAND_DISPLAY or "") ~= "",
  }
end

---Absolute, de-duplicated, in the order given; empty entries dropped. Windows
---gets backslashes (what its clipboard expects); every other platform's paths
---are left as they are -- a backslash is an ordinary file-name character there,
---and rewriting it would put a different file on the clipboard. A directory
---loses its trailing separator.
---@param paths string[]
---@param windows boolean
---@return string[]
function M.normalize(paths, windows)
  local seen, out = {}, {}
  for _, p in ipairs(paths) do
    if type(p) == "string" and p ~= "" then
      local abs = vim.fn.fnamemodify(p, ":p")
      if windows then abs = abs:gsub("/", "\\") end
      -- Keep a bare root ("C:\", "/") intact; strip the separator off the rest.
      if #abs > 1 and not abs:match("^%a:[\\/]?$") then
        abs = abs:gsub(windows and "[\\/]+$" or "/+$", "")
      end
      local key = windows and abs:lower() or abs
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = abs
      end
    end
  end
  return out
end

---The `text/uri-list` body: one `file://` URI per line, CRLF as the format has it.
---`vim.uri_from_fname` does the percent-encoding.
---@param paths string[]
---@return string
local function uri_list(paths)
  local uris = {}
  for i, p in ipairs(paths) do
    uris[i] = vim.uri_from_fname(p)
  end
  return table.concat(uris, "\r\n") .. "\r\n"
end

---The command that puts `paths` on the clipboard as a file list.
---@param plat "windows"|"wsl"|"mac"|"linux"
---@param paths string[]
---@param probe? FiletreeFileClipboardProbe  Defaults to this machine; tests pass a stand-in.
---@return FiletreeFileClipboardCmd? cmd
---@return string? err  Set when `cmd` is nil.
function M.build(plat, paths, probe)
  local list = M.normalize(paths, plat == "windows")
  if #list == 0 then return nil, "nothing to copy" end

  if plat == "windows" then
    return {
      argv = {
        "powershell.exe",
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        M.WINDOWS_SCRIPT,
      },
      env = { [M.ENV_VAR] = table.concat(list, "\n") },
      capture_stderr = true,
      tool = "PowerShell Set-Clipboard",
      count = #list,
    }
  end

  if plat == "mac" then
    local argv = {
      "osascript",
      "-e",
      "on run argv",
      "-e",
      "set l to {}",
      "-e",
      "repeat with p in argv",
      "-e",
      "set end of l to (POSIX file (contents of p))",
      "-e",
      "end repeat",
      "-e",
      "set the clipboard to l",
      "-e",
      "end run",
    }
    vim.list_extend(argv, list)
    return { argv = argv, capture_stderr = true, tool = "osascript", count = #list }
  end

  if plat == "linux" then
    probe = probe or real_probe()
    local body = uri_list(list)
    local wl_copy = {
      argv = { "wl-copy", "--type", "text/uri-list" },
      stdin = body,
      -- wl-copy forks a daemon that owns the selection and inherits stderr.
      capture_stderr = false,
      tool = "wl-copy",
      count = #list,
    }
    if probe.wayland and probe.has("wl-copy") then return wl_copy end
    if probe.has("xclip") then
      return {
        argv = { "xclip", "-selection", "clipboard", "-t", "text/uri-list" },
        stdin = body,
        capture_stderr = false,
        tool = "xclip",
        count = #list,
      }
    end
    if probe.has("wl-copy") then return wl_copy end
    return nil, "needs wl-copy (Wayland) or xclip (X11) on PATH"
  end

  return nil, "copying files to the clipboard is not supported on WSL"
end

---Windows PowerShell by absolute path under `%SystemRoot%`, or nil when it is
---not there. Never a bare name and no `exepath()` fallback: with
---`NoDefaultCurrentDirectoryInExePath` unset (the Windows default) the lookup
---tries the CURRENT DIRECTORY first, so a cloned repo that ships its own
---`powershell.exe` would run instead, with the user's rights. No `windir`
---fallback either: a child started without `SystemRoot` in its environment
---cannot run PowerShell (it dies with a UTF-16 loader error), so a clean "not
---found" is the better answer.
---@return string?
function M.windows_powershell()
  local root = vim.env.SystemRoot
  if not root or root == "" then return nil end
  local exe = root .. "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
  return (vim.uv or vim.loop).fs_stat(exe) and exe or nil
end

---The part of a failing tool's stderr worth a notification: its first line,
---capped. A tool may print a multi-line error record (the Windows script
---above prints one line); the full text goes to the caller separately, for the
---debug log.
---
---NULs are dropped before anything else: a Lua string with a NUL reaches
---Vimscript as a Blob, so `strchars()` would throw E976 inside the scheduled
---callback and `on_done` would never run -- no toast at all. A tool that writes
---UTF-16 (powershell.exe's loader errors) is NUL-interleaved ASCII, which this
---also turns into readable text.
---@param stderr string?
---@return string first, string raw
local function first_line(stderr)
  local raw = vim.trim(stderr or "")
  local first = (raw:match("[^\r\n]+") or ""):gsub("%z", "")
  if vim.fn.strchars(first) > 300 then first = vim.fn.strcharpart(first, 0, 300) .. "…" end
  return first, raw
end

---Run a built command. `on_done` is called on the main loop, never from a
---libuv callback; `raw` is the tool's complete stderr, for a debug log.
---@param cmd FiletreeFileClipboardCmd
---@param on_done fun(ok: boolean, err: string?, raw: string?)
function M.run(cmd, on_done)
  local argv = cmd.argv
  if argv[1] == "powershell.exe" and platform.is_windows() then
    local exe = M.windows_powershell()
    if not exe then
      vim.schedule(function()
        on_done(
          false,
          ("%s could not be started: Windows PowerShell not found under %%SystemRoot%%"):format(
            cmd.tool
          )
        )
      end)
      return
    end
    argv = vim.list_extend({ exe }, argv, 2)
  end

  local ok, err = pcall(vim.system, argv, {
    stdin = cmd.stdin,
    env = cmd.env,
    text = true,
    stdout = false,
    stderr = cmd.capture_stderr or false,
    timeout = M.TIMEOUT_MS,
  }, function(res)
    vim.schedule(function()
      -- libuv reports a death by signal as exit status 0 plus a term signal.
      local signal = res.signal or 0
      if res.code == 0 and signal == 0 then
        on_done(true, nil)
        return
      end
      local first, raw = first_line(res.stderr)
      local how
      if res.code == 124 then
        how = ("timed out after %d s"):format(M.TIMEOUT_MS / 1000)
      elseif signal ~= 0 then
        how = ("was killed by signal %d"):format(signal)
      else
        how = ("exited with %d"):format(res.code)
      end
      on_done(false, ("%s %s%s"):format(cmd.tool, how, first ~= "" and (": " .. first) or ""), raw)
    end)
  end)
  -- A missing executable throws out of vim.system itself, before any callback.
  if not ok then
    vim.schedule(function()
      on_done(false, ("%s could not be started: %s"):format(cmd.tool, tostring(err)))
    end)
  end
end

---Put `paths` on the clipboard as a file list.
---@param paths string[]
---@param on_done fun(ok: boolean, err: string?, count: integer, raw: string?)  `count` is how many distinct paths went out; `raw` the tool's full stderr on failure.
function M.copy(paths, on_done)
  local cmd, err = M.build(platform.current(), paths)
  if not cmd then
    vim.schedule(function()
      on_done(false, err, 0)
    end)
    return
  end
  M.run(cmd, function(ok, run_err, raw)
    on_done(ok, run_err, ok and cmd.count or 0, raw)
  end)
end

return M
