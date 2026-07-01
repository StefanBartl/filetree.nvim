---@module 'filetree.features.open_with'
---@brief Open tree nodes with external applications.
---@description
--- Two modes:
---   system  — uses the OS default handler (xdg-open / open / start)
---   custom  — user-defined app list with optional keymaps
---
--- Config:
---   enabled  boolean
---   keymap   string?  Key for system default open (default "ox").
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

local M = {}

---@type FiletreeOpenWithConfig
local _cfg = {
  enabled = false,
  keymap  = "ox",
  apps    = {},
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Open helpers ──────────────────────────────────────────────────────────────

local function system_open_cmd()
  if platform.is_windows() then return { "cmd", "/c", "start", "" }
  elseif platform.is_wsl()  then return { "wsl-open" }
  end
  -- macOS or Linux
  local uname = vim.fn.system("uname -s"):gsub("%s+", "")
  if uname == "Darwin" then return { "open" }
  else return { "xdg-open" } end
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
  open_with_cmd(system_open_cmd(), path)
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
      open_with_cmd(system_open_cmd(), path)
    else
      local cmd = { app.cmd }
      for _, a in ipairs(app.args or {}) do cmd[#cmd + 1] = a end
      open_with_cmd(cmd, path)
    end
    notify.info(string.format("Opening with %s: %s", app.name, vim.fn.fnamemodify(path, ":t")))
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>",  choose, opts)
  vim.keymap.set("n", "q",     function() vim.api.nvim_win_close(win, true) end, opts)
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, opts)
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

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_open_with", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if _cfg.keymap then
          vim.keymap.set("n", _cfg.keymap, M.open_system, {
            buffer = buf, silent = true, desc = "Filetree: open with system default",
          })
        end
        -- Register per-app keymaps
        for _, app in ipairs(_cfg.apps) do
          if app.keymap then
            local app_copy = app
            vim.keymap.set("n", app.keymap, function() M.open_app(app_copy.name) end, {
              buffer = buf, silent = true,
              desc   = "Filetree: open with " .. app.name,
            })
          end
        end
      end)
    end,
  })
end

function M.teardown()
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
