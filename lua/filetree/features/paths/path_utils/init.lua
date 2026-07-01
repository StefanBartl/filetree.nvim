---@module 'filetree.features.path_utils'
---@brief Path clipboard utilities and code-generation helpers for tree nodes.
---@description
--- Provides actions to copy paths in various formats, generate Markdown links,
--- and convert file paths to Lua require() statements. All actions operate on
--- the node under the cursor or on a supplied path.
---
--- Keymaps are installed in the tree buffer via FileType autocmd.
--- All results are written to the "+" (system) clipboard register.

local notify = require("filetree.util.notify").create("[filetree.path_utils]")
local path   = require("filetree.util.path")

local M = {}

---@type FiletreePathUtilsConfig
local _cfg = {
  enabled  = false,
  lua_root = nil,
  keymaps  = {
    copy_abs   = "ya",
    copy_rel   = "yr",
    copy_name  = "yn",
    copy_dir   = "yd",
    to_require = "yq",
    md_link    = "ym",
  },
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function yank(text, label)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  notify.info(label .. ": " .. text)
end

---Detect the Lua source root (the directory containing "lua/") walking up from `from_dir`.
---@param from_dir string
---@return string?
local function detect_lua_root(from_dir)
  local current = from_dir
  local prev    = nil
  while current ~= prev do
    if vim.fn.isdirectory(current .. "/lua") == 1 then
      return current .. "/lua"
    end
    prev    = current
    current = vim.fn.fnamemodify(current, ":h")
  end
  return nil
end

---Convert a file path to a Lua require() argument.
---  e.g. /project/lua/foo/bar.lua → "foo.bar"
---@param abs_path string
---@return string?
local function to_require_str(abs_path)
  if not abs_path:match("%.lua$") then
    notify.warn("to_require: not a .lua file")
    return nil
  end

  local lua_root = _cfg.lua_root
  if not lua_root then
    lua_root = detect_lua_root(vim.fn.fnamemodify(abs_path, ":h"))
  end

  local rel
  if lua_root then
    rel = path.relative(abs_path, lua_root)
  else
    rel = vim.fn.fnamemodify(abs_path, ":t")
  end

  -- strip .lua, convert / to .
  rel = rel:gsub("%.lua$", ""):gsub("/", "."):gsub("\\", ".")
  -- strip trailing .init
  rel = rel:gsub("%.init$", "")
  return rel
end

-- ── Public actions ────────────────────────────────────────────────────────────

---Copy the absolute path of `node_path` to the clipboard.
---@param node_path string
function M.copy_absolute(node_path)
  yank(node_path, "Abs path")
end

---Copy the path relative to cwd (or project root when project_root is loaded).
---@param node_path string
function M.copy_relative(node_path)
  local base
  local ok_pr, pr = require("filetree.features").load("project_root")
  if ok_pr and pr and type(pr.find) == "function" then
    base = pr.find(node_path)
  else
    base = vim.fn.getcwd()
  end
  local rel = path.relative(node_path, base)
  yank(rel, "Rel path")
end

---Copy just the filename (tail).
---@param node_path string
function M.copy_name(node_path)
  yank(path.basename(node_path), "Name")
end

---Copy the parent directory.
---@param node_path string
function M.copy_dir(node_path)
  yank(path.parent(node_path), "Dir")
end

---Copy the file path as a Lua require() string.
---@param node_path string
function M.copy_as_require(node_path)
  local req = to_require_str(node_path)
  if req then yank('require("' .. req .. '")', "require") end
end

---Copy a Markdown link: [filename](relative/path).
---@param node_path string
function M.copy_markdown_link(node_path)
  local base = vim.fn.getcwd()
  local rel  = path.relative(node_path, base)
  local name = path.basename(node_path)
  yank("[" .. name .. "](" .. rel .. ")", "MD link")
end

---Copy a Markdown link using an absolute path.
---@param node_path string
function M.copy_markdown_link_abs(node_path)
  local name = path.basename(node_path)
  yank("[" .. name .. "](" .. node_path .. ")", "MD link (abs)")
end

---Run `action_fn` on the current tree node.
---@param action_fn fun(path: string)
local function on_current(action_fn)
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node then
    notify.warn("no node under cursor")
    return
  end
  action_fn(node.path)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreePathUtilsConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_path_utils", { clear = true })

  local km = _cfg.keymaps or {}

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = "neo-tree,NvimTree",
    callback = function(ev)
      local buf = ev.buf
      local function map(key, fn, desc)
        if key then
          vim.keymap.set("n", key, fn, { buffer = buf, silent = true, desc = "Filetree: " .. desc })
        end
      end
      map(km.copy_abs,   function() on_current(M.copy_absolute)        end, "copy abs path")
      map(km.copy_rel,   function() on_current(M.copy_relative)        end, "copy rel path")
      map(km.copy_name,  function() on_current(M.copy_name)            end, "copy filename")
      map(km.copy_dir,   function() on_current(M.copy_dir)             end, "copy dir")
      map(km.to_require, function() on_current(M.copy_as_require)      end, "copy as require()")
      map(km.md_link,    function() on_current(M.copy_markdown_link)   end, "copy markdown link")
    end,
  })
end

function M.teardown()
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
