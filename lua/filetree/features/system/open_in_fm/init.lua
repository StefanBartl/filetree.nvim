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
---   enabled   boolean
---   keymap    string?    Key in tree buffer (default "<leader>fm").
---   command   string?    Override the launcher. The directory path is passed as
---                        the last argument (e.g. "nautilus", "thunar").

local notify   = require("filetree.util.notify").create("[filetree.open_in_fm]")
local platform = require("filetree.util.platform")
local path     = require("filetree.util.path")
local map      = require("filetree.util.map")
local au       = require("filetree.util.autocmd")

local M = {}

-- ── Launch ────────────────────────────────────────────────────────────────────

---Spawn a detached process; returns true when the job started.
---@param args string[]
---@return boolean
local function spawn(args)
  local id = vim.fn.jobstart(args, { detach = true })
  if not id or id <= 0 then
    notify.warn("Failed to launch: " .. table.concat(args, " "))
    return false
  end
  return true
end

---Manual per-platform folder open (fallback for Neovim < 0.10).
---@param dir string
---@return boolean
local function manual_open(dir)
  if platform.is_windows() then
    return spawn({ "explorer", (dir:gsub("/", "\\")) })
  elseif platform.is_mac() then
    return spawn({ "open", dir })
  elseif platform.has_executable("wslview") then
    return spawn({ "wslview", dir })
  else
    return spawn({ "xdg-open", dir })
  end
end

---Open `dir` in the system file manager. Prefers `vim.ui.open`.
---@param dir string  Absolute directory path.
---@param override string?  Explicit launcher command, if configured.
local function launch(dir, override)
  if override and override ~= "" then
    spawn({ override, dir })
    return
  end

  if type(vim.ui.open) == "function" then
    -- vim.ui.open returns (SystemObj|nil, err|nil); a non-nil object = spawned.
    local ok, obj = pcall(vim.ui.open, dir)
    if ok and obj ~= nil then
      return
    end
    -- otherwise fall through to the manual path
  end

  manual_open(dir)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil
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
  launch(dir, _cmd)
end

---@param config FiletreeOpenInFmConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local keymap = config.keymap  or "<leader>fm"
  _adapter = adapter
  _cmd     = config.command   -- nil unless the user overrides the launcher

  au.del_group(_augroup)
  _augroup = au.group("filetree_open_in_fm", true)

  au.create("FileType", function(ev)
    local buf = ev.buf
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      map("n", keymap, M.open, { buffer = buf },
        "Filetree: open node directory in system file manager")
    end)
  end, { group = _augroup, pattern = { "neo-tree", "NvimTree" } })
end

function M.teardown()
  au.del_group(_augroup)
  _augroup = nil
end

return M
