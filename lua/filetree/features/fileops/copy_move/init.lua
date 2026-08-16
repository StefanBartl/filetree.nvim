---@module 'filetree.features.fileops.copy_move'
--- Filesystem clipboard: stage files for copy or cut, then paste.
---
--- Works like a vim register for files. Stage one or more nodes for copy
--- or cut, then paste them into any directory node.
---
--- Multiple-file staging uses the marks feature: if files are marked when
--- c/x is pressed, all marked files are staged at once.
---
--- If any staged item's name already exists at the paste target, a
--- kit.confirm prompt asks how to resolve the whole batch before anything
--- is written: Overwrite / Keep both (auto-renamed) / Skip / Cancel. See
--- `paste_resolving_conflicts` and `find_conflicts`.
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
local tree_attach = require("filetree.util.tree_attach")
local buffer      = require("filetree.util.buffer")
local confirm_choice = require("filetree.util.confirm_choice")
local ui_confirm  = require("filetree.util.confirm")
local refs_util   = require("filetree.util.markdown_refs")
local refs_picker = require("filetree.util.refs_picker")
-- Optional: progress indicator for a multi-item paste. No-op (returns nil)
-- when lib.nvim isn't installed.
local progress    = require("filetree.util.progress")

-- Central FS-mutation chokepoint (libuv-based, no shell). Retries transient
-- Windows sharing errors (EPERM/EACCES/EBUSY) that a raw uv.fs_copyfile would
-- surface as a hard failure — see the handle_guard plan.
local fsops = require("lib.nvim.cross.fs.mutate")
-- On a transient lock during a move, release neo-tree's watcher on the source
-- so the retry can proceed. No-op unless handle_guard installed the registry.
local watch = require("lib.nvim.neotree.watch")

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

---@internal
local function clear_marks()
  local ok, marks = require("filetree.features").load("marks")
  if ok and marks then marks.clear_all() end
end

---@internal
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

---@internal
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

---@internal
---Whether a path already exists as either a file or a directory.
---@param path string
---@return boolean
local function exists(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

---@internal
---Remove an existing file or directory outright — the "Overwrite" conflict
---resolution's prep step, run just before the copy/move that replaces it.
---No shell involved.
---@param path string
---@return boolean ok
local function remove_existing(path)
  if vim.fn.isdirectory(path) == 1 then
    return vim.fn.delete(path, "rf") == 0
  end
  return vim.fn.delete(path) == 0
end

---@internal
---First "name (N).ext" that collides with neither an existing path in
---`dst_dir` nor a name already handed out earlier in the same paste batch
---(`claimed`). Directories don't get extension-splitting -- a dir name has
---no extension to preserve.
---@param dst_dir string
---@param name string
---@param claimed table<string, true>
---@param is_dir boolean
---@return string
local function unique_name(dst_dir, name, claimed, is_dir)
  local base, ext
  if not is_dir then
    base, ext = name:match("^(.*)(%.[^./\\]+)$")
  end
  if not base or base == "" then
    base, ext = name, ""
  end
  local candidate, n = name, 2
  repeat
    candidate = string.format("%s (%d)%s", base, n, ext)
    n = n + 1
  until not claimed[candidate] and not exists(dst_dir .. "/" .. candidate)
  claimed[candidate] = true
  return candidate
end

---@internal
---Clipboard entries whose name would collide with an existing entry of
---`dst_dir` if pasted as-is. Purely a preflight check -- the authoritative
---existence check happens again at execution time in `do_paste_impl`, right
---before each item is actually written.
---@param dst_dir string
---@return ClipboardEntry[]
local function find_conflicts(dst_dir)
  local conflicts = {}
  for _, e in ipairs(_clipboard) do
    if exists(dst_dir .. "/" .. vim.fn.fnamemodify(e.path, ":t")) then
      conflicts[#conflicts + 1] = e
    end
  end
  return conflicts
end

---@internal
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

---@internal
---Copy `src` to the already-resolved destination `dst` -- no collision
---handling here, the caller has already decided how to deal with an
---existing target before calling this.
---@param src string
---@param dst string
---@return integer rc  0 on success, 1 on failure
local function do_copy(src, dst)
  if vim.fn.isdirectory(src) == 1 then
    return copy_dir(src, dst)
  end
  local ok = fsops.copy_file(src, dst)
  return ok and 0 or 1
end

---@internal
---Move `src` to the already-resolved destination `dst`.
---@param src string
---@param dst string
---@return integer rc   0 on success, 1 on failure
---@return string? dst  the destination path actually used, when rc == 0
local function do_move(src, dst)
  -- A move is the primary Windows lock trigger (an open neo-tree watcher on the
  -- source dir holds the handle), so route it through the retrying mutation
  -- chokepoint. But uv.fs_rename cannot cross filesystems/drives — it returns
  -- EXDEV, which is not a transient error and so is not retried. vim.fn.rename
  -- can (it copies+deletes internally), so fall back to it for exactly that
  -- case: the cross-drive move keeps working (no retry protection, but a
  -- cross-drive paste is rare), while the common same-drive move gets the
  -- EPERM/EACCES/EBUSY retry it actually needs.
  local ok, err = fsops.rename_file(src, dst, {
    on_retry = function() watch.release(src) end,
  })
  if not ok then
    if type(err) == "string" and err:match("^EXDEV") then
      if vim.fn.rename(src, dst) == 0 then return 0, dst end
    end
    return 1
  end
  return 0, dst
end

-- ── Markdown reference update (post-paste, cut items only) ─────────────────────
-- Same soft-dep + aggregated-chooser pattern as rename_batch: copies never
-- break a reference (the original stays put), only cuts (= moves) do.

---@internal
---@param all_refs table[]  MarkdownFileRef[], each with `.new_target` pre-set.
local function handle_batch_markdown_refs(all_refs)
  if not _cfg.check_markdown_refs or #all_refs == 0 then return end

  local files = refs_util.unique_files(all_refs)
  notify.info(string.format(
    "%d markdown reference(s) found in: %s", #all_refs, table.concat(files, ", ")
  ))

  confirm_choice(
    string.format("%d ref(s) across the moved item(s)", #all_refs),
    { "Update all refs", "Inspect first", "Leave as-is" },
    function(choice)
      if choice == "Update all refs" then
        refs_util.update(all_refs)
      elseif choice == "Inspect first" then
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

---@internal
---Actually perform an already-confirmed paste into `dst_dir`.
---@param dst_dir string
---@param conflict_mode? "Overwrite"|"Keep both"|"Skip"  How to resolve an
---  item whose name already exists at the destination. Set only when
---  `find_conflicts` found at least one during the preflight scan and the
---  user picked a resolution for the batch; nil means none were found (in
---  which case a target that turns out to exist anyway at execution time —
---  a race since the scan — is treated as an error, not a silent guess).
local function do_paste_impl(dst_dir, conflict_mode)
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
    local prog = progress.create({ title = "[filetree.copy_move]" })
    local errors    = 0
    local done      = 0
    local skipped   = 0
    local relocated = 0
    local all_refs  = {}
    local moved     = {} -- entry -> true, once its cut has actually landed
    local claimed   = {} -- names already handed out by "Keep both" this batch

    for i, e in ipairs(_clipboard) do
      if prog then
        prog:update({ text = vim.fn.fnamemodify(e.path, ":t"), current = i - 1, total = #_clipboard })
      end
      local name = vim.fn.fnamemodify(e.path, ":t")
      local dst  = dst_dir .. "/" .. name

      if exists(dst) then
        if conflict_mode == "Overwrite" then
          if _cfg.use_safety then
            local ok_s, safety = require("filetree.features").load("safety")
            if ok_s and safety then pcall(safety.before_delete, dst) end
          end
          if not remove_existing(dst) then
            notify.error("Could not clear existing target: " .. dst)
            errors = errors + 1
            dst = nil
          end
        elseif conflict_mode == "Keep both" then
          local is_dir = vim.fn.isdirectory(e.path) == 1
          dst = dst_dir .. "/" .. unique_name(dst_dir, name, claimed, is_dir)
        elseif conflict_mode == "Skip" then
          skipped = skipped + 1
          dst = nil
        else
          notify.error("Target exists, skipping: " .. dst)
          errors = errors + 1
          dst = nil
        end
      end

      if dst then
        if e.op == "copy" then
          local rc = do_copy(e.path, dst)
          if rc ~= 0 then errors = errors + 1 else done = done + 1 end
        else
          local rc, moved_dst = do_move(e.path, dst)
          if rc ~= 0 or not moved_dst then
            errors = errors + 1
          else
            done = done + 1
            moved[e] = true
            -- Repoint any open buffer(s) at the old path (or nested under it, for
            -- a moved directory) so a stale buffer for the file's old location
            -- doesn't linger alongside a second, disconnected buffer for its new
            -- one. Per-item, right after that item's own move succeeds, so a
            -- partial failure in a multi-item paste still fixes up the items that
            -- did succeed.
            relocated = relocated + buffer.relocate(e.path, moved_dst)

            for _, r in ipairs(refs_by_path[e.path] or {}) do
              r.new_target = refs_util.retarget(r, moved_dst)
              all_refs[#all_refs + 1] = r
            end
          end
        end
      end
    end

    local msg = string.format("Pasted %d/%d item(s) into %s",
      done, #_clipboard, vim.fn.fnamemodify(dst_dir, ":t"))
    if skipped > 0 then
      msg = msg .. string.format(" (%d skipped)", skipped)
    end
    if relocated > 0 then
      msg = msg .. string.format(" (%d open buffer(s) repointed)", relocated)
    end
    if prog then prog:finish(msg) end
    notify.info(msg)

    handle_batch_markdown_refs(all_refs)

    -- Clear clipboard entries that actually landed: copy items always stay
    -- (kept for potential re-paste); cut items only clear once their move
    -- has actually happened, so a skipped or failed cut stays staged for
    -- the user to resolve and paste again instead of vanishing silently.
    local remaining = {}
    for _, e in ipairs(_clipboard) do
      if e.op == "copy" or not moved[e] then remaining[#remaining + 1] = e end
    end
    _clipboard = remaining
    _cut_prefetch = {}

    render_clipboard()
    if _adapter.refresh then pcall(_adapter.refresh) end
  end)
end

---@internal
---Preflight-check `dst_dir` for name collisions; if any exist, ask the user
---once how to resolve the whole batch (Overwrite / Keep both / Skip /
---Cancel) before touching the filesystem. No conflicts -> straight to paste,
---same as before this feature existed.
---@param dst_dir string
local function paste_resolving_conflicts(dst_dir)
  local conflicts = find_conflicts(dst_dir)
  if #conflicts == 0 then
    do_paste_impl(dst_dir)
    return
  end

  local names = {}
  for _, e in ipairs(conflicts) do
    names[#names + 1] = vim.fn.fnamemodify(e.path, ":t")
  end

  confirm_choice(
    string.format("%d item(s) already exist in %s:\n  %s",
      #conflicts, vim.fn.fnamemodify(dst_dir, ":t"), table.concat(names, ", ")),
    { "Overwrite", "Keep both", "Skip", "Cancel" },
    function(choice)
      if choice == nil or choice == "Cancel" then
        notify.info("Paste cancelled")
        return
      end
      do_paste_impl(dst_dir, choice)
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
    ui_confirm({
      question = string.format(
        "Paste %d item(s) into %s?", #_clipboard, vim.fn.fnamemodify(dst_dir, ":~")),
      on_choice = function(yes)
        if not yes then notify.info("Cancelled"); return end
        paste_resolving_conflicts(dst_dir)
      end,
    })
    return
  end

  paste_resolving_conflicts(dst_dir)
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
  tree_attach.on_attach(function(buf)
    render_clipboard()
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
