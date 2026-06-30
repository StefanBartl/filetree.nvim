---@module 'filetree.features.copy_file_list'
---@brief Copy recursive file/directory lists of the current node to clipboard.

local M = {}

---@type FiletreeCopyFileListConfig
local _cfg = {}
---@type FiletreeAdapter?
local _adapter = nil

local notify = require("filetree.util.notify").create("[filetree.copy_file_list]")

---Recursively collect all file paths under a path.
---@param path string
---@param relative boolean  If true, make paths relative to cwd.
---@return string[]
local function collect_files(path, relative)
  local cwd = relative and (vim.fn.getcwd():gsub("\\", "/"):gsub("/?$", "/")) or nil
  local results = {}

  local function recurse(p)
    if vim.fn.isdirectory(p) == 1 then
      local entries = vim.fn.readdir(p)
      if entries then
        for _, e in ipairs(entries) do
          recurse(p .. "/" .. e)
        end
      end
    else
      local norm = p:gsub("\\", "/")
      if cwd then
        norm = norm:gsub("^" .. vim.pesc(cwd), "")
      end
      results[#results + 1] = norm
    end
  end

  recurse(path:gsub("\\", "/"))
  return results
end

---Recursively collect all directory paths under a path.
---@param path string
---@param relative boolean
---@return string[]
local function collect_dirs(path, relative)
  local cwd = relative and (vim.fn.getcwd():gsub("\\", "/"):gsub("/?$", "/")) or nil
  local results = {}

  local function recurse(p)
    if vim.fn.isdirectory(p) == 1 then
      local norm = p:gsub("\\", "/")
      if cwd then
        norm = norm:gsub("^" .. vim.pesc(cwd), "")
      end
      -- Don't add the root itself, only children
      if norm ~= path:gsub("\\", "/") then
        results[#results + 1] = norm
      end
      local entries = vim.fn.readdir(p)
      if entries then
        for _, e in ipairs(entries) do
          recurse(p .. "/" .. e)
        end
      end
    end
  end

  recurse(path:gsub("\\", "/"))
  return results
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
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
  copy_to_reg(collect_dirs(dir, false))
end

function M.copy_dirs_rel()
  local path = current_path()
  if not path then return end
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
  copy_to_reg(collect_dirs(dir, true))
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param cfg FiletreeCopyFileListConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg     = cfg
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
      callback = function(ev) set_keymaps(ev.buf) end,
    })
  end
end

function M.teardown()
  _adapter = nil
end

return M
