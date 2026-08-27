---@module 'filetree.bindings'
--- Aggregated binding catalog + optional which-key integration.
---
--- One place to introspect everything filetree.nvim binds:
---   • keymaps    — the DEFAULT keymaps by category (bindings.keymaps); what
---                  the plugin ships with, including features that are off by
---                  default. Meaningful before `setup()` has run.
---   • live       — what is bound RIGHT NOW, read back from lib.nvim's keymap
---                  registry: the user's own keys, with the disabled ones
---                  gone. Empty until `setup()` has run.
---   • usercommands — every `:Filetree …` sub-command, walked live from the
---                    dispatcher TREE so it never drifts (commands.command_paths)
---   • autocmds   — what is actually registered, read back from lib.nvim
---                  (bindings.autocmds); no longer a hand-written list
---
--- `catalog()` returns the whole thing (also re-exported by docs/BINDINGS.lua).
--- `setup_which_key()` registers leader-group labels when which-key is installed.

local M = {}

M.keymaps = require("filetree.bindings.keymaps")
M.autocmds = require("filetree.bindings.autocmds")

---Return every registered `:Filetree` sub-command path (live from the dispatcher).
---@return string[]
function M.usercommands()
  local ok, commands = pcall(require, "filetree.commands")
  if not ok or type(commands.command_paths) ~= "function" then return {} end
  return commands.command_paths()
end

---Every keymap actually bound, from lib.nvim's registry.
---
---The catalog beside it lists what the plugin *ships*; this lists what the
---user *has*. Both are worth having and they are not the same question --
---which is why the cheatsheet reads this one.
---@return { feature: string, name: string, lhs: string, mode: string|string[], desc: string|nil }[]
function M.live()
  local ok, keymap = pcall(require, "lib.nvim.bindings.keymap")
  if not ok then return {} end

  ---@type table<string, boolean>
  local seen = {}
  local out = {}
  for key, entries in pairs(keymap.registered()) do
    local feature = key:match("^filetree/(.+)$")
    if feature then
      for _, e in ipairs(entries) do
        -- A buffer-local preset is registered once per tree buffer; the answer
        -- to "which keys do I have" is the same each time.
        local id = feature .. " " .. tostring(e.mode) .. " " .. tostring(e.lhs)
        if e.bound and e.lhs and not seen[id] then
          seen[id] = true
          out[#out + 1] = {
            feature = feature,
            name = e.name,
            lhs = e.lhs,
            mode = e.mode,
            desc = e.desc,
          }
        end
      end
    end
  end

  table.sort(out, function(a, b)
    if a.feature ~= b.feature then return a.feature < b.feature end
    return a.lhs < b.lhs
  end)
  return out
end

---Return the full binding catalog as plain data.
---@return { command: string, keymaps: table, live: table, usercommands: string[], autocmds: table }
function M.catalog()
  local cfg_ok, config = pcall(require, "filetree.config")
  local cmd_name = "Filetree"
  if cfg_ok then
    local c = config.get and config.get().command
    if type(c) == "string" then
      cmd_name = c
    elseif type(c) == "table" and c.name then
      cmd_name = c.name
    end
  end
  return {
    command = cmd_name,
    keymaps = M.keymaps,
    live = M.live(),
    usercommands = M.usercommands(),
    autocmds = M.autocmds.list(),
  }
end

-- ── which-key ──────────────────────────────────────────────────────────────────

-- Leader-prefix group labels (only these need explicit which-key groups; single
-- tree-buffer keys already carry a `desc`).
local WK_GROUPS = {
  { "<leader>m", "filetree: marks" },
}

---Register which-key group labels, if which-key is installed. Safe to call
---always; a no-op when which-key is absent.
function M.setup_which_key()
  local groups = {}
  for _, g in ipairs(WK_GROUPS) do
    groups[#groups + 1] = { prefix = g[1], group = g[2] }
  end
  require("lib.nvim.bindings.keymap.which_key").add_group(groups)
end

return M
