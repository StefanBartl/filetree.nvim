---@module 'filetree.features.filter'
---@brief Live filter/search within the tree using a floating input.
---@description
--- Two strategies, tried in order:
---   1. Adapter native filter API (neo-tree: manager.filter_all, nvim-tree: api.tree.search_node)
---   2. Extmark-based dimming fallback: non-matching lines are greyed out.
---
--- Keymaps:
---   "/" inside tree buffer    → enter filter mode
---   <Esc> / empty query       → clear filter
---
--- User commands:
---   :FiletreeFilter [query]
---   :FiletreeFilterClear

local notify = require("filetree.util.notify").create("[filetree.filter]")

local M = {}

---@type FiletreeFilterConfig
local _cfg = {
  enabled          = false,
  keymap           = "/",
  case_sensitive   = false,
  dim_hl_group     = "Comment",
  debounce_ms      = 80,
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace for dimming
local _ns = -1

---@type string  current filter query
local _query = ""

-- ── Adapter-native filter ─────────────────────────────────────────────────────

local function try_native_filter(query)
  if not _adapter then return false end

  local name = _adapter.name
  if name == "neotree" then
    local ok, mgr = pcall(require, "neo-tree.sources.manager")
    if ok and mgr then
      -- neo-tree uses filter_all on the filesystem source
      pcall(function()
        if query and query ~= "" then
          mgr.filter_all("filesystem", query)
        else
          mgr.filter_all("filesystem", nil)
        end
      end)
      return true
    end
  end

  if name == "nvimtree" then
    local ok, api = pcall(require, "nvim-tree.api")
    if ok and api and api.tree then
      if query and query ~= "" then
        pcall(api.tree.search_node, query)
      else
        pcall(api.tree.reload)
      end
      return true
    end
  end

  return false
end

-- ── Extmark-based dimming fallback ────────────────────────────────────────────

local function dim_non_matching(query)
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not query or query == "" then return end

  local pattern = _cfg.case_sensitive
    and query
    or query:lower()

  if not _adapter.get_node_at_line then return end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for linenr = 0, line_count - 1 do
    local node = _adapter.get_node_at_line(bufnr, linenr)
    local name = node and node.name or ""
    local test = _cfg.case_sensitive and name or name:lower()
    if not test:find(pattern, 1, true) then
      -- Dim entire line
      pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, 0, {
        end_col    = #(vim.api.nvim_buf_get_lines(bufnr, linenr, linenr + 1, false)[1] or ""),
        hl_group   = _cfg.dim_hl_group,
        hl_eol     = true,
        priority   = 10,
      })
    end
  end
end

-- ── Debounce ──────────────────────────────────────────────────────────────────

---@type any?
local _timer = nil

local function apply(query)
  _query = query or ""
  if not try_native_filter(query) then
    dim_non_matching(query)
  end
end

local function debounce_apply(query)
  local uv = vim.uv or vim.loop
  if _timer then pcall(function() _timer:stop() end)
  else _timer = uv.new_timer() end
  _timer:start(_cfg.debounce_ms, 0, vim.schedule_wrap(function()
    apply(query)
  end))
end

-- ── Floating input ────────────────────────────────────────────────────────────

---@type integer?
local _input_win = nil
---@type integer?
local _input_buf = nil

local function close_input()
  if _input_win and vim.api.nvim_win_is_valid(_input_win) then
    pcall(vim.api.nvim_win_close, _input_win, true)
  end
  if _input_buf and vim.api.nvim_buf_is_valid(_input_buf) then
    pcall(vim.api.nvim_buf_delete, _input_buf, { force = true })
  end
  _input_win = nil
  _input_buf = nil
end

function M.enter()
  if _input_win and vim.api.nvim_win_is_valid(_input_win) then
    -- Focus existing input
    vim.api.nvim_set_current_win(_input_win)
    return
  end

  -- Position at bottom of the tree window
  local tree_win = _adapter and _adapter.get_winid and _adapter.get_winid() or -1
  local row, col, width
  if tree_win > 0 and vim.api.nvim_win_is_valid(tree_win) then
    local pos = vim.api.nvim_win_get_position(tree_win)
    row   = pos[1] + vim.api.nvim_win_get_height(tree_win) - 1
    col   = pos[2]
    width = vim.api.nvim_win_get_width(tree_win)
  else
    row, col, width = vim.o.lines - 3, 0, 30
  end

  _input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(_input_buf, 0, -1, false, { _query })
  vim.api.nvim_set_option_value("buftype",  "nofile", { buf = _input_buf })
  vim.api.nvim_set_option_value("bufhidden","wipe",   { buf = _input_buf })

  _input_win = vim.api.nvim_open_win(_input_buf, true, {
    relative  = "editor",
    row       = row,
    col       = col,
    width     = math.max(width, 20),
    height    = 1,
    style     = "minimal",
    border    = "single",
    title     = " Filter ",
    title_pos = "left",
  })

  vim.cmd("startinsert!")

  -- Live update on TextChangedI
  local aug = vim.api.nvim_create_augroup("filetree_filter_input_" .. _input_buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group  = aug,
    buffer = _input_buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(_input_buf, 0, 1, false)
      debounce_apply(lines[1] or "")
    end,
  })

  -- Confirm / cancel keymaps
  local opts = { buffer = _input_buf, nowait = true }
  vim.keymap.set({ "i", "n" }, "<CR>", function()
    local lines = vim.api.nvim_buf_get_lines(_input_buf, 0, 1, false)
    apply(lines[1] or "")
    close_input()
    -- Return focus to tree
    if tree_win > 0 and vim.api.nvim_win_is_valid(tree_win) then
      vim.api.nvim_set_current_win(tree_win)
    end
  end, opts)

  vim.keymap.set({ "i", "n" }, "<Esc>", function()
    M.clear()
    close_input()
    if tree_win > 0 and vim.api.nvim_win_is_valid(tree_win) then
      vim.api.nvim_set_current_win(tree_win)
    end
  end, opts)

  vim.api.nvim_create_autocmd("BufLeave", {
    group  = aug,
    buffer = _input_buf,
    once   = true,
    callback = function()
      close_input()
      pcall(vim.api.nvim_del_augroup_by_id, aug)
    end,
  })
end

---Clear the current filter.
function M.clear()
  _query = ""
  apply("")
end

---Apply a filter query directly (without the floating input).
---@param query string
function M.apply(query)
  apply(query)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeFilterConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter
  _ns      = vim.api.nvim_create_namespace("filetree_filter")

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_filter", { clear = true })

  if _cfg.keymap then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        vim.keymap.set("n", _cfg.keymap, M.enter, {
          buffer = ev.buf,
          silent = true,
          desc   = "Filetree: enter filter mode",
        })
      end,
    })
  end

end

function M.teardown()
  M.clear()
  close_input()
  _adapter = nil
  if _timer then pcall(function() _timer:stop(); _timer:close() end); _timer = nil end
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
