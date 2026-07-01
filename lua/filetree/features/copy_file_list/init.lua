---@module 'filetree.features.copy_file_list'
---@brief Copy recursive file/directory lists of the current node to clipboard.

local M = {}

---@type FiletreeCopyFileListConfig
local _cfg = {}
---@type FiletreeAdapter?
local _adapter = nil

local notify = require("filetree.util.notify").create("[filetree.copy_file_list]")
local fs     = require("filetree.util.fs")

---Recursively collect all file paths under a path.
---@param path string
---@param relative boolean  If true, make paths relative to cwd.
---@return string[]
local function collect_files(path, relative)
  local raw = fs.collect_files(path:gsub("\\", "/"))
  if not relative then
    return vim.tbl_map(function(p) return p:gsub("\\", "/") end, raw)
  end
  local cwd = vim.fn.getcwd():gsub("\\", "/"):gsub("/?$", "/")
  return vim.tbl_map(function(p)
    p = p:gsub("\\", "/")
    return p:gsub("^" .. vim.pesc(cwd), "")
  end, raw)
end

---Recursively collect all directory paths under a path (including root).
---@param path string
---@param relative boolean
---@return string[]
local function collect_dirs(path, relative)
  local raw = fs.collect_folders(path:gsub("\\", "/"))
  if not relative then
    return vim.tbl_map(function(p) return p:gsub("\\", "/") end, raw)
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
  if #lines > limit then
    preview[#preview + 1] = "  ... (" .. (#lines - limit) .. " more)"
  end

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
  keymap_dirs_abs  = "[F",
  keymap_dirs_rel  = "]F",
}

---@param cfg FiletreeCopyFileListConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg     = vim.tbl_extend("force", DEFAULTS, cfg or {})
  cfg      = _cfg
  _adapter = adapter

  local keymaps = {
    { key = cfg.keymap_files_abs, fn = M.copy_files_abs, desc = "filetree: copy file list (abs)" },
    { key = cfg.keymap_files_rel, fn = M.copy_files_rel, desc = "filetree: copy file list (rel)" },
    { key = cfg.keymap_dirs_abs,  fn = M.copy_dirs_abs,  desc = "filetree: copy dir list (abs)"  },
    { key = cfg.keymap_dirs_rel,  fn = M.copy_dirs_rel,  desc = "filetree: copy dir list (rel)"  },
  }

  local function set_keymaps(buf)
    for _, km in ipairs(keymaps) do
      if km.key then
        vim.keymap.set("n", km.key, km.fn, { buffer = buf, desc = km.desc, silent = true })
      end
    end
  end

  local winid = adapter.get_winid and adapter.get_winid()
  if winid then
    set_keymaps(vim.api.nvim_win_get_buf(winid))
  else
    vim.api.nvim_create_autocmd("FileType", {
      pattern  = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          set_keymaps(buf)
        end)
      end,
    })
  end
end

function M.teardown()
  _adapter = nil
end

return M
