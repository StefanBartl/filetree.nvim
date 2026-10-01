-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- file_clipboard.lua — headless tests for `features.system.file_clipboard`:
-- copying the FILES (not their paths as text) to the OS clipboard.
--
-- Two halves:
--   * `backend.build()` is pure, so what each platform's tool is handed -- argv,
--     stdin, environment -- is asserted on every CI OS without spawning
--     anything, including names with a space, `&`, `'`, `$`, `[ ]` and umlauts
--     that must reach the tool as data and never as script text.
--   * the feature's target choice (marks, else the cursor node), its refusals
--     and its messages, against a stubbed backend, a stub adapter and a stub
--     marks module.
--
-- A real Windows round trip (copy, then read the clipboard's file list back)
-- is part of this file but OFF by default, because it overwrites the clipboard
-- of whoever runs it. Opt in with:
--   FILETREE_TEST_REAL_CLIPBOARD=1 nvim -n --clean --headless -u NONE -l TESTS/file_clipboard.lua
--
-- Usage (from the repo root):
--   nvim -n --clean --headless -u NONE -l TESTS/file_clipboard.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)
local lib_candidates = {}
for _, env in ipairs({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" then lib_candidates[#lib_candidates + 1] = v end
end
lib_candidates[#lib_candidates + 1] = vim.fn.fnamemodify(root_dir, ":h") .. "/lib.nvim"
lib_candidates[#lib_candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"
for _, candidate in ipairs(lib_candidates) do
  if vim.fn.isdirectory(candidate .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(candidate)
    break
  end
end

local TMP_ROOT = vim.env.TEMP or vim.env.TMPDIR or vim.env.TMP or "/tmp"

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. (detail and ("  — " .. detail) or ""))
  end
end
local function eq(name, got, want)
  check(name, got == want, ("got %q want %q"):format(tostring(got), tostring(want)))
end

local backend = require("filetree.features.system.file_clipboard.backend")

-- Absolute paths that exist on whichever OS this runs on; the names are the
-- awkward part. `/` spelled, as a tree hands them over.
local base = (TMP_ROOT .. "/ft-clip-" .. tostring(vim.uv.hrtime())):gsub("\\", "/")
local TRICKY = base .. "/Bildschirmfoto Ärger & Öl's [1] $x (2).png"
local PLAIN = base .. "/b.png"
local FOLDER = base .. "/Ordner mit Leerzeichen"

---Every string the command hands the tool as program text: argv, minus the
---paths themselves. A path leaking in here would be interpolated, not passed.
---@param cmd table
---@param needle string
---@return boolean
local function in_argv(cmd, needle)
  for _, a in ipairs(cmd.argv) do
    if a:find(needle, 1, true) then return true end
  end
  return false
end

-- ── normalize ─────────────────────────────────────────────────────────────────
do
  local n = backend.normalize({ PLAIN, PLAIN, "", FOLDER .. "/" }, false)
  eq("normalize: drops duplicates and empty entries", #n, 2)
  eq("normalize: keeps order", n[1], vim.fn.fnamemodify(PLAIN, ":p"):gsub("\\", "/"))
  check("normalize: a directory loses its trailing separator", not n[2]:match("[\\/]$"), n[2])

  local w = backend.normalize({ PLAIN, base .. "/B.PNG" }, true)
  eq("normalize (windows): case-insensitive de-duplication", #w, 1)
  check("normalize (windows): backslashes only", not w[1]:find("/", 1, true), w[1])

  local l = backend.normalize({ PLAIN, base .. "/B.PNG" }, false)
  eq("normalize (posix): paths differing in case stay distinct", #l, 2)

  eq("normalize: nothing in, nothing out", #backend.normalize({}, false), 0)
end

-- ── build: Windows ────────────────────────────────────────────────────────────
do
  local cmd, err = backend.build("windows", { TRICKY, PLAIN, FOLDER })
  check("windows: builds a command", cmd ~= nil, err)
  eq("windows: PowerShell is the tool", cmd.argv[1], "powershell.exe")
  check(
    "windows: no profile, not interactive",
    in_argv(cmd, "-NoProfile") and in_argv(cmd, "-NonInteractive")
  )
  eq("windows: the script is the fixed one", cmd.argv[#cmd.argv], backend.WINDOWS_SCRIPT)
  check(
    "windows: the script uses -LiteralPath (no wildcard expansion of [1])",
    backend.WINDOWS_SCRIPT:find("-LiteralPath", 1, true) ~= nil
  )

  -- The point of the environment variable: nothing a path contains can be
  -- parsed as PowerShell.
  for _, frag in ipairs({ "Bildschirmfoto", "Ärger", "Öl's", "[1]", "$x", "&", "b.png", "Ordner" }) do
    check("windows: argv does not carry the path text " .. frag, not in_argv(cmd, frag))
  end

  local want = {}
  for _, p in ipairs({ TRICKY, PLAIN, FOLDER }) do
    want[#want + 1] = (vim.fn.fnamemodify(p, ":p"):gsub("/", "\\"):gsub("[\\/]+$", ""))
  end
  eq(
    "windows: the paths ride in the environment, backslashed, newline-separated",
    cmd.env[backend.ENV_VAR],
    table.concat(want, "\n")
  )
  check("windows: stderr is captured for the error message", cmd.capture_stderr == true)
  eq("windows: nothing goes to stdin", cmd.stdin, nil)
end

-- ── build: macOS ──────────────────────────────────────────────────────────────
do
  local cmd, err = backend.build("mac", { TRICKY, PLAIN })
  check("mac: builds a command", cmd ~= nil, err)
  eq("mac: osascript is the tool", cmd.argv[1], "osascript")
  eq(
    "mac: the last arguments are the paths, verbatim",
    cmd.argv[#cmd.argv],
    vim.fn.fnamemodify(PLAIN, ":p"):gsub("\\", "/")
  )
  eq("mac: ... in order", cmd.argv[#cmd.argv - 1], vim.fn.fnamemodify(TRICKY, ":p"):gsub("\\", "/"))

  -- Everything after `-e` is AppleScript source; a path there would be code.
  local script_has_path = false
  for i, a in ipairs(cmd.argv) do
    if cmd.argv[i - 1] == "-e" and (a:find("png", 1, true) or a:find(base, 1, true)) then
      script_has_path = true
    end
  end
  check("mac: no path is part of the AppleScript source", not script_has_path)
  check("mac: the script reads its paths from argv", in_argv(cmd, "on run argv"))
end

-- ── build: Linux ──────────────────────────────────────────────────────────────
do
  local function probe(wayland, tools)
    return {
      wayland = wayland,
      has = function(exe)
        return tools[exe] == true
      end,
    }
  end

  local wl =
    backend.build("linux", { TRICKY, PLAIN }, probe(true, { ["wl-copy"] = true, xclip = true }))
  eq("linux/wayland: wl-copy is preferred", wl.argv[1], "wl-copy")
  eq("linux/wayland: as a file list", wl.argv[3], "text/uri-list")

  local x =
    backend.build("linux", { TRICKY, PLAIN }, probe(false, { ["wl-copy"] = true, xclip = true }))
  eq("linux/x11: xclip is preferred without a Wayland session", x.argv[1], "xclip")
  eq("linux/x11: ... writing the clipboard selection", x.argv[3], "clipboard")
  eq("linux/x11: ... as a file list", x.argv[#x.argv], "text/uri-list")
  check(
    "linux/x11: xclip's stderr is not captured (its forked child would hold the pipe)",
    x.capture_stderr == false
  )

  -- The URIs are percent-encoded and CRLF-terminated; decoding gives the paths back.
  check("linux: stdin is CRLF-terminated", x.stdin:sub(-2) == "\r\n")
  local lines = vim.split(x.stdin, "\r\n", { plain = true, trimempty = true })
  eq("linux: one URI per path", #lines, 2)
  check(
    "linux: URIs are file:// URIs",
    lines[1]:sub(1, 7) == "file://" and lines[2]:sub(1, 7) == "file://"
  )
  check("linux: a space is encoded, not raw", not lines[1]:find(" ", 1, true), lines[1])
  eq(
    "linux: the URI decodes back to the path",
    vim.fs.normalize(vim.uri_to_fname(lines[1])),
    vim.fs.normalize(vim.fn.fnamemodify(TRICKY, ":p"))
  )

  local only_wl = backend.build("linux", { PLAIN }, probe(false, { ["wl-copy"] = true }))
  eq("linux: wl-copy alone is used even without a Wayland variable", only_wl.argv[1], "wl-copy")
  local wl_missing = backend.build("linux", { PLAIN }, probe(true, { xclip = true }))
  eq("linux/wayland without wl-copy: falls back to xclip", wl_missing.argv[1], "xclip")

  local none, err = backend.build("linux", { PLAIN }, probe(true, {}))
  eq("linux: no tool, no command", none, nil)
  check(
    "linux: ... and the error names what to install",
    err ~= nil and err:find("xclip", 1, true) ~= nil,
    err
  )
end

-- ── build: refusals ───────────────────────────────────────────────────────────
do
  local wsl, err = backend.build("wsl", { PLAIN })
  eq("wsl: not supported", wsl, nil)
  check("wsl: ... with a reason", err ~= nil and err:find("WSL", 1, true) ~= nil, err)

  local empty, err_empty = backend.build("windows", {})
  eq("an empty list builds nothing", empty, nil)
  eq("... and says so", err_empty, "nothing to copy")
end

-- ── the feature: which paths, which messages ──────────────────────────────────

-- Real files for the existence filter.
vim.fn.mkdir(base, "p")
vim.fn.mkdir(FOLDER, "p")
local function touch(p)
  vim.fn.writefile({ "x" }, p)
  return p
end
local FILE_A = touch(base .. "/a.png")
local FILE_B = touch(base .. "/b.png")
local FILE_C = touch(base .. "/c.png")
local GONE = base .. "/deleted-behind-our-back.png"

---Notifications raised while `fn` runs, as { msg, level }.
---@param fn fun()
---@return table[]
local function capture_notify(fn)
  local seen = {}
  local orig = vim.notify
  vim.notify = function(msg, level)
    seen[#seen + 1] = { msg = msg, level = level }
  end
  local ok, err = pcall(fn)
  vim.notify = orig
  assert(ok, err)
  return seen
end
local function any_msg(seen, needle)
  for _, n in ipairs(seen) do
    if tostring(n.msg):find(needle, 1, true) then return true end
  end
  return false
end

local marked = {}
local marks_cleared = 0
package.loaded["filetree.features.org.marks"] = {
  count = function()
    return #marked
  end,
  get_marked = function()
    return vim.deepcopy(marked)
  end,
  clear_all = function()
    marks_cleared = marks_cleared + 1
  end,
}

local cursor_node = { path = FILE_A }
local adapter = {
  name = "neotree",
  get_current_node = function()
    return cursor_node
  end,
}

local fc = require("filetree.features.system.file_clipboard")
fc.setup({ enabled = true }, adapter)

local sent ---@type string[]|nil
local backend_ok, backend_err = true, nil
local real_copy = backend.copy
backend.copy = function(paths, on_done)
  sent = vim.deepcopy(paths)
  on_done(backend_ok, backend_err, #paths)
end

do
  -- Nothing marked: the node under the cursor.
  sent = nil
  local seen = capture_notify(fc.copy)
  eq("unmarked: the cursor node is copied", sent and sent[1], FILE_A)
  eq("unmarked: ... and only it", sent and #sent, 1)
  check(
    "unmarked: the user is told what was copied",
    any_msg(seen, "Copied 1 file(s)") and any_msg(seen, "a.png")
  )

  -- Marked: the marks, and not the cursor node.
  marked = { FILE_B, FILE_C, FOLDER }
  sent = nil
  seen = capture_notify(fc.copy)
  eq("marked: every mark is copied, directories included", sent and #sent, 3)
  eq("marked: ... in mark order", sent and sent[1], FILE_B)
  check("marked: the cursor node is not added", sent ~= nil and not vim.tbl_contains(sent, FILE_A))
  eq("marked: the marks are left alone for the next action", marks_cleared, 0)
  eq("marked: ... still marked", #marked, 3)
  check("marked: the count in the message is the marks'", any_msg(seen, "Copied 3 file(s)"))

  -- A stale mark is skipped and reported; the rest goes out.
  marked = { FILE_B, GONE }
  sent = nil
  seen = capture_notify(fc.copy)
  eq("stale mark: only the existing path is sent", sent and #sent, 1)
  eq("stale mark: ... the right one", sent and sent[1], FILE_B)
  check("stale mark: skipped with a warning", any_msg(seen, "1 path(s) no longer exist"))

  -- Only stale marks: nothing is attempted.
  marked = { GONE }
  sent = nil
  seen = capture_notify(fc.copy)
  eq("only stale marks: the backend is never called", sent, nil)
  check("only stale marks: the user is told", any_msg(seen, "No existing file to copy"))

  -- No marks and no node under the cursor.
  marked = {}
  cursor_node = nil
  sent = nil
  seen = capture_notify(fc.copy)
  eq("no node: the backend is never called", sent, nil)
  check("no node: the user is told", any_msg(seen, "No current node"))
  cursor_node = { path = FILE_A }

  -- The backend failing is reported with its reason, not as a success.
  backend_ok, backend_err = false, "powershell.exe exited with 1: clipboard is locked"
  seen = capture_notify(fc.copy)
  check("backend failure: the reason is shown", any_msg(seen, "clipboard is locked"))
  check("backend failure: ... and it does not claim success", not any_msg(seen, "Copied"))
  backend_ok, backend_err = true, nil

  -- preview_limit caps the names listed.
  fc.setup({ enabled = true, preview_limit = 2 }, adapter)
  marked = { FILE_A, FILE_B, FILE_C }
  seen = capture_notify(fc.copy)
  check(
    "preview_limit: lists that many names",
    any_msg(seen, "a.png") and any_msg(seen, "b.png") and not any_msg(seen, "c.png")
  )
  check("preview_limit: ... and counts the rest", any_msg(seen, "(1 more)"))
  fc.setup({ enabled = true }, adapter)
  marked = {}

  -- The key is bound as an action of this feature.
  local bind = require("filetree.util.bind")
  eq(
    "keymap: the action's config field is `keymap`",
    bind.field_of("file_clipboard", "copy"),
    "keymap"
  )
end

backend.copy = real_copy

-- ── real round trip (Windows, opt-in) ─────────────────────────────────────────
-- Copy through the real PowerShell, then read the clipboard's FILE LIST back
-- through .NET: what a paste target sees. Overwrites the clipboard.
if vim.fn.has("win32") == 1 and vim.env.FILETREE_TEST_REAL_CLIPBOARD == "1" then
  local result
  backend.copy({ TRICKY, PLAIN, FOLDER, PLAIN }, function(ok, err, count)
    result = { ok = ok, err = err, count = count }
  end)
  vim.wait(20000, function()
    return result ~= nil
  end, 50)
  check(
    "real clipboard: the copy reports success",
    result ~= nil and result.ok,
    result and result.err
  )
  eq("real clipboard: a duplicate collapses (3 distinct paths)", result and result.count, 3)

  local reader = table.concat({
    "[Console]::OutputEncoding = [Text.Encoding]::UTF8",
    "Add-Type -AssemblyName System.Windows.Forms",
    "[System.Windows.Forms.Clipboard]::GetFileDropList() | ForEach-Object { $_ }",
  }, "; ")
  local res = vim
    .system({ "powershell.exe", "-NoProfile", "-STA", "-Command", reader }, { text = true })
    :wait()
  local got = vim.split(vim.trim(res.stdout or ""), "\r?\n")
  local want = {}
  for _, p in ipairs({ TRICKY, PLAIN, FOLDER }) do
    want[#want + 1] = (vim.fn.fnamemodify(p, ":p"):gsub("/", "\\"):gsub("[\\/]+$", ""))
  end
  table.sort(got)
  table.sort(want)
  eq("real clipboard: the file list has the three paths", #got, 3)
  eq(
    "real clipboard: ... exactly, umlauts, quote and brackets intact",
    table.concat(got, "|"),
    table.concat(want, "|")
  )
else
  print(
    "  skip real clipboard round trip (set FILETREE_TEST_REAL_CLIPBOARD=1 on Windows to run it)"
  )
end

vim.fn.delete(base, "rf")

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
