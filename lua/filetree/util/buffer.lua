---@module 'filetree.util.buffer'
---@brief Buffer validation and window-context utilities.

local path = require("filetree.util.path")

local M = {}

---Filetypes treated as tree/explorer windows — never valid editor targets.
---@type table<string, true>
M.TREE_FT = {
  ["neo-tree"] = true, ["NvimTree"] = true,
  ["netrw"]    = true, ["oil"]      = true, ["minifiles"] = true,
}

-- Buffer-validity cache. Deliberately a TTL + explicit-invalidation cache, NOT
-- `lib.nvim.memo` (which is pure LRU memoization): buffer validity changes over
-- time (a buffer can become unlisted, unreadable, or wiped without our seeing a
-- BufDelete), so results must expire (TTL) and be invalidatable — semantics memo
-- does not provide. Weak keys let entries GC with the buffer numbers.
---@type table<integer, {valid:boolean, timestamp:number}>
local _cache = {}
setmetatable(_cache, { __mode = "k" })

local CACHE_TTL = 1000 -- ms

---Return true when bufnr is a valid, normal, listed file buffer with a readable path.
---@param bufnr integer|nil  0 or nil = current buffer.
---@return boolean
function M.is_valid_file_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local cached = _cache[bufnr]
  local now    = (vim.uv or vim.loop).now()
  if cached and (now - cached.timestamp < CACHE_TTL) then
    return cached.valid
  end

  local valid = true
  if not vim.api.nvim_buf_is_valid(bufnr)  then valid = false
  elseif not vim.api.nvim_buf_is_loaded(bufnr) then valid = false
  elseif vim.bo[bufnr].buftype ~= ""           then valid = false
  elseif not vim.bo[bufnr].buflisted           then valid = false
  else
    local name = vim.api.nvim_buf_get_name(bufnr)
    if not name or name == ""                 then valid = false
    elseif vim.fn.filereadable(name) ~= 1     then valid = false
    end
  end

  _cache[bufnr] = { valid = valid, timestamp = now }
  return valid
end

---Invalidate cache entry for a buffer (e.g. on BufDelete).
---@param bufnr integer
function M.invalidate(bufnr)
  _cache[bufnr] = nil
end

---Return {buf, file, dir} for bufnr, or nil if the buffer is not a valid file.
---@param bufnr integer|nil
---@return {buf:integer, file:string, dir:string}|nil
function M.context(bufnr)
  if not M.is_valid_file_buffer(bufnr) then return nil end
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  return { buf = bufnr, file = file, dir = vim.fn.fnamemodify(file, ":p:h") }
end

---Find the last window in the current tabpage that holds a valid file buffer.
---`exclude_win` is skipped (pass the tree's winid to exclude it).
---@param exclude_win integer|nil
---@return integer|nil bufnr, integer|nil winid
function M.find_last_normal_buffer(exclude_win)
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for i = #wins, 1, -1 do
    local win = wins[i]
    if win ~= exclude_win and vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if M.is_valid_file_buffer(buf) then
        return buf, win
      end
    end
  end
  return nil, nil
end

---Find the most-recently-focused normal editor window: non-tree filetype,
---editable (`buftype == ""`), non-floating. Prefers the alternate window
---(`winnr("#")`), then falls back to the first matching window.
---Replaces the per-feature `find_adjacent_win()` / `find_editor_win()` helpers.
---@param exclude_win integer|nil  Window to skip (e.g. the tree window).
---@return integer|nil winid
function M.find_editor_win(exclude_win)
  local function is_editor(win)
    if not win or win == 0 or win == exclude_win then return false end
    if not vim.api.nvim_win_is_valid(win) then return false end
    if vim.api.nvim_win_get_config(win).relative ~= "" then return false end -- float
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= "" then return false end
    return not M.TREE_FT[vim.bo[buf].filetype]
  end

  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  if is_editor(prev) then return prev end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_editor(win) then return win end
  end
  return nil
end

-- Auto-invalidate cache when buffers are deleted
vim.api.nvim_create_autocmd("BufDelete", {
  group = vim.api.nvim_create_augroup("FiletreeBufferCache", { clear = true }),
  callback = function(args) M.invalidate(args.buf) end,
})

---Repoint every open buffer whose name is `old_path` (or nested under it, for
---a directory move/rename) to the corresponding path under `new_path`. Used
---after any on-disk move/rename (copy_move's cut+paste, rename_batch,
---smart_rename) so a stale buffer doesn't linger pointing at a path that no
---longer exists while a second, disconnected buffer gets created for the file
---at its new location.
---
---For an exact match: renames the buffer via `nvim_buf_set_name`. When the
---buffer has no unsaved changes, also does a silent `:edit!` to clear the
---"file changed on disk" state, matching what a normal external rename would
---leave behind. When the buffer IS modified, the rename alone is enough --
---content and undo history are untouched, and the next `:w` simply writes to
---the new path. Forcing a reload here would silently discard the user's
---unsaved edits.
---
---For a directory move/rename: any buffer nested under `old_path` (name
---starts with `old_path .. "/"`) gets that prefix replaced with `new_path`,
---preserving the relative sub-path -- covers every buffer open anywhere under
---a moved directory tree, not just a single file.
---
---Both `old_path`/`new_path` and every buffer name are normalized
---(forward-slash) before comparing: a path sourced from a tree adapter's
---node.path can use a different separator convention than
---`nvim_buf_get_name()` returns on Windows, which would otherwise make every
---comparison silently miss (the same class of bug fixed across all 5 tree
---adapters this session).
---
---Renaming onto a path that collides with an already-open, DIFFERENT buffer
---(Neovim raises E95 "buffer already exists") is caught and skipped with a
---warning rather than aborting the whole sweep.
---@param old_path string
---@param new_path string
---@return integer  count of buffers relocated
function M.relocate(old_path, new_path)
  local old_key = path.slashify(old_path)
  local new_key = path.slashify(new_path)
  local prefix  = old_key .. "/"

  local count = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        local key = path.slashify(name)
        local target
        if key == old_key then
          target = new_key
        elseif key:sub(1, #prefix) == prefix then
          target = new_key .. "/" .. key:sub(#prefix + 1)
        end

        if target then
          local was_modified = vim.bo[bufnr].modified
          local ok = pcall(vim.api.nvim_buf_set_name, bufnr, target)
          if ok then
            count = count + 1
            if not was_modified then
              pcall(vim.api.nvim_buf_call, bufnr, function()
                vim.cmd("edit!")
              end)
            end
          else
            local notify = require("filetree.util.notify").create("[filetree.buffer]")
            notify.warn("could not relocate buffer to " .. target
              .. " (a different open buffer already uses that name)")
          end
        end
      end
    end
  end
  return count
end

return M
