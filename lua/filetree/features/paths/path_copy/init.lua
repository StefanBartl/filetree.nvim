---@module 'filetree.features.path_copy'
---@brief Copy the current node's path in various formats to the system clipboard.
---@description
--- Provides quick access to multiple path representations, all written to
--- both the "+" (system) register and the unnamed '"' register.
---
--- Formats:
---   absolute  /home/user/project/src/foo.lua
---   relative  src/foo.lua             (relative to cwd)
---   name      foo.lua                 (filename only)
---   dirname   /home/user/project/src  (parent directory)
---   uri       file:///home/user/...   (file:// URI)
---   line      src/foo.lua:42          (path + cursor line in tree win)
---   stem      foo                     (filename without extension)
---
--- Config:
---   enabled        boolean
---   keymap_pick    string?  Opens format picker (default nil, off).
---   keymap_abs     string?  Copy absolute path directly (default "[a").
---   keymap_dirname string?  Copy absolute parent dir directly (default "]a").
---   keymap_name    string?  Copy name directly (default nil, off).
---   notify         boolean  Show a notification after copying (default true).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree copy absolute|relative|name|dirname|uri|line|stem|pick

local notify = require("filetree.util.notify").create("[filetree.path_copy]")

local ui_select = require("filetree.util.select")
local bind = require("filetree.util.bind")
local M = {}

---@type FiletreePathCopyConfig
local _cfg = {
  enabled = false,
  keymap_pick = nil,
  keymap_abs = "[a",
  keymap_dirname = "]a",
  keymap_name = nil,
  keymap_project_root = "[R", -- copy absolute project root path
  keymap_project_rel = "]R", -- copy node path relative to project root
  root_markers = { ".git" },
  notify = true,
}

---@type FiletreeAdapter?
local _adapter = nil

---Cached marker-based root finder from lib.nvim.fs.find_root.
---@class FiletreeRootFinder
---@field find  fun(path: string): string?
---@field clear fun()

---nil when disabled via root_markers=false, or lib.nvim is unavailable
---@type FiletreeRootFinder?
local _root_finder = nil

---Resolve the project root for `path` (falls back to cwd when unresolved).
---@param path string
---@return string
local function resolve_root(path)
  if _root_finder then
    local ok, root = pcall(_root_finder.find, path)
    if ok and root and root ~= "" then return root end
  end
  return vim.fn.getcwd()
end

-- ── Format builders ───────────────────────────────────────────────────────────

local function current_node_path()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()
  return node and node.path or nil
end

local function cursor_line()
  local winid = _adapter and _adapter.get_winid and _adapter.get_winid() or -1
  if winid > 0 and vim.api.nvim_win_is_valid(winid) then
    return vim.api.nvim_win_get_cursor(winid)[1]
  end
  return nil
end

---@type table<string, fun(path: string): string>
local FORMATS = {
  absolute = function(path)
    return path
  end,
  relative = function(path)
    return vim.fn.fnamemodify(path, ":.")
  end,
  name = function(path)
    return vim.fn.fnamemodify(path, ":t")
  end,
  dirname = function(path)
    return vim.fn.fnamemodify(path, ":h")
  end,
  stem = function(path)
    return vim.fn.fnamemodify(path, ":t:r")
  end,
  uri = function(path)
    local abs = vim.fn.fnamemodify(path, ":p"):gsub("\\", "/")
    return "file://" .. (abs:sub(1, 1) == "/" and abs or "/" .. abs)
  end,
  line = function(path)
    local ln = cursor_line()
    local rel = vim.fn.fnamemodify(path, ":.")
    return ln and (rel .. ":" .. ln) or rel
  end,
  -- Absolute path of the detected project root ([R). cwd-independent.
  project_root = function(path)
    return resolve_root(path)
  end,
  -- Path relative to the project root (]R), independent of the current cwd.
  project_relative = function(path)
    local root = resolve_root(path)
    local ok, relpath = pcall(require, "lib.nvim.fs.relpath")
    if ok and type(relpath) == "function" then return relpath(path, root) end
    -- Fallback: strip the root prefix manually.
    local nroot = root:gsub("\\", "/"):gsub("/$", "")
    local npath = path:gsub("\\", "/")
    if npath:sub(1, #nroot + 1) == nroot .. "/" then return npath:sub(#nroot + 2) end
    return npath
  end,
}

local FORMAT_ORDER = {
  "absolute",
  "relative",
  "name",
  "dirname",
  "stem",
  "uri",
  "line",
  "project_root",
  "project_relative",
}

-- ── Copy helper ───────────────────────────────────────────────────────────────

local function do_copy(fmt)
  local path = current_node_path()
  if not path then
    notify.warn("No node under cursor")
    return
  end

  local builder = FORMATS[fmt]
  if not builder then
    notify.warn("Unknown format: " .. fmt)
    return
  end

  local text = builder(path)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)

  if _cfg.notify then notify.info(string.format("[%s] %s", fmt, text)) end
end

-- ── Public API ────────────────────────────────────────────────────────────────

for _, fmt in ipairs(FORMAT_ORDER) do
  M["copy_" .. fmt] = function()
    do_copy(fmt)
  end
end

function M.pick()
  local path = current_node_path()
  if not path then
    notify.warn("No node under cursor")
    return
  end

  local built = {}
  for _, fmt in ipairs(FORMAT_ORDER) do
    built[#built + 1] = { fmt = fmt, text = FORMATS[fmt](path) }
  end

  ui_select(built, {
    prompt = "Copy path",
    format_item = function(item)
      return string.format("%-10s %s", item.fmt, item.text)
    end,
  }, function(item)
    if not item then return end
    vim.fn.setreg("+", item.text)
    vim.fn.setreg('"', item.text)
    if _cfg.notify then notify.info(string.format("[%s] %s", item.fmt, item.text)) end
  end)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreePathCopyConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  -- Build the cached project-root finder unless disabled (root_markers = false).
  _root_finder = nil
  local markers = _cfg.root_markers
  if markers == nil then markers = { ".git" } end
  if markers ~= false then
    local ok, find_root = pcall(require, "lib.nvim.fs.find_root")
    if ok and type(find_root) == "function" then _root_finder = find_root({ markers = markers }) end
  end

  bind.bind("path_copy", _cfg, {
    { name = "pick", field = "keymap_pick", rhs = M.pick, desc = "copy path (pick format)" },
    { name = "absolute", field = "keymap_abs", rhs = M.copy_absolute, desc = "copy absolute path" },
    {
      name = "dirname",
      field = "keymap_dirname",
      rhs = M.copy_dirname,
      desc = "copy absolute parent directory",
    },
    { name = "name", field = "keymap_name", rhs = M.copy_name, desc = "copy filename" },
    {
      name = "project_root",
      field = "keymap_project_root",
      rhs = M.copy_project_root,
      desc = "copy absolute project root",
    },
    {
      name = "project_relative",
      field = "keymap_project_rel",
      rhs = M.copy_project_relative,
      desc = "copy path relative to project root",
    },
  })
end

function M.teardown()
  _adapter = nil
  _root_finder = nil
end

return M
