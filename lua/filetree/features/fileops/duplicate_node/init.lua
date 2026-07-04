---@module 'filetree.features.duplicate_node'
---@brief Duplicate the current file or directory with an interactive rename.
---@description
--- Copies the current node to a new name (same directory by default).
--- Prompts for the destination name. Integrates with the safety feature
--- to optionally backup before overwriting an existing target.
---
--- File copy:  platform-transparent via Lua io / vim.uv.fs_copyfile
--- Dir copy:   recursive via vim.system cp -r / xcopy (Windows)
---
--- Config:
---   enabled         boolean
---   keymap          string?   Key inside tree (default "<C-d>").
---   suffix          string    Default suffix appended to the copy name (default "_copy").
---   open_after      boolean   Open the new file after creation (default false).
---   confirm_overwrite boolean Warn before overwriting existing path (default true).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree duplicate

local notify   = require("filetree.util.notify").create("[filetree.duplicate_node]")
local platform = require("filetree.util.platform")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local ui_select = require("filetree.util.select")
local path    = require("filetree.util.path")
local bufutil = require("filetree.util.buffer")
local M = {}

---@type FiletreeDuplicateNodeConfig
local _cfg = {
  enabled           = false,
  keymap            = "<C-d>",
  suffix            = "_copy",
  open_after        = false,
  confirm_overwrite = true,
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Copy helpers ──────────────────────────────────────────────────────────────

local function copy_file(src, dst, cb)
  local uv = vim.uv or vim.loop
  uv.fs_copyfile(src, dst, {}, function(err)
    vim.schedule(function() cb(not err, err) end)
  end)
end

local function copy_dir(src, dst, cb)
  local cmd
  if platform.is_windows() then
    cmd = { "robocopy", src, dst, "/E", "/NFL", "/NDL", "/NJH", "/NJS" }
  else
    cmd = { "cp", "-r", "--", src, dst }
  end
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      -- robocopy exit codes 0-7 are success; cp 0 = success
      local ok = platform.is_windows() and result.code <= 7 or result.code == 0
      cb(ok, result.stderr)
    end)
  end)
end

-- ── Default name suggestion ───────────────────────────────────────────────────

local function suggest_name(src_path)
  local dir  = path.parent(src_path)
  local name = vim.fn.fnamemodify(src_path, ":t")

  if vim.fn.isdirectory(src_path) == 1 then
    return dir .. "/" .. name .. _cfg.suffix
  end

  local base = vim.fn.fnamemodify(name, ":r")
  local ext  = vim.fn.fnamemodify(name, ":e")
  local dest = dir .. "/" .. base .. _cfg.suffix
  if ext ~= "" then dest = dest .. "." .. ext end
  return dest
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.duplicate_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end

  local src      = node.path
  local is_dir   = vim.fn.isdirectory(src) == 1
  local default  = suggest_name(src)

  vim.ui.input({
    prompt  = "Duplicate to: ",
    default = path.slashify(default),
    completion = is_dir and "dir" or "file",
  }, function(dst)
    if not dst or dst == "" then return end
    dst = path.slashify(dst)  -- accept "/" or "\" from the user

    -- Confirm overwrite
    if _cfg.confirm_overwrite and
       (vim.fn.filereadable(dst) == 1 or vim.fn.isdirectory(dst) == 1) then
      ui_select({ "Overwrite", "Cancel" }, { prompt = "'" .. dst .. "' exists. " }, function(choice)
        if choice == "Overwrite" then M._do_copy(src, dst, is_dir) end
      end)
    else
      M._do_copy(src, dst, is_dir)
    end
  end)
end

function M._do_copy(src, dst, is_dir)
  local on_done = function(ok, err)
    if ok then
      notify.info("Duplicated → " .. vim.fn.fnamemodify(dst, ":t"))
      if _adapter and _adapter.refresh then _adapter.refresh() end
      if _cfg.open_after and not is_dir and vim.fn.filereadable(dst) == 1 then
        -- Open in a real editor window, never the tree window itself (loading
        -- a buffer into the tree's own window fights its window-management
        -- autocmds and can hang Neovim).
        local tree_win = _adapter and _adapter.get_winid and _adapter.get_winid()
        local win = bufutil.find_editor_win(tree_win)
        if win then vim.api.nvim_set_current_win(win) else vim.cmd("vsplit") end
        vim.cmd("edit " .. vim.fn.fnameescape(dst))
      end
    else
      notify.error("Duplicate failed: " .. (err or "unknown error"))
    end
  end

  if is_dir then copy_dir(src, dst, on_done)
  else       copy_file(src, dst, on_done) end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeDuplicateNodeConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_duplicate_node", true)

  if _cfg.keymap then
    au.acmd("FileType", {
      group   = _augroup,
      pattern = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap, M.duplicate_current, {
            buffer = buf, silent = true, desc = "Filetree: duplicate node",
          })
        end)
      end,
    })
  end
end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
