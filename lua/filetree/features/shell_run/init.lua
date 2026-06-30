---@module 'filetree.features.shell_run'
---@brief Run a shell command in the node's directory from the tree buffer.
---@description
--- Binds a key (default `i`) in the tree buffer.  On activation:
---
---   1. Resolves the directory of the node under the cursor (or cwd if none).
---   2. Prompts for a shell command via vim.ui.input.
---   3. Runs the command via a split terminal (`:split term://cd <dir> && <cmd>`).
---      The terminal window closes automatically when the command exits with
---      code 0 (`on_exit` callback).
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

local M = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

---Return the directory to use: node dir if available, else cwd.
---@param adapter FiletreeAdapter
---@return string
local function resolve_dir(adapter)
  local node = adapter.get_current_node and adapter.get_current_node()
  if node and node.path and node.path ~= "" then
    if vim.fn.isdirectory(node.path) == 1 then
      return node.path
    else
      return vim.fn.fnamemodify(node.path, ":h")
    end
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
  -- Build a shell one-liner: cd into dir, then run the user command
  local shell_line = "cd " .. vim.fn.shellescape(dir) .. " && " .. cmd

  -- Open the split terminal
  local term_cmd
  if split == "vsplit" then
    term_cmd = "vsplit term://" .. shell_line
  else
    term_cmd = height .. "split term://" .. shell_line
  end

  local ok, err = pcall(vim.cmd, term_cmd)
  if not ok then
    notify.warn("Could not open terminal: " .. tostring(err))
    return
  end

  -- In the new terminal buffer, auto-close on successful exit
  if close_on_ok then
    local term_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = term_buf,
      once   = true,
      callback = function(ev)
        -- ev.data (Neovim ≥ 0.10) or pattern contains exit code after space
        local code_str = tostring(ev.data or "")
        local code     = tonumber(code_str:match("%d+")) or -1
        if code == 0 then
          pcall(vim.api.nvim_buf_delete, term_buf, { force = true })
        end
      end,
    })
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeShellRunConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local keymap      = config.keymap      or "i"
  local close_on_ok = config.close_on_ok ~= false   -- default true
  local split       = config.split       or "split"
  local height      = config.height      or 12

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_shell_run", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.keymap.set("n", keymap, function()
          local dir = resolve_dir(adapter)
          local prompt = "$ (" .. vim.fn.fnamemodify(dir, ":~") .. ") "
          vim.ui.input({ prompt = prompt }, function(cmd)
            if not cmd or cmd == "" then return end
            run_in_terminal(dir, cmd, close_on_ok, split, height)
          end)
        end, {
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
