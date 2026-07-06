---@module 'filetree.bindings'
---@brief Aggregated binding catalog + optional which-key integration.
---@description
--- One place to introspect everything filetree.nvim binds:
---   • keymaps    — default keymaps by category (bindings.keymaps)
---   • usercommands — every `:Filetree …` sub-command, walked live from the
---                    dispatcher TREE so it never drifts (commands.command_paths)
---   • autocmds   — behavioural autocmds by event (bindings.autocmds)
---
--- `catalog()` returns the whole thing (also re-exported by docs/BINDINGS.lua).
--- `setup_which_key()` registers leader-group labels when which-key is installed.

local M = {}

M.keymaps  = require("filetree.bindings.keymaps")
M.autocmds = require("filetree.bindings.autocmds")

---Return every registered `:Filetree` sub-command path (live from the dispatcher).
---@return string[]
function M.usercommands()
  local ok, commands = pcall(require, "filetree.commands")
  if not ok or type(commands.command_paths) ~= "function" then return {} end
  return commands.command_paths()
end

---Return the full binding catalog as plain data.
---@return { command: string, keymaps: table, usercommands: string[], autocmds: table }
function M.catalog()
  local cfg_ok, config = pcall(require, "filetree.config")
  local cmd_name = "Filetree"
  if cfg_ok then
    local c = config.get and config.get().command
    if type(c) == "string" then cmd_name = c
    elseif type(c) == "table" and c.name then cmd_name = c.name end
  end
  return {
    command      = cmd_name,
    keymaps      = M.keymaps,
    usercommands = M.usercommands(),
    autocmds     = M.autocmds,
  }
end

-- ── which-key ──────────────────────────────────────────────────────────────────

-- Leader-prefix group labels (only these need explicit which-key groups; single
-- tree-buffer keys already carry a `desc`).
local WK_GROUPS = {
  { "<leader>m", "filetree: marks" },
}

---Register which-key group labels, if which-key is installed. Safe to call
---always; a no-op when which-key is absent. Supports the v3 (`add`) and v2
---(`register`) APIs.
function M.setup_which_key()
  local ok, wk = pcall(require, "which-key")
  if not ok then return end

  if type(wk.add) == "function" then           -- which-key v3
    local spec = {}
    for _, g in ipairs(WK_GROUPS) do
      spec[#spec + 1] = { g[1], group = g[2] }
    end
    pcall(wk.add, spec)
  elseif type(wk.register) == "function" then   -- which-key v2
    local spec = {}
    for _, g in ipairs(WK_GROUPS) do
      spec[g[1]] = { name = g[2] }
    end
    pcall(wk.register, spec)
  end
end

return M
