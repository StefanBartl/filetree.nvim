---@module 'filetree.refs.apply'
--- Writing reference updates back, and undoing them.
---
--- Every change is **content-verified**: a ref carries the byte range
--- (`col` … `col + #target - 1`) it occupied in the line at scan time, and the
--- rewrite only happens when that exact slice still holds `target`. A line that
--- drifted since the scan (unsaved edits, a second tool writing the file) is
--- skipped, never guessed at.
---
--- Files that are open in a buffer are patched in the **buffer**: Neovim does
--- not reload a buffer when its file changes on disk until a checktime fires,
--- so writing only to disk would leave the user staring at stale text. If that
--- buffer had no unsaved changes the patch is written straight back to disk
--- (keeping it unmodified and in sync); if it did, the buffer is left modified
--- and disk is untouched — the user's own edits win.
---
--- Each apply pushes one entry onto an undo stack (`:Filetree refs undo`),
--- holding the pre-change content of every line it touched.

local scan = require("filetree.refs.scan")

-- Optional: a wide symbol rename (`:Filetree refs`) rewrites every referencing
-- file — buffer patch or readfile/writefile per file. Over a large project
-- that is a multi-second freeze with no feedback. No-op without lib.nvim.
local progress = require("filetree.util.progress")

local M = {}

--- Files rewritten per event-loop tick in the async path. A file here costs a
--- `readfile`/`writefile` pair (or a buffer round-trip), so this is smaller
--- than a pure-scan chunk. A set this size or smaller is applied synchronously
--- (no scheduling, no indicator) to keep a small rename's timing unchanged.
local APPLY_CHUNK_SIZE = 8

---@class FiletreeRefsUndoToken
---@field id      integer  Stable handle, valid until the token is undone or trimmed off the stack.
---@field entries FiletreeRefsUndoEntry[]
---@field count   integer  refs applied
---@field files   integer  files changed
---@field label   string

---@type FiletreeRefsUndoToken[]
local _undo_stack = {}

--- Monotonic id source for undo tokens.
---
--- A caller that wants to undo *its own* apply later (trash's `U`, which has
--- to revert the `REF!` markers belonging to exactly the delete it restores)
--- cannot use stack positions: another apply pushed in the meantime moves
--- them, and `M.undo` always takes the top. An id survives both.
local _next_id = 0

---How many reference rewrites stay undoable via `:Filetree refs undo`.
---
---Same class of preference as trash's history: the stack holds the previous
---content of rewritten lines, which is small. `refs.undo_depth`.
---@return integer
local function undo_depth()
  local ok, refs = pcall(require, "filetree.refs")
  if not ok or type(refs.config) ~= "function" then return 10 end
  local n = (refs.config() or {}).undo_depth
  return (type(n) == "number" and n > 0) and n or 10
end

-- ── Line rewriting ────────────────────────────────────────────────────────────

---@internal
---Rewrite one ref inside `line`. Returns the new line, or nil when the line no
---longer holds `target` at the recorded column (stale ref → skip).
---
---`col == 0` marks a ref whose provider could not give a column (e.g. one
---handed over by an external source); those fall back to replacing the first
---literal occurrence of `target` in the line.
---@param line string
---@param ref FiletreeRef
---@return string|nil
local function rewrite(line, ref)
  if not ref.new_target or ref.new_target == ref.target then return nil end

  local col = ref.col or 0
  if col > 0 then
    if line:sub(col, col + #ref.target - 1) == ref.target then
      return line:sub(1, col - 1) .. ref.new_target .. line:sub(col + #ref.target)
    end
    return nil
  end

  local s, e = line:find(ref.target, 1, true)
  if not s then return nil end
  return line:sub(1, s - 1) .. ref.new_target .. line:sub(e + 1)
end

---@internal
---Apply every ref belonging to one line, right to left so an earlier
---replacement never invalidates a later ref's column.
---@param line string
---@param refs FiletreeRef[]
---@return string new_line, integer applied
local function rewrite_line(line, refs)
  table.sort(refs, function(a, b)
    return (a.col or 0) > (b.col or 0)
  end)
  local applied = 0
  for _, ref in ipairs(refs) do
    local new_line = rewrite(line, ref)
    if new_line then
      line = new_line
      applied = applied + 1
    end
  end
  return line, applied
end

---@internal
---Group refs by file, then by line.
---@param refs FiletreeRef[]
---@return table<string, table<integer, FiletreeRef[]>>
local function group(refs)
  local by_file = {}
  for _, r in ipairs(refs) do
    local per_file = by_file[r.file]
    if not per_file then
      per_file = {}
      by_file[r.file] = per_file
    end
    local per_line = per_file[r.line]
    if not per_line then
      per_line = {}
      per_file[r.line] = per_line
    end
    per_line[#per_line + 1] = r
  end
  return by_file
end

-- ── Public API ────────────────────────────────────────────────────────────────

---@internal
---Rewrite every ref belonging to one file — in its buffer if it is open,
---otherwise straight on disk. Returns how many refs landed and the pre-change
---content of every line it touched (for the undo stack).
---@param file string
---@param by_line table<integer, FiletreeRef[]>
---@return integer file_applied, table<integer, string> before
local function apply_file(file, by_line)
  local bufnr = scan.buffer_for(file)
  local before = {} ---@type table<integer, string>
  local file_applied = 0

  if bufnr then
    local was_modified = vim.bo[bufnr].modified
    for lineno, line_refs in pairs(by_line) do
      local line = vim.api.nvim_buf_get_lines(bufnr, lineno - 1, lineno, false)[1]
      if line then
        local new_line, n = rewrite_line(line, line_refs)
        if n > 0 then
          before[lineno] = line
          vim.api.nvim_buf_set_lines(bufnr, lineno - 1, lineno, false, { new_line })
          file_applied = file_applied + n
        end
      end
    end
    if file_applied > 0 and not was_modified then
      -- Persist without firing BufWritePre autocmds (formatters, trailing-
      -- whitespace strippers, …) so this stays a minimal, surgical edit.
      pcall(vim.api.nvim_buf_call, bufnr, function()
        vim.cmd("silent noautocmd keepjumps write")
      end)
    end
  else
    local ok, lines = pcall(vim.fn.readfile, file)
    if ok and type(lines) == "table" then
      for lineno, line_refs in pairs(by_line) do
        local line = lines[lineno]
        if line then
          local new_line, n = rewrite_line(line, line_refs)
          if n > 0 then
            before[lineno] = line
            lines[lineno] = new_line
            file_applied = file_applied + n
          end
        end
      end
      if file_applied > 0 then pcall(vim.fn.writefile, lines, file) end
    end
  end

  return file_applied, before
end

---@internal
---Push one apply onto the undo stack, trimming it to `undo_depth()`.
---@param undo_entries FiletreeRefsUndoEntry[]
---@param applied integer
---@param files_changed integer
---@param label string
---@return integer id  Handle for `M.undo_by_id`.
local function push_undo(undo_entries, applied, files_changed, label)
  _next_id = _next_id + 1
  _undo_stack[#_undo_stack + 1] = {
    id = _next_id,
    entries = undo_entries,
    count = applied,
    files = files_changed,
    label = label,
  }
  while #_undo_stack > undo_depth() do
    table.remove(_undo_stack, 1)
  end
  return _next_id
end

---Apply `refs` (each with `new_target` set).
---
---When `on_done` is given and the change spans more than `APPLY_CHUNK_SIZE`
---files, the files are rewritten `APPLY_CHUNK_SIZE` per event-loop tick with a
---`[filetree.refs]` progress indicator, and the totals are delivered through
---`on_done` instead of the return values (a project-wide rename touches every
---referencing file — one synchronous loop freezes the editor for the whole
---run). A smaller change, and every caller that passes no `on_done`, keep the
---fully synchronous path and its return values unchanged.
---
---The undo token pushed by this apply is reported as a third value (and third
---`on_done` argument) so a caller can revert *its own* apply later — trash's
---`U` reverts the `REF!` markers belonging to exactly the delete it restores.
---It is `nil` when nothing was applied or `opts.undo == false`.
---@param refs FiletreeRef[]
---@param opts? { label?: string, undo?: boolean }
---@param on_done? fun(applied: integer, files_changed: integer, undo_id: integer?)
---@return integer applied, integer files_changed, integer? undo_id
function M.run(refs, opts, on_done)
  opts = opts or {}
  local by_file = group(refs)
  ---@type string[]
  local files = {}
  for file in pairs(by_file) do
    files[#files + 1] = file
  end
  table.sort(files) -- deterministic order

  local applied, files_changed = 0, 0
  ---@type integer?
  local undo_id
  ---@type FiletreeRefsUndoEntry[]
  local undo_entries = {}

  local function tally(file, file_applied, before)
    if file_applied > 0 then
      applied = applied + file_applied
      files_changed = files_changed + 1
      undo_entries[#undo_entries + 1] = { file = file, lines = before }
    end
  end

  local function finalize()
    if applied > 0 and opts.undo ~= false then
      undo_id = push_undo(undo_entries, applied, files_changed, opts.label or "reference update")
    end
  end

  if type(on_done) ~= "function" or #files <= APPLY_CHUNK_SIZE then
    for _, file in ipairs(files) do
      tally(file, apply_file(file, by_file[file]))
    end
    finalize()
    if on_done then on_done(applied, files_changed, undo_id) end
    return applied, files_changed, undo_id
  end

  local h = progress.create({ title = "[filetree.refs]" })
  local total = #files
  local i = 0

  local function step()
    if h and h.cancelled then
      -- Already-written files stay written; report what landed so far.
      finalize()
      on_done(applied, files_changed, undo_id)
      return
    end

    local last = math.min(i + APPLY_CHUNK_SIZE, total)
    for j = i + 1, last do
      tally(files[j], apply_file(files[j], by_file[files[j]]))
    end
    i = last

    if h then h:update({ text = "updating references…", current = i, total = total }) end

    if i < total then
      vim.schedule(step)
      return
    end

    if h then h:finish(string.format("%d reference(s) in %d file(s)", applied, files_changed)) end
    finalize()
    on_done(applied, files_changed, undo_id)
  end

  step()
  return applied, files_changed, undo_id -- best-effort snapshot; async callers use on_done
end

---Whether there is anything to undo.
---@return boolean
function M.can_undo()
  return #_undo_stack > 0
end

---Label of the most recent apply (nil when the stack is empty).
---@return string?
function M.last_label()
  local top = _undo_stack[#_undo_stack]
  return top and top.label or nil
end

---@internal
---Restore one undo entry's lines, but only where the current content is still
---exactly what this module wrote — an edit made since then wins.
---@param entry FiletreeRefsUndoEntry
---@return integer file_restored
local function undo_file(entry)
  local bufnr = scan.buffer_for(entry.file)
  local file_restored = 0

  if bufnr then
    local was_modified = vim.bo[bufnr].modified
    for lineno, old_line in pairs(entry.lines) do
      vim.api.nvim_buf_set_lines(bufnr, lineno - 1, lineno, false, { old_line })
      file_restored = file_restored + 1
    end
    if file_restored > 0 and not was_modified then
      pcall(vim.api.nvim_buf_call, bufnr, function()
        vim.cmd("silent noautocmd keepjumps write")
      end)
    end
  else
    local ok, lines = pcall(vim.fn.readfile, entry.file)
    if ok and type(lines) == "table" then
      for lineno, old_line in pairs(entry.lines) do
        if lines[lineno] then
          lines[lineno] = old_line
          file_restored = file_restored + 1
        end
      end
      if file_restored > 0 then pcall(vim.fn.writefile, lines, entry.file) end
    end
  end

  return file_restored
end

---@internal
---Restore every entry of one already-popped token.
---
---Chunked with a progress indicator when `on_done` is given and the token
---spans more than `APPLY_CHUNK_SIZE` files, mirroring `M.run`.
---@param token FiletreeRefsUndoToken
---@param on_done? fun(restored: integer, files_changed: integer, label: string?)
---@return integer restored, integer files_changed, string? label
local function restore_token(token, on_done)
  local restored, files_changed = 0, 0

  local function tally(file_restored)
    if file_restored > 0 then
      restored = restored + file_restored
      files_changed = files_changed + 1
    end
  end

  if type(on_done) ~= "function" or #token.entries <= APPLY_CHUNK_SIZE then
    for _, entry in ipairs(token.entries) do
      tally(undo_file(entry))
    end
    if on_done then on_done(restored, files_changed, token.label) end
    return restored, files_changed, token.label
  end

  local h = progress.create({ title = "[filetree.refs]" })
  local total = #token.entries
  local i = 0

  local function step()
    if h and h.cancelled then
      on_done(restored, files_changed, token.label)
      return
    end

    local last = math.min(i + APPLY_CHUNK_SIZE, total)
    for j = i + 1, last do
      tally(undo_file(token.entries[j]))
    end
    i = last

    if h then h:update({ text = "restoring references…", current = i, total = total }) end

    if i < total then
      vim.schedule(step)
      return
    end

    if h then h:finish(string.format("%d reference(s) in %d file(s)", restored, files_changed)) end
    on_done(restored, files_changed, token.label)
  end

  step()
  return restored, files_changed, token.label
end

---Undo the most recent apply. Lines are restored only where the current
---content is still what this module wrote — an edit made since then wins.
---@param on_done? fun(restored: integer, files_changed: integer, label: string?)
---@return integer restored, integer files_changed, string? label
function M.undo(on_done)
  local token = table.remove(_undo_stack)
  if not token then
    if on_done then on_done(0, 0, nil) end
    return 0, 0, nil
  end
  return restore_token(token, on_done)
end

---Whether `id` (from `M.run`) is still on the stack — it is gone once undone,
---or once `undo_depth` trimmed it off the bottom.
---@param id integer?
---@return boolean
function M.has_token(id)
  if not id then return false end
  for _, token in ipairs(_undo_stack) do
    if token.id == id then return true end
  end
  return false
end

---Undo one specific apply, identified by the id `M.run` reported — regardless
---of where it now sits on the stack.
---
---This is what lets an undo that is *not* "the last reference update" stay
---correct: restoring a trashed file has to revert the `REF!` markers of that
---delete, even when unrelated renames pushed applies on top since. An id that
---is no longer on the stack (already undone, or trimmed by `undo_depth`)
---reports 0 rather than reverting something else.
---@param id integer
---@param on_done? fun(restored: integer, files_changed: integer, label: string?)
---@return integer restored, integer files_changed, string? label
function M.undo_by_id(id, on_done)
  for i, token in ipairs(_undo_stack) do
    if token.id == id then
      table.remove(_undo_stack, i)
      return restore_token(token, on_done)
    end
  end
  if on_done then on_done(0, 0, nil) end
  return 0, 0, nil
end

---Drop the undo history (used by teardown/tests).
function M.reset()
  _undo_stack = {}
end

---Preview of what `refs` would change: one `{ file, line, before, after }`
---row per affected line, ordered by file then line. Feeds the "Show diff"
---option of the chooser without touching anything.
---@param refs FiletreeRef[]
---@return { file: string, line: integer, before: string, after: string }[]
function M.preview(refs)
  local rows = {}
  for file, by_line in pairs(group(refs)) do
    local lines = scan.lines_of(file)
    if lines then
      for lineno, line_refs in pairs(by_line) do
        local line = lines[lineno]
        if line then
          local new_line, n = rewrite_line(line, line_refs)
          if n > 0 then
            rows[#rows + 1] = { file = file, line = lineno, before = line, after = new_line }
          end
        end
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    return a.line < b.line
  end)
  return rows
end

return M
