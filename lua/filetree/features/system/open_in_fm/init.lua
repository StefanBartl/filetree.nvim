---@module 'filetree.features.system.open_in_fm'
--- Open the node under cursor in the system file manager.
---
--- Binds a key (default `<leader>fm`) in the tree buffer.  On activation it
--- resolves the node under the cursor and shows it in the platform's native
--- file manager — a file selected inside its parent directory, a directory
--- navigated into:
---
---   Windows  → explorer.exe /select,<file>  /  explorer.exe <dir>
---   macOS    → open -R <file>  /  open <dir>  (Finder)
---   Linux    → nautilus / nemo / dolphin --select / …, xdg-open for a directory
---
--- The platform dispatch itself lives in `lib.nvim.cross.reveal_in_fm`, shared
--- with open.nvim's `:Open filemanager` handler, so a fix there lands in both
--- plugins at once. This module contributes what is specific to a tree buffer:
--- resolving the node under the cursor, the optional Explorer-window reuse,
--- and the debug logging.
---
--- Config:
---   enabled        boolean
---   keymap         string?    Key in tree buffer (default "<leader>fm").
---   command        string?    Override the launcher. The path is passed as the
---                             last argument (e.g. "nautilus", "thunar").
---   reveal         boolean?   Select a file node inside its parent directory
---                             (default true). false → open the containing
---                             directory without selecting anything, which is
---                             what this feature did before the reveal option
---                             existed. Directory nodes are always navigated
---                             into either way.
---   debug          boolean?   Verbose notify.debug() logging of every launch attempt
---                             (branch taken, argv, job id, exit code/stderr). Default
---                             false — this feature previously had NO diagnostics at
---                             all, which is why an intermittent failure looked like
---                             it had "no pattern": every path here only ever checked
---                             that a process STARTED, never that it actually
---                             succeeded, so a transient OS-side failure (Explorer's
---                             COM server busy, a slow/locked network path, a
---                             misconfigured xdg-open handler) was invisible.
---   reuse_existing boolean?   Windows only. Navigate an already-open Explorer
---                             window to the target instead of opening another one.
---                             A window rather than a literal new tab because
---                             Explorer's tab feature has no scripting hook, while
---                             Shell.Application's Navigate2 has worked unchanged
---                             since Windows XP. Forwarded to
---                             lib.nvim.cross.reveal_in_fm as `reuse`; a file node
---                             cannot be selected this way (Navigate2 takes a
---                             folder), so it reuses the window on its parent
---                             directory. Default false.

local notify = require("filetree.util.notify").create("[filetree.open_in_fm]")
local platform = require("filetree.util.platform")
local path = require("filetree.util.path")
local map = require("filetree.util.map")
local tree_attach = require("filetree.util.tree_attach")

local M = {}

---@type boolean
local _debug = false

---@internal
---@param msg string
local function dbg(msg)
  if _debug then notify.debug(msg) end
end

-- ── Launch ────────────────────────────────────────────────────────────────────

---@type boolean
local _reuse_existing = false
---@type boolean
local _reveal = true

---@internal
---Open `target` in the system file manager.
---
---Everything platform-specific is delegated to `lib.nvim.cross.reveal_in_fm`.
---Note what a `true` return from it means: the OS agreed to spawn the
---launcher, not that a file manager window actually appeared — a file manager
---is fire-and-forget, so nothing here waits on it. `debug = true` at least
---makes the branch taken and the reported error visible.
---@param target string  Absolute path of the node (file or directory).
---@param override string?  Explicit launcher command, if configured.
local function launch(target, override)
  -- Reuse is handed to the shared dispatcher rather than attempted here first:
  -- it has to happen in the same step as bringing the window to the front, and
  -- that raise is the part Windows makes hard (see lib.nvim's reveal_in_fm).
  -- This module's own earlier copy did the Navigate2 and then called
  -- SetForegroundWindow straight from PowerShell, which Windows silently
  -- refuses for a background process — so the window was navigated but stayed
  -- buried, which reads exactly like nothing happened.
  local reuse = _reuse_existing and platform.is_windows() and not override

  local reveal_in_fm = require("lib.nvim.cross.reveal_in_fm")
  dbg(
    ("launch: reveal_in_fm target=%s reveal=%s reuse=%s command=%s"):format(
      target,
      tostring(_reveal),
      tostring(reuse),
      tostring(override)
    )
  )

  local ok, err = reveal_in_fm(target, { reveal = _reveal, reuse = reuse, command = override })
  if not ok then
    notify.warn("Failed to open in file manager: " .. tostring(err))
    return
  end
  dbg("launch: reveal_in_fm spawned the launcher")
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

  -- A file node is handed over as-is so it can be selected in its parent
  -- directory (`reveal`); `ensure_dir` only steps in for a path that no longer
  -- exists on disk, where selecting is not an option anyway.
  local target = node.path
  if vim.fn.isdirectory(target) ~= 1 and vim.fn.filereadable(target) ~= 1 then
    target = path.ensure_dir(target)
  end
  if not target or target == "" then
    notify.warn("Cannot resolve path for node")
    return
  end

  notify.info("Opening in file manager: " .. target)
  dbg("open(): resolved target=" .. target)
  launch(target, _cmd)
end

---@param config FiletreeOpenInFmConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local keymap = config.keymap or "<leader>fm"
  _adapter = adapter
  _cmd = config.command -- nil unless the user overrides the launcher
  _debug = config.debug == true
  _reuse_existing = config.reuse_existing == true
  _reveal = config.reveal ~= false

  tree_attach.on_attach(function(buf)
    map(
      "n",
      keymap,
      M.open,
      { buffer = buf },
      "Filetree: open node directory in system file manager"
    )
  end)
end

function M.teardown() end

return M
