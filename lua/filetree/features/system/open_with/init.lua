---@module 'filetree.features.open_with'
---@brief Open tree nodes with external applications.
---@description
--- Two modes:
---   system  — uses the OS default handler (xdg-open / open / start)
---   custom  — user-defined app list with optional keymaps
---
--- Config:
---   enabled  boolean
---   keymap   string?  Key for system default open (default "<leader>sm").
---   apps     FiletreeOpenWithApp[]  List of custom app entries.
---
--- Example config:
---   apps = {
---     { name = "VSCode",   cmd = "code",    keymap = "ov" },
---     { name = "Nautilus", cmd = "nautilus", keymap = "on" },
---   }
---
--- Commands (via :Filetree dispatcher):
---   :Filetree open system
---   :Filetree open pick       (floating picker of configured apps)

local notify   = require("filetree.util.notify").create("[filetree.open_with]")
local platform = require("filetree.util.platform")
local map      = require("filetree.util.map")
local au       = require("filetree.util.autocmd")
local window   = require("filetree.util.window")

local M = {}

---@type FiletreeOpenWithConfig
local _cfg = {
  enabled = false,
  keymap  = "<leader>sm",
  apps    = {},
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Open helpers ──────────────────────────────────────────────────────────────

---Per-OS "open with default handler" command (fallback for Neovim < 0.10).
---@return string[]
local function system_open_cmd()
  if platform.is_windows() then return { "cmd", "/c", "start", "" } end
  if platform.is_mac()     then return { "open" } end
  if platform.is_wsl() or platform.has_executable("wslview") then return { "wslview" } end
  return { "xdg-open" }
end

local function open_with_cmd(cmd_parts, path)
  local full_cmd = vim.deepcopy(cmd_parts)
  full_cmd[#full_cmd + 1] = path
  vim.system(full_cmd, { detach = true }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        notify.error("Open failed (exit " .. result.code .. "): " .. (result.stderr or ""))
      end)
    end
  end)
end

---Open `path` with the OS default handler. Prefers Neovim's built-in
---`vim.ui.open` (0.10+, platform-correct + maintained); falls back to a manual
---per-OS spawn otherwise.
local function system_open(path)
  if type(vim.ui.open) == "function" then
    local ok, obj = pcall(vim.ui.open, path)
    if ok and obj ~= nil then return end
  end
  open_with_cmd(system_open_cmd(), path)
end

local function current_path()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()
  return node and node.path or nil
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Open the current node with the system default application.
function M.open_system()
  local path = current_path()
  if not path then notify.warn("No node under cursor"); return end
  system_open(path)
  notify.info("Opening: " .. vim.fn.fnamemodify(path, ":t"))
end

---Open the current node with a specific app by name or command.
---@param app_name string
function M.open_app(app_name)
  local path = current_path()
  if not path then notify.warn("No node under cursor"); return end

  for _, app in ipairs(_cfg.apps) do
    if app.name == app_name or app.cmd == app_name then
      local cmd = { app.cmd }
      for _, a in ipairs(app.args or {}) do cmd[#cmd + 1] = a end
      open_with_cmd(cmd, path)
      notify.info(string.format("Opening with %s: %s", app.name, vim.fn.fnamemodify(path, ":t")))
      return
    end
  end
  notify.warn("Unknown app: " .. app_name)
end

---Open a floating picker to choose an application.
function M.pick()
  local path = current_path()
  if not path then notify.warn("No node under cursor"); return end

  local apps = vim.list_slice(_cfg.apps)
  table.insert(apps, 1, { name = "System default", cmd = "_system" })

  local labels = vim.tbl_map(function(a) return a.name end, apps)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, labels)
  vim.bo[buf].modifiable = false

  local width  = math.min(40, vim.o.columns - 4)
  local height = math.min(#labels, 10)
  local win    = vim.api.nvim_open_win(buf, true, {
    relative = "cursor", style = "minimal", border = "rounded",
    width = width, height = height, row = 1, col = 0,
    title = " Open with ", title_pos = "center",
  })
  vim.wo[win].cursorline = true

  local function choose()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local app = apps[row]
    vim.api.nvim_win_close(win, true)
    if app.cmd == "_system" then
      system_open(path)
    else
      local cmd = { app.cmd }
      for _, a in ipairs(app.args or {}) do cmd[#cmd + 1] = a end
      open_with_cmd(cmd, path)
    end
    notify.info(string.format("Opening with %s: %s", app.name, vim.fn.fnamemodify(path, ":t")))
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  map("n", "<CR>", choose, opts)
  window.nice_quit(win)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeOpenWithConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  au.del_group(_augroup)
  _augroup = au.group("filetree_open_with", true)

  au.create("FileType", function(ev)
    local buf = ev.buf
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if _cfg.keymap then
        map("n", _cfg.keymap, M.open_system, { buffer = buf },
          "Filetree: open with system default")
      end
      -- Register per-app keymaps
      for _, app in ipairs(_cfg.apps) do
        if app.keymap then
          local app_copy = app
          map("n", app.keymap, function() M.open_app(app_copy.name) end,
            { buffer = buf }, "Filetree: open with " .. app.name)
        end
      end
    end)
  end, { group = _augroup, pattern = { "neo-tree", "NvimTree" } })
end

function M.teardown()
  _adapter = nil
  au.del_group(_augroup)
  _augroup = nil
end

return M
