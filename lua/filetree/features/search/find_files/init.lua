---@module 'filetree.features.find_files'
---@brief Fuzzy-find files within the tree root, then reveal the result.
---@description
--- Detects available fuzzy finders in order:
---   1. telescope.nvim  (nvim-telescope/telescope.nvim)
---   2. fzf-lua         (ibhagwan/fzf-lua)
---   3. mini.pick       (echasnovski/mini.pick)
---   4. vim.ui.select   (built-in fallback, uses vim.fn.glob)
---
--- The search root is (in priority order):
---   - The directory of the current tree node
---   - The project root (if project_root feature is loaded)
---   - vim.fn.getcwd()
---
--- After selection, the file is opened in the editor and optionally
--- revealed in the tree via adapter.reveal().
---
--- Keymaps (default): "<leader>ff" global, "f" inside tree buffer.
--- User command:      :FiletreeFindFiles

local notify = require("filetree.util.notify").create("[filetree.find_files]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local ui_select = require("filetree.util.select")
local M = {}

---@type FiletreeFindFilesConfig
local _cfg = {
  enabled         = false,
  keymap_tree     = "f",
  keymap_global   = nil,
  prefer          = "auto",  -- "auto"|"telescope"|"fzf-lua"|"mini.pick"|"builtin"
  reveal_on_open  = true,
  hidden          = false,
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Root resolution ───────────────────────────────────────────────────────────

local function get_root(from_node)
  if from_node then
    return from_node.type == "directory"
      and from_node.path
      or vim.fn.fnamemodify(from_node.path, ":h")
  end
  local ok_pr, pr = require("filetree.features").load("project_root")
  if ok_pr and type(pr.find) == "function" then
    local buf  = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    return pr.find(name ~= "" and name or vim.fn.getcwd())
  end
  return vim.fn.getcwd()
end

-- ── Post-select action ────────────────────────────────────────────────────────

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

local function via_builtin(root)
  -- vim.fn.glob all files, present via vim.ui.select
  local pattern = _cfg.hidden and root .. "/**/*" or root .. "/**/*"
  local ok_g, files = pcall(vim.fn.globpath, root, "**/*", false, true)
  if not ok_g then files = {} end
  -- filter to files only, limit to 10000
  local filtered = {}
  for _, f in ipairs(files) do
    if vim.fn.filereadable(f) == 1 then
      filtered[#filtered + 1] = f
      if #filtered >= 10000 then break end
    end
  end
  if #filtered == 0 then
    notify.warn("No files found in: " .. root)
    return true
  end
  -- Relativize for display
  local display = {}
  local root_len = #root + 2
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

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeFindFilesConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_find_files", true)

  -- Keymap inside tree
  if _cfg.keymap_tree then
    au.acmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap_tree, M.find, {
            buffer = buf,
            silent = true,
            desc   = "Filetree: find files from current node",
          })
        end)
      end,
    })
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
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
  if _cfg.keymap_global then
    pcall(vim.keymap.del, "n", _cfg.keymap_global)
  end
end

return M
