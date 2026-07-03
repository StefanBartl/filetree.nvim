---@module 'filetree.features.jump_list'
---@brief Back/forward navigation through tree cursor positions.
---@description
--- Tracks cursor movements in the tree buffer and maintains a ring-buffer
--- of (path, line) positions. <C-o>/<C-i> inside the tree navigate the
--- jump list (mirroring Neovim's own jumplist but scoped to the tree).
---
--- A new jump is recorded when:
---   - The tree's cursor dwells on a new line for > debounce_ms ms
---   - The user opens a file from the tree (node_open hook)
---
--- Config:
---   enabled      boolean
---   max_jumps    integer   Ring buffer size (default 50).
---   debounce_ms  integer   Minimum dwell time before recording (default 500).
---   keymap_back  string?   Navigate backwards (default "<C-o>").
---   keymap_fwd   string?   Navigate forwards  (default "<C-i>").
---
--- Commands (via :Filetree dispatcher):
---   :Filetree jump back
---   :Filetree jump forward
---   :Filetree jump list
---   :Filetree jump clear

local notify = require("filetree.util.notify").create("[filetree.jump_list]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeJumpListConfig
local _cfg = {
  enabled     = false,
  max_jumps   = 50,
  debounce_ms = 500,
  keymap_back = "<C-o>",
  keymap_fwd  = "<C-i>",
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Jump list state ───────────────────────────────────────────────────────────

---@class FiletreeJump
---@field path  string   Absolute path of the node
---@field line  integer  1-based tree buffer line number

---@type FiletreeJump[]
local _list   = {}
local _cursor = 0   -- current position index in _list (1-based, 0 = empty)
local _timer  = nil

local function uv() return vim.uv or vim.loop end

-- ── Record ────────────────────────────────────────────────────────────────────

local function push(path, line)
  if not path or path == "" then return end
  -- Avoid duplicate consecutive jumps
  local last = _list[_cursor]
  if last and last.path == path and last.line == line then return end

  -- Truncate forward history
  while #_list > _cursor do table.remove(_list) end

  _list[#_list + 1] = { path = path, line = line }

  -- Trim to max
  if #_list > _cfg.max_jumps then table.remove(_list, 1) end
  _cursor = #_list
end

local function record_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  local line  = 1
  if bufnr >= 0 then
    local winid = _adapter.get_winid and _adapter.get_winid() or -1
    if winid > 0 and vim.api.nvim_win_is_valid(winid) then
      line = vim.api.nvim_win_get_cursor(winid)[1]
    end
  end
  push(node.path, line)
end

local function schedule_record()
  if _timer then pcall(function() _timer:stop() end) end
  _timer = uv().new_timer()
  _timer:start(_cfg.debounce_ms, 0, vim.schedule_wrap(function()
    _timer = nil
    record_current()
  end))
end

-- ── Navigate ──────────────────────────────────────────────────────────────────

local function go_to(jump)
  if not _adapter then return end
  if _adapter.reveal then pcall(_adapter.reveal, jump.path) end
  -- Also try to restore line
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  local winid = _adapter.get_winid and _adapter.get_winid() or -1
  if bufnr >= 0 and winid > 0 and vim.api.nvim_win_is_valid(winid) then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local target = math.min(jump.line, line_count)
    pcall(vim.api.nvim_win_set_cursor, winid, { target, 0 })
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.back()
  if _cursor <= 1 then notify.info("At start of jump list"); return end
  _cursor = _cursor - 1
  go_to(_list[_cursor])
end

function M.forward()
  if _cursor >= #_list then notify.info("At end of jump list"); return end
  _cursor = _cursor + 1
  go_to(_list[_cursor])
end

function M.clear()
  _list   = {}
  _cursor = 0
  notify.info("Jump list cleared")
end

function M.show()
  if #_list == 0 then notify.info("Jump list is empty"); return end
  local lines = {}
  for i, j in ipairs(_list) do
    local marker = (i == _cursor) and "▶ " or "  "
    lines[#lines + 1] = marker .. vim.fn.fnamemodify(j.path, ":~") .. ":" .. j.line
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width  = math.min(72, vim.o.columns - 4)
  local height = math.min(#lines, 15)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    width    = width,    height = height,
    row      = math.floor((vim.o.lines - height) / 2),
    col      = math.floor((vim.o.columns - width) / 2),
    title    = " Jump List ", title_pos = "center",
  })
  vim.wo[win].cursorline = true
  -- position cursor on current jump
  if _cursor > 0 then
    pcall(vim.api.nvim_win_set_cursor, win, { _cursor, 0 })
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  map("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_close(win, true)
    _cursor = row
    go_to(_list[_cursor])
  end, opts)
  map("n", "q",     function() vim.api.nvim_win_close(win, true) end, opts)
  map("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, opts)
end

---@return integer  current cursor position (1-based)
function M.pos()  return _cursor  end
---@return integer  total jump count
function M.size() return #_list   end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeJumpListConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_jump_list", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if _cfg.keymap_back then
          map("n", _cfg.keymap_back, M.back, {
            buffer = buf, silent = true, desc = "Filetree: jump back",
          })
        end
        if _cfg.keymap_fwd then
          map("n", _cfg.keymap_fwd, M.forward, {
            buffer = buf, silent = true, desc = "Filetree: jump forward",
          })
        end
      end)
    end,
  })

  -- Record jump on CursorMoved in tree window (debounced)
  au.acmd("CursorMoved", {
    group   = _augroup,
    callback = function()
      if not _adapter then return end
      local winid = _adapter.get_winid and _adapter.get_winid() or -1
      if winid > 0 and vim.api.nvim_get_current_win() == winid then
        schedule_record()
      end
    end,
  })

  -- Hook into hooks_api if available
  vim.schedule(function()
    local ok, hooks = require("filetree.features").load("hooks_api")
    if ok and hooks and type(hooks.on) == "function" then
      hooks.on("node_open", function(data)
        if data and data.path then push(data.path, 1) end
      end)
    end
  end)
end

function M.teardown()
  _adapter = nil
  _list    = {}
  _cursor  = 0
  if _timer then pcall(function() _timer:stop(); _timer:close() end); _timer = nil end
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
