---@module 'filetree.features.recent_files'
---@brief MRU (most-recently-used) file list with persistent JSON storage.
---@description
--- Tracks every file opened in the editor via BufEnter autocmd.
--- Shows a floating picker (same style as bookmarks) with the most recent
--- files first. Selecting a file opens it in the editor and optionally
--- reveals it in the tree.
---
--- Files that no longer exist are pruned automatically when the picker opens.
--- Directories, special buffers (terminal, nofile), and explicitly excluded
--- glob patterns are never recorded.
---
--- Storage: stdpath("data")/filetree/recent_files.json
---
--- User commands: :FiletreeRecentFiles
--- Keymap:        configurable global (default nil) + optional tree keymap

local notify = require("filetree.util.notify").create("[filetree.recent_files]")

local M = {}

---@type FiletreeRecentFilesConfig
local _cfg = {
  enabled      = false,
  max_files    = 100,
  keymap_tree  = "r",
  keymap_global = nil,
  reveal_on_open = true,
  exclude      = {
    "*/%.git/*",
    "*/node_modules/*",
    "filetree://.*",
  },
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Storage ───────────────────────────────────────────────────────────────────

---@class RecentFileEntry
---@field path     string
---@field visited  integer  Unix timestamp of last visit.

local _store_path = ""

---@type RecentFileEntry[]
local _files = {}

local function ensure_dir()
  local dir = vim.fn.fnamemodify(_store_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end
end

local function load()
  if vim.fn.filereadable(_store_path) == 0 then return end
  local ok, content = pcall(vim.fn.readfile, _store_path)
  if not ok or not content or #content == 0 then return end
  local jok, data = pcall(vim.fn.json_decode, table.concat(content, "\n"))
  if jok and type(data) == "table" then _files = data end
end

local function save()
  ensure_dir()
  local ok, enc = pcall(vim.fn.json_encode, _files)
  if ok then pcall(vim.fn.writefile, { enc }, _store_path) end
end

-- ── Recording ─────────────────────────────────────────────────────────────────

local function is_excluded(path)
  for _, pat in ipairs(_cfg.exclude) do
    if path:match(pat) then return true end
  end
  return false
end

local function record(path)
  if not path or path == "" then return end
  if vim.fn.filereadable(path) == 0 then return end
  if is_excluded(path) then return end

  -- Remove existing entry for this path
  for i, e in ipairs(_files) do
    if e.path == path then table.remove(_files, i); break end
  end

  -- Prepend (most recent first)
  table.insert(_files, 1, { path = path, visited = os.time() })

  -- Trim
  while #_files > _cfg.max_files do
    table.remove(_files, #_files)
  end

  save()
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Open the recent files floating picker.
function M.show()
  -- Prune non-existent files
  local pruned = {}
  for _, e in ipairs(_files) do
    if vim.fn.filereadable(e.path) == 1 then
      pruned[#pruned + 1] = e
    end
  end
  _files = pruned

  if #_files == 0 then
    notify.info("No recent files recorded")
    return
  end

  local lines   = {}
  local entries = {}
  for i, e in ipairs(_files) do
    local name = vim.fn.fnamemodify(e.path, ":t")
    local dir  = vim.fn.fnamemodify(e.path, ":~:h")
    local ts   = os.date("%m-%d %H:%M", e.visited)
    lines[i]   = string.format(" [%3d]  %-30s  %s  (%s)", i, name, dir, ts)
    entries[i] = e
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = " <CR> open  |  d delete  |  q close"

  local width  = 0
  for _, l in ipairs(lines) do width = math.max(width, #l + 2) end
  width  = math.min(width, math.floor(vim.o.columns * 0.9))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.7))

  local row = math.floor((vim.o.lines   - height) / 2)
  local col = math.floor((vim.o.columns - width)  / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  vim.api.nvim_set_option_value("buftype",    "nofile", { buf = bufnr })

  local win = vim.api.nvim_open_win(bufnr, true, {
    relative  = "editor",
    row = row, col = col, width = width, height = height,
    style = "minimal", border = "rounded",
    title = " Recent Files ", title_pos = "center",
  })

  local close = function()
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end

  local open_entry = function()
    local idx   = vim.api.nvim_win_get_cursor(win)[1]
    local entry = entries[idx]
    if not entry then return end
    close()
    vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
    if _cfg.reveal_on_open and _adapter and _adapter.reveal then
      vim.defer_fn(function() pcall(_adapter.reveal, entry.path) end, 50)
    end
  end

  local delete_entry = function()
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    if entries[idx] then
      for i, e in ipairs(_files) do
        if e.path == entries[idx].path then table.remove(_files, i); break end
      end
      save()
    end
    close()
    vim.schedule(M.show)
  end

  local opts = { buffer = bufnr, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>",  open_entry,   opts)
  vim.keymap.set("n", "d",     delete_entry, opts)
  vim.keymap.set("n", "q",     close,        opts)
  vim.keymap.set("n", "<Esc>", close,        opts)

  -- Number-jump: press 1-9 to jump to that entry
  for i = 1, 9 do
    vim.keymap.set("n", tostring(i), function()
      if entries[i] then
        close()
        vim.cmd("edit " .. vim.fn.fnameescape(entries[i].path))
        if _cfg.reveal_on_open and _adapter and _adapter.reveal then
          vim.defer_fn(function() pcall(_adapter.reveal, entries[i].path) end, 50)
        end
      end
    end, opts)
  end
end

---Return the list of recent file entries.
---@return RecentFileEntry[]
function M.get_all()
  return _files
end

---Clear all recent file history.
function M.clear()
  _files = {}
  save()
  notify.info("Recent files cleared")
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeRecentFilesConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg        = vim.tbl_deep_extend("force", _cfg, config)
  _adapter    = adapter
  _store_path = vim.fn.stdpath("data") .. "/filetree/recent_files.json"

  load()

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_recent_files", { clear = true })

  -- Record every normal buffer open
  vim.api.nvim_create_autocmd("BufEnter", {
    group    = _augroup,
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" then return end
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if path and path ~= "" then record(path) end
    end,
  })

  -- Tree keymap
  if _cfg.keymap_tree then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.keymap.set("n", _cfg.keymap_tree, M.show, {
            buffer = buf, silent = true, desc = "Filetree: show recent files",
          })
        end)
      end,
    })
  end

  -- Global keymap
  if _cfg.keymap_global then
    vim.keymap.set("n", _cfg.keymap_global, M.show, {
      silent = true, desc = "Filetree: show recent files",
    })
  end

end

function M.teardown()
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
  if _cfg.keymap_global then
    pcall(vim.keymap.del, "n", _cfg.keymap_global)
  end
end

return M
