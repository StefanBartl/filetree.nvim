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

---The whole Windows script: no path appears in it. `Stop` makes a failing
---`Set-Clipboard` (clipboard locked by another process) a non-zero exit instead
---of a silent success.
M.WINDOWS_SCRIPT = "$ErrorActionPreference = 'Stop'; Set-Clipboard -LiteralPath ($env:"
  .. M.ENV_VAR
  .. " -split [char]10)"

---@class FiletreeFileClipboardCmd
---@field argv           string[]
---@field stdin?         string                  Fed to the tool's stdin.
---@field env?           table<string, string>   Added to the inherited environment.
---@field capture_stderr boolean                 false for `xclip`, which keeps the selection alive in a forked child holding the pipe open.
---@field tool           string                  For messages: what ran.

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
---gets backslashes (what its clipboard expects), everything else forward ones.
---A directory loses its trailing separator.
---@param paths string[]
---@param windows boolean
---@return string[]
function M.normalize(paths, windows)
  local seen, out = {}, {}
  for _, p in ipairs(paths) do
    if type(p) == "string" and p ~= "" then
      local abs = vim.fn.fnamemodify(p, ":p")
      abs = windows and abs:gsub("/", "\\") or abs:gsub("\\", "/")
      -- Keep a bare root ("C:\", "/") intact; strip the separator off the rest.
      if #abs > 1 and not abs:match("^%a:[\\/]?$") then abs = abs:gsub("[\\/]+$", "") end
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
    return { argv = argv, capture_stderr = true, tool = "osascript" }
  end

  if plat == "linux" then
    probe = probe or real_probe()
    local body = uri_list(list)
    if probe.wayland and probe.has("wl-copy") then
      return {
        argv = { "wl-copy", "--type", "text/uri-list" },
        stdin = body,
        capture_stderr = true,
        tool = "wl-copy",
      }
    end
    if probe.has("xclip") then
      return {
        argv = { "xclip", "-selection", "clipboard", "-t", "text/uri-list" },
        stdin = body,
        capture_stderr = false,
        tool = "xclip",
      }
    end
    if probe.has("wl-copy") then
      return {
        argv = { "wl-copy", "--type", "text/uri-list" },
        stdin = body,
        capture_stderr = true,
        tool = "wl-copy",
      }
    end
    return nil, "needs wl-copy (Wayland) or xclip (X11) on PATH"
  end

  return nil, "copying files to the clipboard is not supported on WSL"
end

---Run a built command. `on_done` is called on the main loop, never from a
---libuv callback.
---@param cmd FiletreeFileClipboardCmd
---@param on_done fun(ok: boolean, err: string?)
function M.run(cmd, on_done)
  local ok, err = pcall(vim.system, cmd.argv, {
    stdin = cmd.stdin,
    env = cmd.env,
    text = true,
    stdout = false,
    stderr = cmd.capture_stderr or false,
  }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        on_done(true, nil)
        return
      end
      local detail = vim.trim(res.stderr or "")
      on_done(
        false,
        ("%s exited with %d%s"):format(cmd.tool, res.code, detail ~= "" and (": " .. detail) or "")
      )
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
---@param on_done fun(ok: boolean, err: string?, count: integer)  `count` is how many distinct paths went out.
function M.copy(paths, on_done)
  local plat = platform.current()
  local cmd, err = M.build(plat, paths)
  if not cmd then
    vim.schedule(function()
      on_done(false, err, 0)
    end)
    return
  end
  local count = #M.normalize(paths, plat == "windows")
  M.run(cmd, function(ok, run_err)
    on_done(ok, run_err, ok and count or 0)
  end)
end

return M
