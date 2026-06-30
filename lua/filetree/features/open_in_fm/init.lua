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
--- The command runs asynchronously via vim.fn.jobstart so Neovim is not
--- blocked while the file manager launches.
---
--- Config:
---   enabled   boolean
---   keymap    string?    Key in tree buffer (default "<leader>fm").
---   command   string?    Override the launch command entirely. The directory
---                        path is appended as the last argument.

local notify = require("filetree.util.notify").create("[filetree.open_in_fm]")

local M = {}

-- ── Platform detection ────────────────────────────────────────────────────────

local function default_cmd()
  local uname = vim.loop and vim.loop.os_uname and vim.loop.os_uname()
  if uname then
    local sys = uname.sysname or ""
    if sys:find("Windows") or sys:find("MINGW") or sys:find("CYGWIN") then
      return "explorer"
    elseif sys == "Darwin" then
      return "open"
    end
  end
  -- Linux / BSD / WSL fallback
  return "xdg-open"
end

-- ── Launch ────────────────────────────────────────────────────────────────────

---Open `dir` in the system file manager.
---@param dir string  Absolute directory path.
---@param cmd string  Binary to invoke.
local function launch(dir, cmd)
  local args
  if cmd == "open" then
    -- macOS: -R reveals the item in Finder; fall back to dir directly
    args = { "open", dir }
  elseif cmd == "explorer" then
    -- Windows: explorer path\ — trailing backslash ensures it opens the folder
    args = { "explorer", dir:gsub("/", "\\") }
  else
    args = { cmd, dir }
  end

  local ok = vim.fn.jobstart(args, { detach = true })
  if not ok or ok <= 0 then
    notify.warn("Failed to launch file manager: " .. table.concat(args, " "))
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeOpenInFmConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local keymap = config.keymap  or "<leader>fm"
  local cmd    = config.command or default_cmd()

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_open_in_fm", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.keymap.set("n", keymap, function()
          local node = adapter.get_current_node and adapter.get_current_node()
          if not node or not node.path or node.path == "" then
            notify.warn("No node under cursor")
            return
          end

          local dir
          if vim.fn.isdirectory(node.path) == 1 then
            dir = node.path
          else
            dir = vim.fn.fnamemodify(node.path, ":h")
          end

          if not dir or dir == "" then
            notify.warn("Cannot resolve directory for node")
            return
          end

          launch(dir, cmd)
        end, {
          buffer = buf, silent = true,
          desc   = "Filetree: open node directory in system file manager",
        })
      end)
    end,
  })
end

function M.teardown()
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
