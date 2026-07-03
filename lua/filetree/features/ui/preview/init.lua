---@module 'filetree.features.preview'
---@brief File content preview + image/PDF dispatch triggered from the tree.
---@description
--- Two preview modes (config `mode`):
---
---   "buffer" (default) — show the file in the editor window (the non-tree
---     window). Moving the cursor over file nodes live-updates it, like
---     neo-tree's built-in preview. Focus stays in the tree. Toggling off (or
---     leaving the tree) restores the buffer that was there before.
---   "float"            — a floating window next to the tree showing the first
---     N lines / hex dump / directory listing. Auto-closes on leaving the tree.
---
--- Images and PDFs are dispatched to an external/inline viewer in both modes.
---
--- Keymaps (defaults):
---   <Tab>  — toggle preview; image/PDF dispatch for those file types.
---   <CR>   — image/PDF dispatch only; other nodes pass through to adapter's <CR>.

local notify     = require("filetree.util.notify").create("[filetree.preview]")
local platform   = require("filetree.util.platform")
local line_count = require("filetree.util.line_count")
local bufutil    = require("filetree.util.buffer")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreePreviewConfig
local _cfg = {
  enabled              = false,
  mode                 = "buffer",   -- "buffer" | "float"
  keymap               = "<Tab>",
  keymap_open          = "<CR>",
  max_lines            = 40,
  max_width            = 80,
  max_height           = 25,
  wrap                 = false,
  keymap_scroll_up     = "<C-b>",
  keymap_scroll_down   = "<C-f>",
  keymap_scroll_up10   = "<PageUp>",
  keymap_scroll_down10 = "<PageDown>",
  image = {
    backend = "auto",   -- "auto" | "snacks" | "image.nvim" | "system" | false
  },
  pdf = {
    backend = "pdfport",  -- "pdfport" | "system" | false
  },
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer?  current float preview window
local _win  = nil
---@type integer?  current float preview buffer
local _bufnr = nil

-- Buffer-mode state: preview shown inside an existing editor window.
---@type boolean
local _buf_active = false
---@type integer?  editor window used for buffer-mode preview
local _editor_win = nil
---@type integer?  buffer that was in _editor_win before preview started (to restore)
local _saved_buf = nil

-- ── File-type detection ───────────────────────────────────────────────────────

local _IMAGE_EXTS = {
  png=1, jpg=1, jpeg=1, gif=1, bmp=1, svg=1, webp=1,
  ico=1, tiff=1, tif=1, avif=1, heic=1,
}

local _PDF_EXTS = { pdf=1 }

local function ext(path)
  return (path:match("%.([^.]+)$") or ""):lower()
end

local function is_image(path) return _IMAGE_EXTS[ext(path)] == 1 end
local function is_pdf(path)   return _PDF_EXTS[ext(path)]   == 1 end

-- ── Cross-platform system-open ────────────────────────────────────────────────

local function system_open(path)
  local args
  if platform.is_windows() then
    args = { "cmd", "/c", "start", "", path:gsub("/", "\\") }
  elseif platform.is_mac() then
    args = { "open", path }
  elseif platform.is_wsl() or platform.has_executable("wslview") then
    args = { "wslview", path }
  else
    args = { "xdg-open", path }
  end
  local ok = vim.fn.jobstart(args, { detach = true })
  if not ok or ok <= 0 then
    notify.warn("Could not open in system app: " .. path)
  end
end

-- ── Image backend dispatch ────────────────────────────────────────────────────

local function open_image(path)
  local backend = (_cfg.image or {}).backend or "auto"
  if backend == false then return false end   -- caller falls through to text preview

  if backend == "snacks" or backend == "auto" then
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.image then
      local opened, _ = pcall(snacks.image.open, path)
      if opened then return true end
    end
    if backend == "snacks" then
      notify.warn("snacks.image not available — install folke/snacks.nvim")
      return true   -- don't fall through
    end
  end

  if backend == "image.nvim" or backend == "auto" then
    local ok2, img = pcall(require, "image")
    if ok2 and img.open then
      local opened2, _ = pcall(img.open, path)
      if opened2 then return true end
    end
    if backend == "image.nvim" then
      notify.warn("image.nvim not available — install 3rd/image.nvim")
      return true
    end
  end

  -- "system" or "auto" fallback
  system_open(path)
  return true
end

-- ── PDF backend dispatch ──────────────────────────────────────────────────────

local function open_pdf(path)
  local backend = (_cfg.pdf or {}).backend or "pdfport"
  if backend == false then return false end

  if backend == "pdfport" then
    local ok, pp = pcall(require, "pdfport")
    if ok and pp.open then
      local opened, err = pcall(pp.open, path)
      if opened then return true end
      notify.warn("pdfport.open failed: " .. tostring(err) .. " — falling back to system app")
    else
      notify.warn("pdfport.nvim not installed — opening PDF in system app")
    end
    system_open(path)
    return true
  end

  -- "system"
  system_open(path)
  return true
end

-- ── Text preview helpers ──────────────────────────────────────────────────────

local function is_binary(path)
  local e = ext(path)
  if line_count.is_binary_ext(e) then return true end
  -- Unknown extension: probe for null bytes
  local ok, data = pcall(vim.fn.readfile, path, "b", 1)
  if not ok or not data or #data == 0 then return false end
  local line = data[1]
  for i = 1, math.min(#line, 512) do
    if line:byte(i) == 0 then return true end
  end
  return false
end

local function hex_dump(path)
  local ok, data = pcall(vim.fn.readfile, path, "b", 16)
  if not ok then return { "(cannot read file)" } end
  local out = {}
  for i, l in ipairs(data) do
    local hex = {}
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
    local full   = path .. "/" .. e
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

  local max_w     = _cfg.max_width
  local content_w = 0
  for _, l in ipairs(lines) do content_w = math.max(content_w, #l) end
  local width  = math.max(math.min(content_w + 2, max_w), 20)
  local height = math.min(#lines + 1, _cfg.max_height)

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
  vim.api.nvim_set_option_value("wrap", _cfg.wrap, { win = _win })
  pcall(vim.api.nvim_win_set_cursor, _win, { 1, 0 })
end

-- ── Scroll helper ─────────────────────────────────────────────────────────────

---@param delta integer  positive = up (lower line numbers)
local function scroll_preview(delta)
  if not (_win and vim.api.nvim_win_is_valid(_win)) then return end
  local buf   = vim.api.nvim_win_get_buf(_win)
  local total = vim.api.nvim_buf_line_count(buf)
  local cur   = vim.api.nvim_win_get_cursor(_win)[1]
  local next  = math.max(1, math.min(total, cur - delta))
  pcall(vim.api.nvim_win_set_cursor, _win, { next, 0 })
end

-- ── Buffer-mode preview (show file in the editor window) ────────────────────────

---Editor window to preview into: not the tree window, holds a normal buffer.
---@return integer?
local function editor_target()
  local tree_win = _adapter and _adapter.get_winid and _adapter.get_winid() or nil
  return bufutil.find_editor_win(tree_win)
end

---Display `path` in the buffer-mode editor window without stealing focus.
---@param path string
local function buf_show(path)
  local win = _editor_win
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  if vim.fn.filereadable(path) ~= 1 then return end
  local b = vim.fn.bufadd(path)
  vim.fn.bufload(b)                              -- triggers filetype/syntax
  pcall(vim.api.nvim_win_set_buf, win, b)        -- set buffer, focus stays in tree
end

---Stop buffer-mode preview. When `restore` is true, put the original buffer back.
---@param restore boolean
local function buf_stop(restore)
  if restore and _editor_win and vim.api.nvim_win_is_valid(_editor_win)
     and _saved_buf and vim.api.nvim_buf_is_valid(_saved_buf) then
    pcall(vim.api.nvim_win_set_buf, _editor_win, _saved_buf)
  end
  _buf_active = false
  _editor_win = nil
  _saved_buf  = nil
end

---Start buffer-mode preview for `node`, remembering the editor window's buffer.
---@param node FiletreeNode
local function buf_start(node)
  local win = editor_target()
  if not win then
    notify.warn("no editor window to preview into")
    return
  end
  _editor_win = win
  _saved_buf  = vim.api.nvim_win_get_buf(win)
  _buf_active = true
  if node and node.path and node.path ~= "" and vim.fn.isdirectory(node.path) ~= 1 then
    buf_show(node.path)
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Toggle text/dir preview in the configured mode.
function M.toggle()
  if not _adapter then return end

  if _cfg.mode == "float" then
    if _win and vim.api.nvim_win_is_valid(_win) then
      close_preview()
      return
    end
    local node = _adapter.get_current_node()
    if not node then notify.warn("no node under cursor"); return end
    open_preview(node)
    return
  end

  -- buffer mode
  if _buf_active then
    buf_stop(true)
    return
  end
  local node = _adapter.get_current_node()
  if not node then notify.warn("no node under cursor"); return end
  buf_start(node)
end

---Dispatch for <Tab>: image/PDF open, text preview toggle for everything else.
function M.toggle_or_open()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path or node.path == "" then
    notify.warn("no node under cursor")
    return
  end

  local cfg_img = _cfg.image or {}
  local cfg_pdf = _cfg.pdf   or {}

  if cfg_img.backend ~= false and is_image(node.path) then
    close_preview()   -- close any open text preview first
    open_image(node.path)
    return
  end

  if cfg_pdf.backend ~= false and is_pdf(node.path) then
    close_preview()
    open_pdf(node.path)
    return
  end

  -- Text / directory preview (toggle)
  M.toggle()
end

---Dispatch for <CR>: image/PDF open; calls `fallback` for other nodes.
---@param fallback function?
function M.open_or_fallback(fallback)
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path or node.path == "" then
    if fallback then fallback() end
    return
  end

  local cfg_img = _cfg.image or {}
  local cfg_pdf = _cfg.pdf   or {}

  if cfg_img.backend ~= false and is_image(node.path) then
    open_image(node.path)
    return
  end

  if cfg_pdf.backend ~= false and is_pdf(node.path) then
    open_pdf(node.path)
    return
  end

  if fallback then fallback() end
end

function M.close()
  close_preview()
  buf_stop(true)
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

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_preview", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = "neo-tree,NvimTree",
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end

        -- <Tab>: toggle text preview, or dispatch image/PDF
        if _cfg.keymap then
          map("n", _cfg.keymap, M.toggle_or_open, {
            buffer = buf, silent = true, desc = "Filetree: preview / open image or PDF",
          })
        end

        -- <CR>: image/PDF dispatch; save and call neotree's original <CR> for other nodes
        if _cfg.keymap_open then
          local original_cr_cb = nil
          for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
            if m.lhs == _cfg.keymap_open then
              original_cr_cb = m.callback
              break
            end
          end

          map("n", _cfg.keymap_open, function()
            M.open_or_fallback(original_cr_cb)
          end, {
            buffer = buf, silent = true,
            desc   = "Filetree: open image/PDF, or adapter default",
          })
        end

        -- Scroll keymaps — only in float mode (they'd shadow the tree's own
        -- <C-b>/<C-f>/<PageUp>/<PageDown> otherwise, and buffer mode has no float
        -- to scroll; focus the editor window to scroll a buffer preview).
        if _cfg.mode == "float" then
          local scroll_keys = {
            { _cfg.keymap_scroll_up,     1  },
            { _cfg.keymap_scroll_down,   -1 },
            { _cfg.keymap_scroll_up10,   10 },
            { _cfg.keymap_scroll_down10, -10 },
          }
          for _, pair in ipairs(scroll_keys) do
            local key, delta = pair[1], pair[2]
            if key then
              map("n", key, function() scroll_preview(delta) end, {
                buffer = buf, silent = true,
                desc   = "Filetree: scroll preview " .. (delta > 0 and "up" or "down"),
              })
            end
          end
        end
      end)
    end,
  })

  -- Leaving the tree ends the preview. Float: close it. Buffer: deactivate but
  -- keep the shown file (the user is moving into the editor to use it); toggling
  -- off from inside the tree is what restores the original buffer.
  au.acmd({ "BufLeave", "WinLeave" }, {
    group   = _augroup,
    pattern = "*",
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft == "neo-tree" or ft == "NvimTree" then
        if _cfg.mode == "float" then
          close_preview()
        elseif _buf_active then
          buf_stop(false)
        end
      end
    end,
  })

  -- Live-update the preview as the cursor moves over tree nodes.
  au.acmd("CursorMoved", {
    group   = _augroup,
    pattern = "*",
    callback = function()
      local ft = vim.bo.filetype
      if ft ~= "neo-tree" and ft ~= "NvimTree" then return end
      local node = _adapter and _adapter.get_current_node()
      if not node then return end

      if _cfg.mode == "float" then
        if _win and vim.api.nvim_win_is_valid(_win) then open_preview(node) end
      elseif _buf_active then
        if node.path and node.path ~= "" and vim.fn.isdirectory(node.path) ~= 1 then
          buf_show(node.path)
        end
      end
    end,
  })
end

function M.teardown()
  close_preview()
  buf_stop(true)
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
