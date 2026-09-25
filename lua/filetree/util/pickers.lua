---@module 'filetree.util.pickers'
---@brief Soft bridge to pickers.nvim: files / live grep scoped to one directory.
---@description
--- pickers.nvim already owns the engine choice (telescope / fzf-lua / snacks),
--- the `find.*` flags and the entry actions, so the tree hands it a root and
--- lets it do the rest instead of re-implementing a picker per engine.
---
--- It has no "run `files` in this directory" entry point of its own (its
--- scopes are cwd / config / folder / collection), so this drives the same two
--- pieces every scope ends up in: the engine module and the action module,
--- with a hand-built `{ roots, prompt }` source. Soft dependency: every call
--- answers `false` when pickers.nvim is not installed.

local M = {}

---@internal
---@return table? engine
local function engine()
  local ok, engines = pcall(require, "pickers.engines")
  if not ok then return nil end
  local mod = engines.load()
  return mod
end

---True when pickers.nvim is installed and an engine is available.
---@return boolean
function M.available()
  local ok = pcall(require, "pickers.actions.files")
  return ok and engine() ~= nil
end

---@internal
---@param dir string
---@param what string
---@return Pickers.Source
local function source_for(dir, what)
  local name = vim.fn.fnamemodify(dir, ":t")
  return { roots = { dir }, prompt = what .. " " .. (name ~= "" and name or dir) .. "> " }
end

---Find files under `dir`.
---@param dir string
---@param query? string  Seeds the prompt.
---@return boolean handled
function M.files(dir, query)
  local eng = engine()
  local ok, files = pcall(require, "pickers.actions.files")
  if not eng or not ok then return false end
  local source = source_for(dir, "Files")
  source.query = query
  files.run(source, eng)
  return true
end

---Live grep under `dir`.
---@param dir string
---@param query? string  Seeds the prompt.
---@param extra_args? string[]  Additional rg flags.
---@return boolean handled
function M.grep(dir, query, extra_args)
  local eng = engine()
  local ok, grep = pcall(require, "pickers.actions.grep")
  if not eng or not ok then return false end
  local source = source_for(dir, "Grep")
  source.query = query
  grep.run(source, eng, extra_args)
  return true
end

return M
