---@module 'filetree.features.copy_move'
---@brief Filesystem clipboard: stage files for copy or cut, then paste.
---@description
--- Works like a vim register for files. Stage one or more nodes for copy
--- or cut, then paste them into any directory node.
---
--- Multiple-file staging uses the marks feature: if files are marked when
--- c/x is pressed, all marked files are staged at once.
---
--- Keymaps (in tree buffer):
---   c      Stage current node for copy (or all marked)
---   x      Stage current node for cut  (or all marked)
---   p      Paste staged files into the directory of the current node
---   P      Show the current clipboard
---   <C-c>  Clear the current clipboard
---
--- Extmark: staged-for-copy nodes get a "C" indicator, cut nodes get "X".

local notify = require("filetree.util.notify").create("[filetree.copy_move]")

local map         = require("filetree.util.map")
local au          = require("filetree.util.autocmd")
local buffer      = require("filetree.util.buffer")
local ui_select   = require("filetree.util.select")
local refs_util   = require("filetree.util.markdown_refs")
local refs_picker = require("filetree.util.refs_picker")

-- Central FS-mutation chokepoint (libuv-based, no shell). Retries transient
-- Windows sharing errors (EPERM/EACCES/EBUSY) that a raw uv.fs_copyfile would
-- surface as a hard failure — see the handle_guard plan.
local fsops = require("lib.nvim.cross.fs.mutate")

local M = {}

---@type FiletreeCopyMoveConfig
local _cfg = {
  enabled    = false,
  keymaps = {
    copy  = "c",
    cut   = "x",
    paste = "p",
    show  = "P",
    clear = "<C-c>",
  },
  confirm             = false,
  use_safety          = true,
  dry_run             = false,
  check_markdown_refs = true,
  refs_picker_prefer  = "auto",
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

---@type table<string, { await: fun(cb: fun(refs: table[])) }>  cut-path -> prefetch handle
local _cut_prefetch = {}

-- ── Clipboard state ───────────────────────────────────────────────────────────

local function clear_marks()
  local ok, marks = require("filetree.features").load("marks")
  if ok and marks then marks.clear_all() end
end

local function get_targets()
  -- Prefer marks if any are set
  local ok, marks = require("filetree.features").load("marks")
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

  -- For a cut (= move), start the markdown-reference scan NOW, while the
  -- sources still exist, so it overlaps with the time the user spends
  -- navigating to the paste target. Copies never break a reference (the
  -- original stays put), so only cuts prefetch. See refs_util.prefetch.
  _cut_prefetch = {}
  if op == "cut" and _cfg.check_markdown_refs and refs_util.available() then
    for _, p in ipairs(paths) do
      _cut_prefetch[p] = refs_util.prefetch(p)
    end
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

---Recursively copy a directory tree without shelling out (shell-agnostic:
---works identically whether &shell is cmd.exe, PowerShell, or a POSIX shell).
---@param src string
---@param dst string
---@return integer  0 on success, 1 on any failure
local function copy_dir(src, dst)
  if vim.fn.mkdir(dst, "p") == 0 then return 1 end
  for _, name in ipairs(vim.fn.readdir(src)) do
    local s = src .. "/" .. name
    local d = dst .. "/" .. name
    if vim.fn.isdirectory(s) == 1 then
      if copy_dir(s, d) ~= 0 then return 1 end
    else
      local ok = fsops.copy_file(s, d)
      if not ok then return 1 end
    end
  end
  return 0
end

local function do_copy(src, dst_dir)
  local name = vim.fn.fnamemodify(src, ":t")
  local dst  = dst_dir .. "/" .. name
  -- Avoid overwriting
  if vim.fn.filereadable(dst) == 1 or vim.fn.isdirectory(dst) == 1 then
    local ts = os.date("%H%M%S")
    dst = dst_dir .. "/" .. ts .. "_" .. name
  end

  if vim.fn.isdirectory(src) == 1 then
    return copy_dir(src, dst)
  else
    local ok = fsops.copy_file(src, dst)
    return ok and 0 or 1
  end
end

---@param src string
---@param dst_dir string
---@return integer rc   0 on success, 1 on failure
---@return string? dst  the destination path actually used, when rc == 0
local function do_move(src, dst_dir)
  local name = vim.fn.fnamemodify(src, ":t")
  local dst  = dst_dir .. "/" .. name
  if vim.fn.filereadable(dst) == 1 or vim.fn.isdirectory(dst) == 1 then
    notify.error("Target exists, cannot move: " .. dst)
    return 1
  end
  if vim.fn.rename(src, dst) ~= 0 then return 1 end
  return 0, dst
end

-- ── Markdown reference update (post-paste, cut items only) ─────────────────────
-- Same soft-dep + aggregated-chooser pattern as rename_batch: copies never
-- break a reference (the original stays put), only cuts (= moves) do.

---@param all_refs table[]  MarkdownFileRef[], each with `.new_target` pre-set.
local function handle_batch_markdown_refs(all_refs)
  if not _cfg.check_markdown_refs or #all_refs == 0 then return end

  local files = refs_util.unique_files(all_refs)
  notify.info(string.format(
    "%d markdown reference(s) found in: %s", #all_refs, table.concat(files, ", ")
  ))

  ui_select(
    {
      "✓  Update all references to their new paths",
      "◐  Inspect references first",
      "✗  Leave references as-is",
    },
    { prompt = string.format(" %d ref(s) across the moved item(s) ", #all_refs) },
    function(_, idx)
      if idx == 1 then
        refs_util.update(all_refs)
      elseif idx == 2 then
        refs_picker.pick(
          all_refs,
          { prefer = _cfg.refs_picker_prefer, title = "References across the moved item(s)" },
          function(selected) if #selected > 0 then refs_util.update(selected) end end,
          function() end
        )
      end
    end
  )
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
    local ok_s, safety = require("filetree.features").load("safety")
    if ok_s and safety then
      for _, e in ipairs(_clipboard) do
        pcall(safety.before_move, e.path, dst_dir .. "/" .. vim.fn.fnamemodify(e.path, ":t"))
      end
    end
  end

  -- Await the reference scans for cut items (started on stage_cut, so likely
  -- already done after the user navigated here). Captured while the sources
  -- still exist; the copy/move loop runs only inside the continuation, so no
  -- move happens before its item's scan has finished. Copies aren't scanned —
  -- the original stays put, so no reference breaks.
  local cut_handles = {}
  if _cfg.check_markdown_refs and refs_util.available() then
    for _, e in ipairs(_clipboard) do
      if e.op ~= "copy" then
        cut_handles[e.path] = _cut_prefetch[e.path] or refs_util.prefetch(e.path)
      end
    end
  end

  refs_util.await_all(cut_handles, function(refs_by_path)
    local errors  = 0
    local done    = 0
    local relocated = 0
    local all_refs  = {}
    for _, e in ipairs(_clipboard) do
      if e.op == "copy" then
        local rc = do_copy(e.path, dst_dir)
        if rc ~= 0 then errors = errors + 1 else done = done + 1 end
      else
        local rc, dst = do_move(e.path, dst_dir)
        if rc ~= 0 or not dst then
          errors = errors + 1
        else
          done = done + 1
          -- Repoint any open buffer(s) at the old path (or nested under it, for
          -- a moved directory) so a stale buffer for the file's old location
          -- doesn't linger alongside a second, disconnected buffer for its new
          -- one. Per-item, right after that item's own move succeeds, so a
          -- partial failure in a multi-item paste still fixes up the items that
          -- did succeed.
          relocated = relocated + buffer.relocate(e.path, dst)

          for _, r in ipairs(refs_by_path[e.path] or {}) do
            r.new_target = refs_util.retarget(r, dst)
            all_refs[#all_refs + 1] = r
          end
        end
      end
    end

    local msg = string.format("Pasted %d/%d item(s) into %s",
      done, #_clipboard, vim.fn.fnamemodify(dst_dir, ":t"))
    if relocated > 0 then
      msg = msg .. string.format(" (%d open buffer(s) repointed)", relocated)
    end
    notify.info(msg)

    handle_batch_markdown_refs(all_refs)

    -- Clear cut items from clipboard (keep copy items for potential re-paste)
    local remaining = {}
    for _, e in ipairs(_clipboard) do
      if e.op == "copy" then remaining[#remaining + 1] = e end
    end
    _clipboard = remaining
    _cut_prefetch = {}

    render_clipboard()
    if _adapter.refresh then pcall(_adapter.refresh) end
  end)
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

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_copy_move", true)

  local km = _cfg.keymaps or {}
  au.acmd("FileType", {
    group   = _augroup,
    pattern = "neo-tree,NvimTree",
    callback = function(ev)
      render_clipboard()
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local function bind(key, fn, desc)
          if key then
            map("n", key, fn, { buffer = buf, silent = true, desc = "Filetree: " .. desc })
          end
        end

        -- neo-tree's own native keymaps (y/x/p/...) are registered with a
        -- global `nowait = true`, which makes Vim resolve the ambiguity
        -- between a single-char native mapping and our own longer "yy"/"xx"
        -- sequence immediately in the native mapping's favour — the second
        -- keypress never gets a chance to complete the double-tap. Re-binding
        -- the bare prefix char to a plain <Nop> (no nowait) on this buffer
        -- overrides neo-tree's mapping and restores Vim's normal
        -- wait-for-more-input behaviour, making "yy"/"xx" reachable again.
        local function unblock_prefix(key, desc)
          if type(key) == "string" and #key == 2 and key:sub(1, 1) == key:sub(2, 2) then
            local prefix = key:sub(1, 1)
            if prefix ~= km.paste and prefix ~= km.show then
              map("n", prefix, "<Nop>", {
                buffer = buf, silent = true,
                desc   = "Filetree: unblock " .. desc .. " (" .. key .. ")",
              })
            end
          end
        end
        unblock_prefix(km.copy, "stage copy")
        unblock_prefix(km.cut,  "stage cut")

        bind(km.copy,  M.stage_copy, "stage copy")
        bind(km.cut,   M.stage_cut,  "stage cut")
        bind(km.paste, M.paste,      "paste clipboard")
        bind(km.show,  M.show,       "show clipboard")
        bind(km.clear, M.clear,      "clear clipboard")
      end)
    end,
  })

  au.acmd("BufEnter", {
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
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
