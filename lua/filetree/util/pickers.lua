---@module 'filetree.util.pickers'
---@brief Soft bridge to pickers.nvim: files / live grep scoped to one directory.
---@description
--- pickers.nvim owns the engine choice (telescope / fzf-lua / snacks), the
--- `find.*` flags and the entry actions, so the tree hands it a directory and
--- lets it do the rest instead of driving a picker of its own.
---
--- It is used only when all three hold, and each is an opt-out:
---   1. pickers.nvim is installed and ships `pickers.integrations.filetree`
---      (an older one does not, and is treated as absent);
---   2. `integrations.pickers` is not `false` in filetree's own config;
---   3. `filetree = { enabled = false }` is not set in pickers.nvim's config
---      (that side answers `false` itself).
--- Any of them missing makes every call answer `false`, and the caller falls
--- back to its own backends (telescope, fzf-lua, ...).

local M = {}

---@internal
---filetree's own switch. Read from the resolved config rather than passed in,
---so the `tf`/`tg` keys and the auto chain cannot disagree about it.
---@return boolean
local function enabled_here()
  local ok, cfg = pcall(function()
    return require("filetree.config").get()
  end)
  if not ok or type(cfg) ~= "table" or type(cfg.integrations) ~= "table" then return true end
  return cfg.integrations.pickers ~= false
end

---@internal
---pickers.nvim's side of the bridge, or nil when it is absent, too old, or
---switched off on this side.
---@return table?
local function bridge()
  if not enabled_here() then return nil end
  local ok, mod = pcall(require, "pickers.integrations.filetree")
  if not ok or type(mod) ~= "table" then return nil end
  return mod
end

---True when the bridge is usable right now (all three conditions above, plus
---an installed engine).
---@return boolean
function M.available()
  local b = bridge()
  return b ~= nil and b.available() == true
end

---Find files under `dir`.
---@param dir string
---@param query? string  Seeds the prompt.
---@param on_select? fun(path: string)  Called with the picked file's absolute path once pickers.nvim opened it (an older pickers.nvim ignores it).
---@return boolean handled
function M.files(dir, query, on_select)
  local b = bridge()
  if not b then return false end
  return b.files(dir, { query = query, on_select = on_select }) == true
end

---Live grep under `dir`.
---@param dir string
---@param query? string  Seeds the prompt.
---@param extra_args? string[]  Additional rg flags.
---@return boolean handled
function M.grep(dir, query, extra_args)
  local b = bridge()
  if not b then return false end
  return b.grep(dir, { query = query, extra_args = extra_args }) == true
end

return M
