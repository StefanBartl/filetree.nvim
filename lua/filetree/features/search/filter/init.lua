---@module 'filetree.features.search.filter'
--- Live filter/search within the tree using a floating input.
---
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

local map = require("filetree.util.map")
local tree_attach = require("filetree.util.tree_attach")
local kit = require("lib.nvim.ui.kit")
local M = {}

---@type FiletreeFilterConfig
local _cfg = {
  enabled = false,
  keymap = "/",
  keymap_clear = "<C-c>",
  case_sensitive = false,
  dim_hl_group = "Comment",
  debounce_ms = 80,
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace for dimming
local _ns = -1

---@type string  current filter query
local _query = ""

-- ── Adapter-native filter ─────────────────────────────────────────────────────

---@internal
---Try the adapter's native filter API (neo-tree/nvim-tree). Returns false when
---no native filter is available, so the caller can fall back to dimming.
---@param query string?
---@return boolean handled
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

---@internal
---Dim non-matching lines in the tree buffer via extmarks (fallback strategy).
---@param query string?
local function dim_non_matching(query)
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not query or query == "" then return end

  local pattern = _cfg.case_sensitive and query or query:lower()

  if not _adapter.get_node_at_line then return end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for linenr = 0, line_count - 1 do
    local node = _adapter.get_node_at_line(bufnr, linenr)
    local name = node and node.name or ""
    local test = _cfg.case_sensitive and name or name:lower()
    if not test:find(pattern, 1, true) then
      -- Dim entire line
      pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, 0, {
        end_col = #(vim.api.nvim_buf_get_lines(bufnr, linenr, linenr + 1, false)[1] or ""),
        hl_group = _cfg.dim_hl_group,
        hl_eol = true,
        priority = 10,
      })
    end
  end
end

---@internal
---Apply `query`: try the native filter first, fall back to dimming.
---@param query string?
local function apply(query)
  _query = query or ""
  if not try_native_filter(query) then dim_non_matching(query) end
end

-- ── Floating input ────────────────────────────────────────────────────────────

---@type Lib.UI.Kit.Surface|nil
local _surf = nil

---Open the floating filter-query input, focusing it if already open.
function M.enter()
  if _surf and _surf:is_valid() then
    _surf:focus()
    return
  end

  -- Position at bottom of the tree window
  local tree_win = _adapter and _adapter.get_winid and _adapter.get_winid() or -1
  local row, col, width
  if tree_win > 0 and vim.api.nvim_win_is_valid(tree_win) then
    local pos = vim.api.nvim_win_get_position(tree_win)
    row = pos[1] + vim.api.nvim_win_get_height(tree_win) - 1
    col = pos[2]
    width = vim.api.nvim_win_get_width(tree_win)
  else
    row, col, width = vim.o.lines - 3, 0, 30
  end

  local function return_to_tree()
    if tree_win > 0 and vim.api.nvim_win_is_valid(tree_win) then
      vim.api.nvim_set_current_win(tree_win)
    end
  end

  _surf = kit.live_input({
    title = "Filter",
    relative = "editor",
    row = row,
    col = col,
    width = math.max(width, 20),
    default = _query,
    debounce = _cfg.debounce_ms,
    on_change = apply,
    on_submit = function(query)
      apply(query)
      return_to_tree()
    end,
    on_cancel = function()
      M.clear()
      return_to_tree()
    end,
  })
  if _surf then _surf:on_close(function()
    _surf = nil
  end) end
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

---@param config FiletreeFilterConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter
  _ns = vim.api.nvim_create_namespace("filetree_filter")

  if _cfg.keymap or _cfg.keymap_clear then
    tree_attach.on_attach(function(buf)
      if _cfg.keymap then
        map("n", _cfg.keymap, M.enter, {
          buffer = buf,
          silent = true,
          desc = "Filetree: enter filter mode",
        })
      end
      if _cfg.keymap_clear then
        map("n", _cfg.keymap_clear, M.clear, {
          buffer = buf,
          silent = true,
          desc = "Filetree: clear filter",
        })
      end
    end)
  end
end

---Clear the filter and close the floating input, if open.
function M.teardown()
  M.clear()
  if _surf then _surf:close() end
  _adapter = nil
end

return M
