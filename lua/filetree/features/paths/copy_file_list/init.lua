---@module 'filetree.features.copy_file_list'
---@brief Copy recursive file/directory lists of the current node to clipboard.

local M = {}

---@type FiletreeCopyFileListConfig
local _cfg = {}
---@type FiletreeAdapter?
local _adapter = nil

local notify = require("filetree.util.notify").create("[filetree.copy_file_list]")
local fs = require("filetree.util.fs")
local ignore = require("filetree.util.ignore")
local bind = require("filetree.util.bind")

---Recursively collect all file paths under a path. Skips `.git`,
---`node_modules`, etc. per the ignore_list feature (see filetree.util.ignore).
---@param path string
---@param relative boolean  If true, make paths relative to cwd.
---@return string[]
local function collect_files(path, relative)
  local raw = fs.collect_files((path:gsub("\\", "/")), ignore.predicate())
  if not relative then
    return vim.tbl_map(function(p)
      return p:gsub("\\", "/")
    end, raw)
  end
  local cwd = vim.fn.getcwd():gsub("\\", "/"):gsub("/?$", "/")
  return vim.tbl_map(function(p)
    p = p:gsub("\\", "/")
    return p:gsub("^" .. vim.pesc(cwd), "")
  end, raw)
end

---Recursively collect all directory paths under a path (including root).
---Skips ignored subtrees; see `collect_files` above.
---@param path string
---@param relative boolean
---@return string[]
local function collect_dirs(path, relative)
  local raw = fs.collect_folders((path:gsub("\\", "/")), ignore.predicate())
  if not relative then
    return vim.tbl_map(function(p)
      return p:gsub("\\", "/")
    end, raw)
  end
  local cwd = vim.fn.getcwd():gsub("\\", "/"):gsub("/?$", "/")
  return vim.tbl_map(function(p)
    p = p:gsub("\\", "/")
    p = p:gsub("^" .. vim.pesc(cwd), "")
    return p == "" and "." or p
  end, raw)
end

---Write lines to clipboard and show notification.
---@param lines string[]
local function copy_to_reg(lines)
  if #lines == 0 then
    notify.warn("No entries found")
    return
  end

  local sep = _cfg.separator or "\n"
  local text = table.concat(lines, sep)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)

  local limit = _cfg.preview_limit or 5
  local preview = {}
  for i = 1, math.min(limit, #lines) do
    preview[#preview + 1] = "  " .. lines[i]
  end
  if #lines > limit then preview[#preview + 1] = "  ... (" .. (#lines - limit) .. " more)" end

  notify.info(string.format("Copied %d path(s):\n%s", #lines, table.concat(preview, "\n")))
end

---Get path of current node (file → itself, directory → itself).
---@return string?
local function current_path()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()
  if not node or not node.path then
    notify.warn("No current node")
    return nil
  end
  return node.path
end

function M.copy_files_abs()
  local path = current_path()
  if not path then return end
  copy_to_reg(collect_files(path, false))
end

function M.copy_files_rel()
  local path = current_path()
  if not path then return end
  copy_to_reg(collect_files(path, true))
end

function M.copy_dirs_abs()
  local path = current_path()
  if not path then return end
  if vim.fn.isdirectory(path) == 1 then
    copy_to_reg(collect_dirs(path, false))
  else
    -- File node: return just the parent directory
    copy_to_reg({ vim.fn.fnamemodify(path, ":h"):gsub("\\", "/") })
  end
end

function M.copy_dirs_rel()
  local path = current_path()
  if not path then return end
  if vim.fn.isdirectory(path) == 1 then
    copy_to_reg(collect_dirs(path, true))
  else
    -- File node: return just the parent directory (relative)
    local cwd = vim.fn.getcwd():gsub("\\", "/"):gsub("/?$", "/")
    local dir = vim.fn.fnamemodify(path, ":h"):gsub("\\", "/")
    dir = dir:gsub("^" .. vim.pesc(cwd), "")
    if dir == "" then dir = "." end
    copy_to_reg({ dir })
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type FiletreeCopyFileListConfig
local DEFAULTS = {
  keymap_files_abs = "[f",
  keymap_files_rel = "]f",
  keymap_dirs_abs = "[F",
  keymap_dirs_rel = "]F",
}

---@param cfg FiletreeCopyFileListConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg = vim.tbl_extend("force", DEFAULTS, cfg or {})
  cfg = _cfg
  _adapter = adapter

  bind.bind("copy_file_list", cfg, {
    {
      name = "files_abs",
      field = "keymap_files_abs",
      rhs = M.copy_files_abs,
      desc = "copy file list (abs)",
    },
    {
      name = "files_rel",
      field = "keymap_files_rel",
      rhs = M.copy_files_rel,
      desc = "copy file list (rel)",
    },
    {
      name = "dirs_abs",
      field = "keymap_dirs_abs",
      rhs = M.copy_dirs_abs,
      desc = "copy dir list (abs)",
    },
    {
      name = "dirs_rel",
      field = "keymap_dirs_rel",
      rhs = M.copy_dirs_rel,
      desc = "copy dir list (rel)",
    },
  })
end

function M.teardown()
  _adapter = nil
end

return M
