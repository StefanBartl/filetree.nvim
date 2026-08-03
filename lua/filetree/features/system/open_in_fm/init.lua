---@module 'filetree.features.open_in_fm'
---@brief Open the node under cursor in the system file manager.
---@description
--- Binds a key (default `<leader>fm`) in the tree buffer.  On activation it
--- resolves the directory of the node under the cursor and opens it in the
--- platform's native file manager:
---
---   Windows  → explorer.exe
---   macOS    → open -R  (reveals the file in Finder)
---   Linux    → xdg-open (Nautilus, Thunar, Dolphin, …)
---
--- Uses Neovim's built-in `vim.ui.open` (0.10+) by default — the platform-correct,
--- maintained way to hand a path to the OS (explorer on Windows, open on macOS,
--- xdg-open on Linux, wslview under WSL). Falls back to a manual per-platform
--- spawn on older Neovim, and honours a `command` override.
---
--- Config:
---   enabled        boolean
---   keymap         string?    Key in tree buffer (default "<leader>fm").
---   command        string?    Override the launcher. The directory path is passed as
---                             the last argument (e.g. "nautilus", "thunar").
---   debug          boolean?   Verbose notify.debug() logging of every launch attempt
---                             (branch taken, argv, job id, exit code/stderr). Default
---                             false — this feature previously had NO diagnostics at
---                             all, which is why an intermittent failure looked like
---                             it had "no pattern": every path here only ever checked
---                             that a process STARTED, never that it actually
---                             succeeded, so a transient OS-side failure (Explorer's
---                             COM server busy, a slow/locked network path, a
---                             misconfigured xdg-open handler) was invisible.
---   reuse_existing boolean?   Windows only. Before opening a new Explorer window,
---                             check whether one is already open and navigate IT to
---                             the target path instead. See reuse_win.lua for why
---                             this reuses a window rather than adding a literal new
---                             tab (Explorer's own tab feature has no scripting
---                             hook), and its real latency cost. Default false.

local notify   = require("filetree.util.notify").create("[filetree.open_in_fm]")
local platform = require("filetree.util.platform")
local path     = require("filetree.util.path")
local map      = require("filetree.util.map")
local tree_attach = require("filetree.util.tree_attach")

local M = {}

---@type boolean
local _debug = false

---@param msg string
local function dbg(msg)
  if _debug then notify.debug(msg) end
end

-- ── Launch ────────────────────────────────────────────────────────────────────

---Spawn a detached process; returns true when the job started.
---
---NOTE on what "true" actually means: only that `jobstart` accepted the argv
---and returned a positive job id, i.e. the OS agreed to fork/exec something.
---It says nothing about whether that process went on to actually open a file
---manager window — with `_debug` off, an `on_exit`/`on_stderr` handler isn't
---even attached, so a nonzero exit or stderr output is invisible by design
---(matches the previous zero-overhead behavior). Turn `debug = true` on to
---see the real outcome.
---@param args string[]
---@return boolean
local function spawn(args)
  dbg("spawn: " .. table.concat(args, " "))

  local opts = { detach = true }
  if _debug then
    opts.on_exit = function(_, code)
      dbg(("spawn exited: code=%d  args=%s"):format(code, table.concat(args, " ")))
    end
    opts.on_stderr = function(_, data)
      local text = data and table.concat(data, "\n") or ""
      if text ~= "" then dbg("spawn stderr: " .. text) end
    end
  end

  local id = vim.fn.jobstart(args, opts)
  if not id or id <= 0 then
    notify.warn("Failed to launch: " .. table.concat(args, " "))
    return false
  end
  dbg("spawn started: job id=" .. tostring(id))
  return true
end

---Manual per-platform folder open (fallback for Neovim < 0.10).
---@param dir string
---@return boolean
local function manual_open(dir)
  if platform.is_windows() then
    dbg("manual_open: windows -> explorer")
    return spawn({ "explorer", (dir:gsub("/", "\\")) })
  elseif platform.is_mac() then
    dbg("manual_open: mac -> open")
    return spawn({ "open", dir })
  elseif platform.has_executable("wslview") then
    dbg("manual_open: wsl -> wslview")
    return spawn({ "wslview", dir })
  else
    dbg("manual_open: linux -> xdg-open")
    return spawn({ "xdg-open", dir })
  end
end

---@type boolean
local _reuse_existing = false

---Open `dir` in the system file manager. Prefers `vim.ui.open`.
---@param dir string  Absolute directory path.
---@param override string?  Explicit launcher command, if configured.
local function launch(dir, override)
  if override and override ~= "" then
    dbg("launch: command override -> " .. override)
    spawn({ override, dir })
    return
  end

  if _reuse_existing and platform.is_windows() then
    local ok_req, reuse_win = pcall(require, "filetree.features.system.open_in_fm.reuse_win")
    if ok_req and reuse_win.try(dir, dbg) then
      dbg("launch: reused an existing Explorer window, done")
      return
    end
    dbg("launch: no existing Explorer window reused, opening a new one")
  end

  if type(vim.ui.open) == "function" then
    dbg("launch: trying vim.ui.open")
    -- vim.ui.open returns (SystemObj|nil, err|nil); a non-nil object = spawned.
    local ok, obj = pcall(vim.ui.open, dir)
    if ok and obj ~= nil then
      dbg("launch: vim.ui.open returned an object (assumed spawned; see module doc)")
      return
    end
    dbg("launch: vim.ui.open unavailable or failed, falling back to manual_open")
  end

  manual_open(dir)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type FiletreeAdapter?
local _adapter = nil
---@type string?
local _cmd = nil

---Open the directory of the node under the cursor in the system file manager.
function M.open()
  local adapter = _adapter
  if not adapter then
    notify.warn("open_in_fm: no adapter")
    return
  end
  local node = adapter.get_current_node and adapter.get_current_node()
  if not node or not node.path or node.path == "" then
    notify.warn("No node under cursor")
    return
  end

  local dir = path.ensure_dir(node.path)
  if not dir or dir == "" then
    notify.warn("Cannot resolve directory for node")
    return
  end

  notify.info("Opening in file manager: " .. dir)
  dbg("open(): resolved dir=" .. dir)
  launch(dir, _cmd)
end

---@param config FiletreeOpenInFmConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local keymap = config.keymap  or "<leader>fm"
  _adapter        = adapter
  _cmd            = config.command   -- nil unless the user overrides the launcher
  _debug          = config.debug == true
  _reuse_existing = config.reuse_existing == true

  tree_attach.on_attach(function(buf)
    map("n", keymap, M.open, { buffer = buf },
      "Filetree: open node directory in system file manager")
  end)
end

function M.teardown()
end

return M
