---@module 'filetree.features.bookmarks'
---@brief Persistent file/directory bookmarks across Neovim sessions.
---@description
--- Unlike marks (in-session, in-tree), bookmarks persist to JSON and can be
--- jumped to from anywhere — not just from within the tree buffer.
---
--- API:
---   M.toggle(path, label?)   Add or remove a bookmark.
---   M.toggle_current()       Toggle bookmark for the current tree node.
---   M.add(path, label?)      Add a bookmark.
---   M.remove(path)           Remove a bookmark by path.
---   M.get_all()              Return all FiletreeBookmark entries.
---   M.is_bookmarked(path)    Return true/false.
---   M.show()                 Open a floating picker window.
---   M.clear_all()            Remove all bookmarks.
---
--- User commands:
---   :FiletreeBookmarksShow
---   :FiletreeBookmarksClear
---
--- Keymap (in tree buffer): "b" toggles bookmark on current node.
--- Extmark indicator: "★" rendered at eol.

local notify = require("filetree.util.notify").create("[filetree.bookmarks]")
local store  = require("filetree.features.bookmarks.store")

local M = {}

---@type FiletreeBookmarksConfig
local _cfg = {
  enabled   = false,
  indicator = "★",
  hl_group  = "DiagnosticHint",
  keymap    = "b",
  persist   = true,
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace id
local _ns = -1

-- ── Extmark rendering ─────────────────────────────────────────────────────────

local function render_buf(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not _adapter or not _adapter.get_node_at_line then return end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for linenr = 0, line_count - 1 do
    local node = _adapter.get_node_at_line(bufnr, linenr)
    if node and store.find(node.path) then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, -1, {
        virt_text     = { { " " .. _cfg.indicator, _cfg.hl_group } },
        virt_text_pos = "eol",
        priority      = 90,
      })
    end
  end
end

local function render_all()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr >= 0 then render_buf(bufnr) end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---@param path    string
---@param label?  string
function M.add(path, label)
  store.add(path, label)
  render_all()
  notify.info("Bookmarked: " .. vim.fn.fnamemodify(path, ":t"))
end

---@param path string
function M.remove(path)
  store.remove(path)
  render_all()
  notify.info("Removed bookmark: " .. vim.fn.fnamemodify(path, ":t"))
end

---@param path   string
---@param label? string
function M.toggle(path, label)
  if store.find(path) then
    M.remove(path)
  else
    M.add(path, label)
  end
end

function M.toggle_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node then
    notify.warn("no node under cursor")
    return
  end
  M.toggle(node.path)
end

---@param path string
---@return boolean
function M.is_bookmarked(path)
  return store.find(path) ~= nil
end

---@return FiletreeBookmark[]
function M.get_all()
  return store.all()
end

function M.clear_all()
  store.clear()
  render_all()
  notify.info("All bookmarks cleared")
end

-- ── Floating picker ───────────────────────────────────────────────────────────

function M.show()
  local bookmarks = store.all()
  if #bookmarks == 0 then
    notify.info("No bookmarks saved")
    return
  end

  local lines   = {}
  local entries = {}

  for i, bm in ipairs(bookmarks) do
    local label = bm.label or vim.fn.fnamemodify(bm.path, ":t")
    local date  = os.date("%Y-%m-%d", bm.added)
    lines[i]    = string.format(" [%d] %s  %s  (%s)", i, _cfg.indicator, label, date)
    entries[i]  = bm
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = " <Enter> open  |  d delete  |  q close"

  local width  = 0
  for _, l in ipairs(lines) do width = math.max(width, #l + 2) end
  width = math.min(width, 80)
  local height = math.min(#lines, 20)

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })

  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row      = row,
    col      = col,
    width    = width,
    height   = height,
    style    = "minimal",
    border   = "rounded",
    title    = " Bookmarks ",
    title_pos = "center",
  })

  local close = function()
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end

  local open_entry = function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local idx    = cursor[1]
    local entry  = entries[idx]
    if not entry then return end
    close()
    -- Reveal in tree and open in editor
    if _adapter and _adapter.reveal then
      _adapter.reveal(entry.path)
    end
    if vim.fn.filereadable(entry.path) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
    end
  end

  local delete_entry = function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local idx    = cursor[1]
    local entry  = entries[idx]
    if not entry then return end
    M.remove(entry.path)
    close()
    vim.schedule(M.show)  -- reopen updated list
  end

  local opts = { buffer = bufnr, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", open_entry,    opts)
  vim.keymap.set("n", "d",    delete_entry,  opts)
  vim.keymap.set("n", "q",    close,         opts)
  vim.keymap.set("n", "<Esc>",close,         opts)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeBookmarksConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter
  _ns      = vim.api.nvim_create_namespace("filetree_bookmarks")

  if _cfg.persist then store.load() end

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_bookmarks", { clear = true })

  if _cfg.keymap then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        render_buf(ev.buf)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.keymap.set("n", _cfg.keymap, M.toggle_current, {
            buffer  = buf,
            silent  = true,
            desc    = "Filetree: toggle bookmark on current node",
          })
        end)
      end,
    })
  end

  -- Re-render when entering or refreshing the tree
  vim.api.nvim_create_autocmd("BufEnter", {
    group   = _augroup,
    pattern = "*",
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft == "neo-tree" or ft == "NvimTree" then
        render_buf(ev.buf)
      end
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
