---@module 'filetree.features.lua_require_copy'
---@brief Copy current node as require('module.path') string(s) to clipboard.

local map = require("filetree.util.map")
local tree_attach = require("filetree.util.tree_attach")
local M = {}

-- The canonical, already-implemented path -> Lua module resolver (same one
-- create_from_template's ${module} defers to) — reuse it rather than
-- re-deriving the same "/lua/…/init.lua -> foo.bar" logic a second time.
local get_lua_module_path = require("lib.nvim.lua_ls.get_module_path")

---@type FiletreeLuaRequireCopyConfig
local _cfg = {
  enabled = false,
  keymap = "rq",
}
---@type FiletreeAdapter?
local _adapter = nil

local notify = require("filetree.util.notify").create("[filetree.lua_require_copy]")

---Convert a relative path (from a known root) to a module string. Only
---needed for copy_require_relative's cwd-relative root below — the
---absolute-path case defers entirely to get_lua_module_path instead.
---@param rel_path string
---@return string
local function path_to_module(rel_path)
  return rel_path:gsub("\\", "/"):gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")
end

---Recursively gather all .lua files under a directory as module strings.
---@param dir string   Absolute directory path
---@param resolve fun(full_path: string): string?   Path -> module resolver; nil skips the file
---@return string[]   Module strings
local function gather_lua_files(dir, resolve)
  local modules = {}
  local entries = vim.fn.readdir(dir)
  if not entries then return modules end

  for _, entry in ipairs(entries) do
    local full = dir .. "/" .. entry
    if vim.fn.isdirectory(full) == 1 then
      local sub = gather_lua_files(full, resolve)
      for _, m in ipairs(sub) do
        modules[#modules + 1] = m
      end
    elseif entry:match("%.lua$") then
      local m = resolve(full)
      if m then modules[#modules + 1] = m end
    end
  end
  return modules
end

---Write lines to clipboard registers.
---@param text string
---@param count integer
local function write_to_clipboard(text, count)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  notify.info(
    string.format(
      "Copied %d require() string(s):\n%s",
      count,
      count == 1 and text or text:sub(1, 200) .. (count > 1 and "\n..." or "")
    )
  )
end

---Copy current node as require() string(s), resolved via the canonical
---get_lua_module_path (a pure "/lua/" substring search — no filesystem
---walking or stdpath("config") guessing). A node genuinely outside any
---lua/ directory resolves to no modules rather than a guessed, likely-wrong
---one.
function M.copy_require()
  if not _adapter then return end

  local node = _adapter.get_current_node()
  if not node or not node.path then
    notify.warn("No current node")
    return
  end

  local modules = {}
  if node.type == "directory" then
    modules = gather_lua_files(node.path, get_lua_module_path)
  else
    local m = get_lua_module_path(node.path)
    if m then modules[1] = m end
  end

  if #modules == 0 then
    notify.warn("No Lua modules found")
    return
  end

  local lines = {}
  for _, m in ipairs(modules) do
    lines[#lines + 1] = "require('" .. m .. "')"
  end

  write_to_clipboard(table.concat(lines, "\n"), #lines)
end

---Copy current node as require() string(s) relative to cwd.
function M.copy_require_relative()
  if not _adapter then return end

  local node = _adapter.get_current_node()
  if not node or not node.path then
    notify.warn("No current node")
    return
  end

  local cwd = vim.fn.getcwd():gsub("\\", "/"):gsub("/?$", "/")
  -- Use cwd/lua as the root
  local root_norm = cwd .. "lua/"

  local function resolve(full_path)
    local path_norm = full_path:gsub("\\", "/")
    local rel = path_norm:gsub("^" .. vim.pesc(root_norm), "")
    return path_to_module(rel)
  end

  local modules = {}
  if node.type == "directory" then
    modules = gather_lua_files(node.path, resolve)
  else
    modules[1] = resolve(node.path)
  end

  if #modules == 0 then
    notify.warn("No Lua modules found")
    return
  end

  local lines = {}
  for _, m in ipairs(modules) do
    lines[#lines + 1] = "require('" .. m .. "')"
  end

  write_to_clipboard(table.concat(lines, "\n"), #lines)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param cfg FiletreeLuaRequireCopyConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg = vim.tbl_deep_extend("force", _cfg, cfg or {})
  _adapter = adapter

  if _cfg.keymap then
    tree_attach.on_attach(function(buf)
      map("n", _cfg.keymap, function()
        M.copy_require()
      end, { buffer = buf, desc = "filetree: copy as require()", silent = true })
    end)
  end
end

function M.teardown()
  _adapter = nil
end

return M
