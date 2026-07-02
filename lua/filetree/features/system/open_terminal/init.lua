---@module 'filetree.features.open_terminal'
---@brief Open a terminal in the directory of the current tree node.
---@description
--- Detects available terminal integrations in order:
---   1. snacks.terminal  (folke/snacks.nvim)
---   2. toggleterm.nvim  (akinsho/toggleterm.nvim)
---   3. Neovim built-in  :terminal (hsplit or vsplit)
---
--- The working directory is the parent directory of the node under the cursor
--- (or the node itself when it is a directory).
---
--- Keymap (default): "T" in tree buffer.
--- User command:     :FiletreeOpenTerminal

local notify = require("filetree.util.notify").create("[filetree.open_terminal]")

local M = {}

---@type FiletreeOpenTerminalConfig
local _cfg = {
  enabled     = false,
  keymap      = "T",
  prefer      = "auto",  -- "auto"|"snacks"|"toggleterm"|"builtin"
  split       = "horizontal",  -- "horizontal"|"vertical"|"float" (builtin only)
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Backend detection ─────────────────────────────────────────────────────────

local function open_snacks(dir)
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.terminal then return false end
  pcall(snacks.terminal, nil, { cwd = dir })
  return true
end

local function open_toggleterm(dir)
  local ok, tt = pcall(require, "toggleterm.terminal")
  if not ok then return false end
  local Terminal = tt.Terminal
  if not Terminal then return false end
  local term = Terminal:new({ dir = dir, hidden = true })
  term:toggle()
  return true
end

local function open_builtin(dir)
  local split = _cfg.split
  if split == "float" then
    -- minimal floating terminal
    local bufnr = vim.api.nvim_create_buf(false, true)
    local width  = math.floor(vim.o.columns * 0.75)
    local height = math.floor(vim.o.lines   * 0.75)
    local row    = math.floor((vim.o.lines   - height) / 2)
    local col    = math.floor((vim.o.columns - width)  / 2)
    vim.api.nvim_open_win(bufnr, true, {
      relative = "editor",
      row = row, col = col,
      width = width, height = height,
      style = "minimal", border = "rounded",
    })
  elseif split == "vertical" then
    vim.cmd("vsplit | enew")
  else
    vim.cmd("split | enew")
  end

  -- Start the shell with cwd set natively. This is shell-agnostic — no manual
  -- `cd` is sent, so it works with cmd, PowerShell, bash, zsh, … alike (the old
  -- `cd /d` was cmd.exe-only and broke under PowerShell).
  vim.fn.termopen(vim.o.shell, { cwd = dir })
  vim.cmd("startinsert")
  return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Open a terminal in `dir`.
---@param dir string  Absolute directory path.
function M.open(dir)
  local prefer = _cfg.prefer or "auto"
  if prefer == "snacks" then
    if not open_snacks(dir) then notify.error("snacks.terminal not available") end
    return
  end
  if prefer == "toggleterm" then
    if not open_toggleterm(dir) then notify.error("toggleterm.nvim not available") end
    return
  end
  if prefer == "builtin" then
    open_builtin(dir)
    return
  end
  -- auto: try in order
  if not open_snacks(dir) and not open_toggleterm(dir) then
    open_builtin(dir)
  end
end

---Open terminal at the directory of the current tree node.
function M.open_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node then
    notify.warn("no node under cursor")
    return
  end
  local dir
  if node.type == "directory" then
    dir = node.path
  else
    dir = vim.fn.fnamemodify(node.path, ":h")
  end
  M.open(dir)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeOpenTerminalConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_open_terminal", { clear = true })

  if _cfg.keymap then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.keymap.set("n", _cfg.keymap, M.open_current, {
            buffer = buf,
            silent = true,
            desc   = "Filetree: open terminal at current node",
          })
        end)
      end,
    })
  end

end

function M.teardown()
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
