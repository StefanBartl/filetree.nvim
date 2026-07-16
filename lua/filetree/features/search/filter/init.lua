---@module 'filetree.features.filter'
---@brief Live filter/search within the tree using a floating input.
---@description
--- Two strategies, tried in order:
---   1. Adapter native filter API (neo-tree: manager.filter_all, nvim-tree: api.tree.search_node)
---   2. Extmark-based dimming fallback: non-matching lines are greyed out.
---
--- Keymaps:
---   "/" inside tree buffer    → enter filter mode
---   <Esc> / empty query       → clear filter (inside the input prompt)
---   <C-c> inside tree buffer  → clear an already-applied filter directly
---
--- User commands:
---   :FiletreeFilter [query]
---   :FiletreeFilterClear

local notify = require("filetree.util.notify").create("[filetree.filter]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local lib_debounce = require("lib.nvim.debounce")
local M = {}

---@type FiletreeFilterConfig
local _cfg = {
  enabled          = false,
  keymap           = "/",
  keymap_clear     = "<C-c>",
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

---Debounce handle built in M.setup() (needs `_cfg.debounce_ms`); `{ call, cancel }`.
---@type table?
local _debounce = nil

local function apply(query)
  _query = query or ""
  if not try_native_filter(query) then
    dim_non_matching(query)
  end
end

local function debounce_apply(query)
  _debounce.call(query)
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
  local aug = au.group("filetree_filter_input_" .. _input_buf, true)
  au.acmd({ "TextChangedI", "TextChanged" }, {
    group  = aug,
    buffer = _input_buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(_input_buf, 0, 1, false)
      debounce_apply(lines[1] or "")
    end,
  })

  -- Confirm / cancel keymaps
  local opts = { buffer = _input_buf, nowait = true }
  map({ "i", "n" }, "<CR>", function()
    local lines = vim.api.nvim_buf_get_lines(_input_buf, 0, 1, false)
    apply(lines[1] or "")
    close_input()
    -- Return focus to tree
    if tree_win > 0 and vim.api.nvim_win_is_valid(tree_win) then
      vim.api.nvim_set_current_win(tree_win)
    end
  end, opts)

  map({ "i", "n" }, "<Esc>", function()
    M.clear()
    close_input()
    if tree_win > 0 and vim.api.nvim_win_is_valid(tree_win) then
      vim.api.nvim_set_current_win(tree_win)
    end
  end, opts)

  au.acmd("BufLeave", {
    group  = aug,
    buffer = _input_buf,
    once   = true,
    callback = function()
      close_input()
      au.del_group(aug)
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

  if _debounce then _debounce.cancel() end
  _debounce = lib_debounce.new(apply, _cfg.debounce_ms)

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_filter", true)

  if _cfg.keymap or _cfg.keymap_clear then
    au.acmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          if _cfg.keymap then
            map("n", _cfg.keymap, M.enter, {
              buffer = buf,
              silent = true,
              desc   = "Filetree: enter filter mode",
            })
          end
          if _cfg.keymap_clear then
            map("n", _cfg.keymap_clear, M.clear, {
              buffer = buf,
              silent = true,
              desc   = "Filetree: clear filter",
            })
          end
        end)
      end,
    })
  end

end

function M.teardown()
  M.clear()
  close_input()
  _adapter = nil
  if _debounce then _debounce.cancel(); _debounce = nil end
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
