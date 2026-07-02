---@module 'filetree.features.shell_run'
---@brief Run a shell command in the node's directory from the tree buffer.
---@description
--- Binds a key (default `i`) in the tree buffer.  On activation:
---
---   1. Resolves the directory of the node under the cursor (or cwd if none).
---   2. Prompts for a shell command via vim.ui.input.
---   3. Runs the command in a split terminal via `termopen(cmd, { cwd = dir })`
---      — cwd is set natively (shell-agnostic; no `cd … &&`). The terminal
---      window closes automatically when the command exits 0 (`on_exit`).
---
--- The terminal approach gives the user live output, coloured output, and
--- interactive input (password prompts, confirm dialogs) without blocking
--- Neovim's event loop.
---
--- Config:
---   enabled      boolean
---   keymap       string?   Key in tree buffer (default "i").
---   close_on_ok  boolean   Auto-close terminal when command exits 0 (default true).
---   split        string?   Split direction: "split" | "vsplit" (default "split").
---   height       integer?  Terminal height in lines when split="split" (default 12).

local notify = require("filetree.util.notify").create("[filetree.shell_run]")
local path   = require("filetree.util.path")

local M = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

---Return the directory to use: node dir if available, else cwd.
---@param adapter FiletreeAdapter
---@return string
local function resolve_dir(adapter)
  local node = adapter.get_current_node and adapter.get_current_node()
  if node and node.path and node.path ~= "" then
    return path.ensure_dir(node.path)
  end
  return vim.fn.getcwd()
end

---Open a terminal window running `cmd` with cwd set to `dir`.
---@param dir          string
---@param cmd          string
---@param close_on_ok  boolean
---@param split        string   "split" | "vsplit"
---@param height       integer
local function run_in_terminal(dir, cmd, close_on_ok, split, height)
  -- Open an empty split, then run the command with cwd set natively. No manual
  -- `cd … && …` — that was shell-specific (`&&` breaks on older PowerShell);
  -- termopen's `cwd` is shell-agnostic (cmd, PowerShell, bash, zsh, …).
  local open_cmd = split == "vsplit" and "vsplit | enew" or (height .. "split | enew")
  local ok, err = pcall(vim.cmd, open_cmd)
  if not ok then
    notify.warn("Could not open terminal split: " .. tostring(err))
    return
  end

  local term_buf = vim.api.nvim_get_current_buf()
  local job = vim.fn.termopen(cmd, {
    cwd     = dir,
    on_exit = function(_, code)
      if close_on_ok and code == 0 then
        pcall(vim.api.nvim_buf_delete, term_buf, { force = true })
      end
    end,
  })
  if not job or job <= 0 then
    notify.warn("Could not run command: " .. cmd)
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil
---@type FiletreeAdapter?
local _adapter = nil
---@type table
local _opts = {}

---Prompt for a shell command and run it in the node directory.
function M.run()
  local adapter = _adapter
  if not adapter then return end
  local dir = resolve_dir(adapter)
  local prompt = "$ (" .. vim.fn.fnamemodify(dir, ":~") .. ") "
  vim.ui.input({ prompt = prompt }, function(cmd)
    if not cmd or cmd == "" then return end
    run_in_terminal(dir, cmd, _opts.close_on_ok, _opts.split, _opts.height)
  end)
end

---@param config FiletreeShellRunConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local keymap = config.keymap or "i"
  _adapter = adapter
  _opts = {
    close_on_ok = config.close_on_ok ~= false,   -- default true
    split       = config.split       or "split",
    height      = config.height      or 12,
  }

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_shell_run", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.keymap.set("n", keymap, M.run, {
          buffer = buf, silent = true,
          desc   = "Filetree: run shell command in node directory",
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
