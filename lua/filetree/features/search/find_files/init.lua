---@module 'filetree.features.search.find_files'
--- Fuzzy-find files within the tree root, then reveal the result.
---
--- Detects available fuzzy finders in order:
---   1. telescope.nvim  (nvim-telescope/telescope.nvim)
---   2. fzf-lua         (ibhagwan/fzf-lua)
---   3. mini.pick       (echasnovski/mini.pick)
---   4. vim.ui.select   (built-in fallback, uses vim.fn.glob)
---
--- The search root is (in priority order):
---   - The directory of the current tree node
---   - Whatever `filetree.util.root` resolves: cwd_mode's held root (lock /
---     project), else the project root, else vim.fn.getcwd()
---
--- After selection, the file is opened in the editor and optionally
--- revealed in the tree via adapter.reveal().
---
--- Keymaps (default): "<leader>ff" global, "f" inside tree buffer.
--- User command:      :FiletreeFindFiles

local notify = require("filetree.util.notify").create("[filetree.find_files]")

local map = require("filetree.util.map")
local tree_attach = require("filetree.util.tree_attach")
local ui_select = require("filetree.util.select")
local ignore = require("filetree.util.ignore")
local M = {}

-- Optional: shows a "scanning…" indicator for the builtin backend's
-- vim.fn.globpath() walk, which can take a while under a large root and has
-- no other feedback otherwise. No-op (returns nil) when lib.nvim isn't
-- installed — the scan still runs, just without the indicator.
local ok_progress, progress_mod = pcall(require, "lib.nvim.progress")
---@internal
---@return table?
local function new_progress()
  if not ok_progress then return nil end
  return progress_mod.create({ title = "[filetree.find_files]" })
end

---@type FiletreeFindFilesConfig
local _cfg = {
  enabled          = false,
  keymap_tree      = "f",
  keymap_telescope = "tf",
  keymap_global    = nil,
  prefer           = "auto",  -- "auto"|"telescope"|"fzf-lua"|"mini.pick"|"builtin"
  reveal_on_open   = true,
  hidden           = false,
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Root resolution ───────────────────────────────────────────────────────────

---@internal
---Resolve the search root: the given node's directory, or the project/cwd
---root via `filetree.util.root`.
---@param from_node FiletreeNode?
---@return string
local function get_root(from_node)
  if from_node then
    return from_node.type == "directory"
      and from_node.path
      or vim.fn.fnamemodify(from_node.path, ":h")
  end
  -- util.root asks cwd_mode's held root first, then falls back to the same
  -- project_root → getcwd() chain this used to spell out. Without that, a
  -- locked session searching from a buffer that belongs to another project
  -- would find files in that other project.
  return require("filetree.util.root").find()
end

-- ── Post-select action ────────────────────────────────────────────────────────

---@internal
---Open the selected file and optionally reveal it in the tree.
---@param path string?
local function on_select(path)
  if not path or path == "" then return end
  if vim.fn.filereadable(path) == 0 then
    notify.warn("file not readable: " .. path)
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  if _cfg.reveal_on_open and _adapter and _adapter.reveal then
    vim.defer_fn(function() pcall(_adapter.reveal, path) end, 50)
  end
end

-- ── Backends ──────────────────────────────────────────────────────────────────

---@internal
---Find files via telescope.nvim. Returns false when telescope isn't installed.
---@param root string
---@return boolean handled
local function via_telescope(root)
  local ok, tel = pcall(require, "telescope.builtin")
  if not ok then return false end
  tel.find_files({
    cwd            = root,
    hidden         = _cfg.hidden,
    attach_mappings = function(_, map_fn)
      local actions = require("telescope.actions")
      local state   = require("telescope.actions.state")
      map_fn("i", "<CR>", function(prompt_bufnr)
        local sel = state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then on_select(sel.path or (root .. "/" .. sel[1])) end
      end)
      return true
    end,
  })
  return true
end

---@internal
---Find files via fzf-lua. Returns false when fzf-lua isn't installed.
---@param root string
---@return boolean handled
local function via_fzflua(root)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return false end
  fzf.files({
    cwd     = root,
    hidden  = _cfg.hidden,
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          on_select(root .. "/" .. selected[1])
        end
      end,
    },
  })
  return true
end

---@internal
---Find files via mini.pick. Returns false when mini.pick isn't installed.
---@param root string
---@return boolean handled
local function via_minipick(root)
  local ok, mp = pcall(require, "mini.pick")
  if not ok then return false end
  mp.builtin.files({ tool = "rg" }, {
    source = { cwd = root },
    mappings = {
      choose = function(item)
        if item then on_select(root .. "/" .. item) end
      end,
    },
  })
  return true
end

---True if any path segment of `rel` (root-relative, "/"-separated) is on the
---ignore list (`.git`, `node_modules`, …). globpath already expanded the
---whole tree in one call, so this can't prune the walk itself the way
---`fs.collect_recursive`'s `ignore_fn` does -- it only keeps ignored entries
---out of the results shown to the user.
---@internal
---@param rel string
---@param ignored fun(name: string): boolean
---@return boolean
local function path_is_ignored(rel, ignored)
  for seg in rel:gmatch("[^/\\]+") do
    if ignored(seg) then return true end
  end
  return false
end

---@internal
---Find files via vim.fn.globpath + vim.ui.select (dependency-free fallback).
---@param root string
---@return boolean handled
local function via_builtin(root)
  -- vim.fn.glob all files, present via vim.ui.select
  local prog = new_progress()
  if prog then prog:update({ text = "scanning " .. root .. "…" }) end

  local pattern = _cfg.hidden and root .. "/**/*" or root .. "/**/*"
  local ok_g, files = pcall(vim.fn.globpath, root, "**/*", false, true)
  if not ok_g then files = {} end
  -- filter to files only, skip ignored subtrees (.git, node_modules, …), limit to 10000
  local ignored = ignore.predicate()
  local root_len = #root + 2
  local filtered = {}
  local total = #files
  for i, f in ipairs(files) do
    if vim.fn.filereadable(f) == 1 and not path_is_ignored(f:sub(root_len), ignored) then
      filtered[#filtered + 1] = f
      if #filtered >= 10000 then break end
    end
    if prog and i % 500 == 0 then
      prog:update({ current = i, total = total })
    end
  end

  if prog then prog:finish(string.format("%d file(s) found under %s", #filtered, root)) end

  if #filtered == 0 then
    notify.warn("No files found in: " .. root)
    return true
  end
  -- Relativize for display
  local display = {}
  for _, f in ipairs(filtered) do
    display[#display + 1] = f:sub(root_len)
  end
  ui_select(display, {
    prompt = "Find files: ",
    format_item = function(item) return item end,
  }, function(choice, idx)
    if choice and idx then on_select(filtered[idx]) end
  end)
  return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Open the fuzzy finder rooted at `root` (or auto-detected if nil).
---@param root? string
function M.find(root)
  local node = _adapter and _adapter.get_current_node()
  root = root or get_root(node)

  local prefer = _cfg.prefer or "auto"
  if prefer == "telescope" then via_telescope(root); return end
  if prefer == "fzf-lua"   then via_fzflua(root);   return end
  if prefer == "mini.pick" then via_minipick(root);  return end
  if prefer == "builtin"   then via_builtin(root);   return end

  -- auto
  if not via_telescope(root) and not via_fzflua(root) and not via_minipick(root) then
    via_builtin(root)
  end
end

---Force telescope specifically, regardless of the configured `prefer` backend.
---@param root? string
function M.find_telescope(root)
  local node = _adapter and _adapter.get_current_node()
  root = root or get_root(node)
  if not via_telescope(root) then
    notify.warn("telescope.nvim not available")
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeFindFilesConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  -- Keymap inside tree
  if _cfg.keymap_tree then
    tree_attach.on_attach(function(buf)
      map("n", _cfg.keymap_tree, M.find, {
        buffer = buf,
        silent = true,
        desc   = "Filetree: find files from current node",
      })
      if _cfg.keymap_telescope then
        map("n", _cfg.keymap_telescope, M.find_telescope, {
          buffer = buf,
          silent = true,
          desc   = "Filetree: find files via telescope specifically",
        })
      end
    end)
  end

  -- Optional global keymap
  if _cfg.keymap_global then
    map("n", _cfg.keymap_global, M.find, {
      silent = true,
      desc   = "Filetree: find files",
    })
  end

end

function M.teardown()
  _adapter = nil
  if _cfg.keymap_global then
    pcall(vim.keymap.del, "n", _cfg.keymap_global)
  end
end

return M
