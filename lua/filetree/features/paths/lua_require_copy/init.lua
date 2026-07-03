---@module 'filetree.features.lua_require_copy'
---@brief Copy current node as require('module.path') string(s) to clipboard.

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeLuaRequireCopyConfig
local _cfg = {
  enabled = false,
  keymap  = "rq",
}
---@type FiletreeAdapter?
local _adapter = nil

local notify = require("filetree.util.notify").create("[filetree.lua_require_copy]")

---Find the lua/ root directory in a path.
---@param path string
---@return string?
local function find_lua_root(path)
  -- Walk up until we find a /lua/ segment
  local cur = path
  while true do
    local parent = vim.fn.fnamemodify(cur, ":h")
    if parent == cur then break end
    -- Check if there is a 'lua' directory at this level
    local candidate = parent .. "/lua"
    local stat = vim.uv.fs_stat(candidate)
    if stat and stat.type == "directory" then
      return candidate
    end
    cur = parent
  end
  -- Fallback: stdpath("config")/lua
  return vim.fn.stdpath("config") .. "/lua"
end

---Convert a relative path (from lua root) to a module string.
---@param rel_path string
---@return string
local function path_to_module(rel_path)
  return rel_path
    :gsub("\\", "/")
    :gsub("%.lua$", "")
    :gsub("/init$", "")
    :gsub("/", ".")
end

---Recursively gather all .lua files under a directory.
---@param dir string   Absolute directory path
---@param lua_root string
---@return string[]   Module strings
local function gather_lua_files(dir, lua_root)
  local modules = {}
  local entries = vim.fn.readdir(dir)
  if not entries then return modules end

  -- Ensure lua_root ends with /
  local root = lua_root:gsub("\\", "/"):gsub("/?$", "/")

  for _, entry in ipairs(entries) do
    local full = dir .. "/" .. entry
    if vim.fn.isdirectory(full) == 1 then
      local sub = gather_lua_files(full, lua_root)
      for _, m in ipairs(sub) do modules[#modules + 1] = m end
    elseif entry:match("%.lua$") then
      local rel = full:gsub("\\", "/"):gsub("^" .. vim.pesc(root), "")
      modules[#modules + 1] = path_to_module(rel)
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
  notify.info(string.format("Copied %d require() string(s):\n%s", count,
    count == 1 and text or text:sub(1, 200) .. (count > 1 and "\n..." or "")))
end

---Copy current node as require() string(s) using the lua root.
function M.copy_require()
  if not _adapter then return end

  local node = _adapter.get_current_node()
  if not node or not node.path then
    notify.warn("No current node")
    return
  end

  local lua_root = find_lua_root(node.path)
  if not lua_root then
    notify.warn("Could not find lua/ root")
    return
  end

  local root_norm = lua_root:gsub("\\", "/"):gsub("/?$", "/")

  local modules = {}
  if node.type == "directory" then
    modules = gather_lua_files(node.path, lua_root)
  else
    local rel = node.path:gsub("\\", "/"):gsub("^" .. vim.pesc(root_norm), "")
    modules[1] = path_to_module(rel)
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
  local lua_root = cwd .. "lua"

  local root_norm = lua_root:gsub("/?$", "/")

  local modules = {}
  if node.type == "directory" then
    modules = gather_lua_files(node.path, lua_root)
  else
    local path_norm = node.path:gsub("\\", "/")
    local rel = path_norm:gsub("^" .. vim.pesc(root_norm), "")
    modules[1] = path_to_module(rel)
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
  _cfg     = vim.tbl_deep_extend("force", _cfg, cfg or {})
  _adapter = adapter

  if _cfg.keymap then
    local function set_km(buf)
      map("n", _cfg.keymap, function() M.copy_require() end,
        { buffer = buf, desc = "filetree: copy as require()", silent = true })
    end

    local winid = adapter.get_winid and adapter.get_winid()
    if winid then
      set_km(vim.api.nvim_win_get_buf(winid))
    else
      au.acmd("FileType", {
        pattern  = { "neo-tree", "NvimTree" },
        callback = function(ev)
          local buf = ev.buf
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then return end
            set_km(buf)
          end)
        end,
      })
    end
  end
end

function M.teardown()
  _adapter = nil
end

return M
