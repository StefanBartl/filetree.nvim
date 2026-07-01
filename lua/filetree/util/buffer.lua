---@module 'filetree.util.buffer'
---@brief Buffer validation and window-context utilities.

local M = {}

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

-- Auto-invalidate cache when buffers are deleted
vim.api.nvim_create_autocmd("BufDelete", {
  group = vim.api.nvim_create_augroup("FiletreeBufferCache", { clear = true }),
  callback = function(args) M.invalidate(args.buf) end,
})

return M
