---@module 'filetree.features.preview'
---@brief Floating file content preview triggered from the tree.
---@description
--- Opens a floating window showing the content of the file under the cursor.
--- Auto-closes when the cursor leaves the tree buffer or the preview window.
---
--- Supported content:
---   Text files:   first N lines with syntax highlight via filetype detection.
---   Binary files: hex dump of the first 256 bytes.
---   Images:       metadata summary (size, format).
---   Directories:  lists immediate children.
---
--- Keymap (default): <Tab> in tree buffer.

local notify = require("filetree.util.notify").create("[filetree.preview]")

local M = {}

---@type FiletreePreviewConfig
local _cfg = {
  enabled    = false,
  keymap     = "<Tab>",
  max_lines  = 40,
  max_width  = 80,
  max_height = 25,
  wrap       = false,
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer?  current preview window
local _win  = nil
---@type integer?  current preview buffer
local _bufnr = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function is_binary(path)
  local ok, data = pcall(vim.fn.readfile, path, "b", 1)
  if not ok or not data or #data == 0 then return false end
  local line = data[1]
  for i = 1, math.min(#line, 512) do
    local b = line:byte(i)
    if b == 0 then return true end
  end
  return false
end

local function hex_dump(path)
  local ok, data = pcall(vim.fn.readfile, path, "b", 16)
  if not ok then return { "(cannot read file)" } end
  local out = {}
  for i, l in ipairs(data) do
    local hex  = {}
    for j = 1, #l do hex[#hex + 1] = string.format("%02x", l:byte(j)) end
    out[i] = table.concat(hex, " ")
  end
  out[#out + 1] = "(binary — first 16 lines as hex)"
  return out
end

local function read_text(path)
  local ok, lines = pcall(vim.fn.readfile, path, "", _cfg.max_lines)
  if not ok then return { "(cannot read file)" } end
  return lines
end

local function list_dir(path)
  local ok, entries = pcall(vim.fn.readdir, path)
  if not ok then return { "(cannot list directory)" } end
  table.sort(entries)
  local out = { "Directory: " .. path, "" }
  for _, e in ipairs(entries) do
    local full = path .. "/" .. e
    local prefix = vim.fn.isdirectory(full) == 1 and "  /" or "   "
    out[#out + 1] = prefix .. e
  end
  return out
end

-- ── Preview window ────────────────────────────────────────────────────────────

local function close_preview()
  if _win and vim.api.nvim_win_is_valid(_win) then
    pcall(vim.api.nvim_win_close, _win, true)
  end
  if _bufnr and vim.api.nvim_buf_is_valid(_bufnr) then
    pcall(vim.api.nvim_buf_delete, _bufnr, { force = true })
  end
  _win   = nil
  _bufnr = nil
end

local function open_preview(node)
  close_preview()

  local path   = node.path
  local is_dir = vim.fn.isdirectory(path) == 1
  local lines, ft

  if is_dir then
    lines = list_dir(path)
    ft    = ""
  elseif is_binary(path) then
    lines = hex_dump(path)
    ft    = ""
  else
    lines = read_text(path)
    ft    = vim.filetype.match({ filename = path }) or ""
  end

  -- Clamp dimensions
  local max_w = _cfg.max_width
  local content_w = 0
  for _, l in ipairs(lines) do content_w = math.max(content_w, #l) end
  local width  = math.max(math.min(content_w + 2, max_w), 20)
  local height = math.min(#lines + 1, _cfg.max_height)

  -- Position: to the right of the cursor column if space allows, else left
  local cur_win = vim.api.nvim_get_current_win()
  local win_pos = vim.api.nvim_win_get_position(cur_win)
  local win_w   = vim.api.nvim_win_get_width(cur_win)
  local cur_row = vim.api.nvim_win_get_cursor(cur_win)[1] - 1

  local col = win_pos[2] + win_w + 1
  if col + width > vim.o.columns then
    col = math.max(0, win_pos[2] - width - 1)
  end
  local row = math.max(0, win_pos[1] + cur_row - math.floor(height / 2))
  row = math.min(row, vim.o.lines - height - 3)

  _bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(_bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = _bufnr })
  vim.api.nvim_set_option_value("buftype",    "nofile", { buf = _bufnr })
  if ft ~= "" then
    pcall(vim.api.nvim_set_option_value, "filetype", ft, { buf = _bufnr })
  end
  vim.api.nvim_set_option_value("wrap", _cfg.wrap, { buf = _bufnr })

  _win = vim.api.nvim_open_win(_bufnr, false, {
    relative  = "editor",
    row       = row,
    col       = col,
    width     = width,
    height    = height,
    style     = "minimal",
    border    = "rounded",
    title     = " " .. vim.fn.fnamemodify(path, ":t") .. " ",
    title_pos = "center",
    focusable = false,
  })

  vim.api.nvim_set_option_value("winhl",
    "Normal:NormalFloat,FloatBorder:FloatBorder", { win = _win })
end

-- ── Toggle action ─────────────────────────────────────────────────────────────

function M.toggle()
  if _win and vim.api.nvim_win_is_valid(_win) then
    close_preview()
    return
  end
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node then
    notify.warn("no node under cursor")
    return
  end
  open_preview(node)
end

function M.close()
  close_preview()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreePreviewConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_preview", { clear = true })

  if _cfg.keymap then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.keymap.set("n", _cfg.keymap, M.toggle, {
            buffer = buf,
            silent = true,
            desc   = "Filetree: toggle file preview",
          })
        end)
      end,
    })
  end

  -- Auto-close when leaving tree buffer
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group   = _augroup,
    pattern = "*",
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft == "neo-tree" or ft == "NvimTree" then
        close_preview()
      end
    end,
  })

  -- Update preview when cursor moves in tree
  vim.api.nvim_create_autocmd("CursorMoved", {
    group   = _augroup,
    pattern = "*",
    callback = function()
      if not (_win and vim.api.nvim_win_is_valid(_win)) then return end
      local ft = vim.bo.filetype
      if ft == "neo-tree" or ft == "NvimTree" then
        local node = _adapter and _adapter.get_current_node()
        if node then open_preview(node) end
      end
    end,
  })
end

function M.teardown()
  close_preview()
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
