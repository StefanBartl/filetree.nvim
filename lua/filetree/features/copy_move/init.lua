---@module 'filetree.features.copy_move'
---@brief Filesystem clipboard: stage files for copy or cut, then paste.
---@description
--- Works like a vim register for files. Stage one or more nodes for copy
--- or cut, then paste them into any directory node.
---
--- Multiple-file staging uses the marks feature: if files are marked when
--- yy/xx is pressed, all marked files are staged at once.
---
--- Keymaps (in tree buffer):
---   yy   Stage current node for copy (or all marked)
---   xx   Stage current node for cut  (or all marked)
---   p    Paste staged files into the directory of the current node
---   P    Show / clear the current clipboard
---
--- Extmark: staged-for-copy nodes get a "C" indicator, cut nodes get "X".

local notify = require("filetree.util.notify").create("[filetree.copy_move]")

local M = {}

---@type FiletreeCopyMoveConfig
local _cfg = {
  enabled    = false,
  keymaps = {
    copy  = "yy",
    cut   = "xx",
    paste = "p",
    show  = "P",
  },
  confirm    = true,
  use_safety = true,
  dry_run    = false,
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace
local _ns = -1

---@alias ClipboardOp "copy"|"cut"

---@class ClipboardEntry
---@field path string
---@field op   ClipboardOp

---@type ClipboardEntry[]
local _clipboard = {}

-- ── Clipboard state ───────────────────────────────────────────────────────────

local function clear_marks()
  local ok, marks = pcall(require, "filetree.features.marks")
  if ok and marks then marks.clear_all() end
end

local function get_targets()
  -- Prefer marks if any are set
  local ok, marks = pcall(require, "filetree.features.marks")
  if ok and marks and marks.count() > 0 then
    return marks.get_marked()
  end
  -- Fall back to current node
  if not _adapter then return {} end
  local node = _adapter.get_current_node()
  return node and { node.path } or {}
end

local function render_clipboard()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if #_clipboard == 0 then return end

  -- Build lookup
  local staged = {}
  for _, e in ipairs(_clipboard) do
    staged[e.path] = e.op
  end

  if not _adapter.get_node_at_line then return end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for linenr = 0, line_count - 1 do
    local node = _adapter.get_node_at_line(bufnr, linenr)
    if node then
      local op = staged[node.path]
      if op then
        local text = op == "copy" and " C" or " X"
        local hl   = op == "copy" and "DiagnosticHint" or "DiagnosticWarn"
        pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, -1, {
          virt_text     = { { text, hl } },
          virt_text_pos = "eol",
          priority      = 80,
        })
      end
    end
  end
end

-- ── Stage ─────────────────────────────────────────────────────────────────────

---@param op ClipboardOp
function M.stage(op)
  local paths = get_targets()
  if #paths == 0 then
    notify.warn("no node selected")
    return
  end
  _clipboard = {}
  for _, p in ipairs(paths) do
    _clipboard[#_clipboard + 1] = { path = p, op = op }
  end
  clear_marks()
  render_clipboard()
  local verb = op == "copy" and "Copied" or "Cut"
  notify.info(string.format("%s %d item(s) to clipboard", verb, #paths))
end

function M.stage_copy() M.stage("copy") end
function M.stage_cut()  M.stage("cut")  end

function M.clear()
  _clipboard = {}
  render_clipboard()
  notify.info("Clipboard cleared")
end

function M.show()
  if #_clipboard == 0 then
    notify.info("Clipboard is empty")
    return
  end
  local lines = { string.format("Clipboard (%d items):", #_clipboard), "" }
  for _, e in ipairs(_clipboard) do
    lines[#lines + 1] = string.format("  [%s] %s", e.op:upper():sub(1,1),
      vim.fn.fnamemodify(e.path, ":~"))
  end
  notify.info(table.concat(lines, "\n"))
end

-- ── Paste ─────────────────────────────────────────────────────────────────────

local function do_copy(src, dst_dir)
  local name = vim.fn.fnamemodify(src, ":t")
  local dst  = dst_dir .. "/" .. name
  -- Avoid overwriting
  if vim.fn.filereadable(dst) == 1 or vim.fn.isdirectory(dst) == 1 then
    local ts = os.date("%H%M%S")
    dst = dst_dir .. "/" .. ts .. "_" .. name
  end

  local is_dir = vim.fn.isdirectory(src) == 1
  local cmd
  if vim.fn.has("win32") == 1 then
    if is_dir then
      cmd = string.format('xcopy /E /I /Y "%s" "%s"', src, dst)
    else
      cmd = string.format('copy /Y "%s" "%s"', src, dst)
    end
    return vim.fn.system(cmd)
  else
    if is_dir then
      cmd = { "cp", "-r", src, dst }
    else
      cmd = { "cp", src, dst }
    end
    local result = vim.system(cmd):wait()
    return result.code == 0 and 0 or 1
  end
end

local function do_move(src, dst_dir)
  local name = vim.fn.fnamemodify(src, ":t")
  local dst  = dst_dir .. "/" .. name
  if vim.fn.filereadable(dst) == 1 or vim.fn.isdirectory(dst) == 1 then
    notify.error("Target exists, cannot move: " .. dst)
    return 1
  end
  return vim.fn.rename(src, dst) == 0 and 0 or 1
end

function M.paste()
  if #_clipboard == 0 then
    notify.warn("Clipboard is empty")
    return
  end
  if not _adapter then return end

  local node = _adapter.get_current_node()
  local dst_dir
  if node then
    dst_dir = node.type == "directory"
      and node.path
      or vim.fn.fnamemodify(node.path, ":h")
  else
    dst_dir = vim.fn.getcwd()
  end

  if _cfg.dry_run then
    local lines = { "-- Paste plan (dry-run) --", "  → " .. dst_dir }
    for _, e in ipairs(_clipboard) do
      lines[#lines + 1] = "  [" .. e.op .. "] " .. vim.fn.fnamemodify(e.path, ":t")
    end
    notify.info(table.concat(lines, "\n"))
    return
  end

  if _cfg.confirm then
    local ans = vim.fn.input(string.format(
      "Paste %d item(s) into %s? [y/N] ", #_clipboard, vim.fn.fnamemodify(dst_dir, ":~")))
    if ans:lower() ~= "y" then notify.info("Cancelled"); return end
  end

  if _cfg.use_safety then
    local ok_s, safety = pcall(require, "filetree.features.safety")
    if ok_s and safety then
      for _, e in ipairs(_clipboard) do
        pcall(safety.before_move, e.path, dst_dir .. "/" .. vim.fn.fnamemodify(e.path, ":t"))
      end
    end
  end

  local errors = 0
  local done   = 0
  for _, e in ipairs(_clipboard) do
    local rc
    if e.op == "copy" then
      rc = do_copy(e.path, dst_dir)
    else
      rc = do_move(e.path, dst_dir)
    end
    if rc ~= 0 then errors = errors + 1 else done = done + 1 end
  end

  notify.info(string.format("Pasted %d/%d item(s) into %s",
    done, #_clipboard, vim.fn.fnamemodify(dst_dir, ":t")))

  -- Clear cut items from clipboard (keep copy items for potential re-paste)
  local remaining = {}
  for _, e in ipairs(_clipboard) do
    if e.op == "copy" then remaining[#remaining + 1] = e end
  end
  _clipboard = remaining

  render_clipboard()
  if _adapter.refresh then pcall(_adapter.refresh) end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeCopyMoveConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter
  _ns      = vim.api.nvim_create_namespace("filetree_copy_move")

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_copy_move", { clear = true })

  local km = _cfg.keymaps or {}
  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = "neo-tree,NvimTree",
    callback = function(ev)
      render_clipboard()
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local function map(key, fn, desc)
          if key then
            vim.keymap.set("n", key, fn, { buffer = buf, silent = true, desc = "Filetree: " .. desc })
          end
        end
        map(km.copy,  M.stage_copy, "stage copy")
        map(km.cut,   M.stage_cut,  "stage cut")
        map(km.paste, M.paste,      "paste clipboard")
        map(km.show,  M.show,       "show clipboard")
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group   = _augroup,
    pattern = "*",
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft == "neo-tree" or ft == "NvimTree" then render_clipboard() end
    end,
  })
end

function M.teardown()
  _clipboard = {}
  _adapter   = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
