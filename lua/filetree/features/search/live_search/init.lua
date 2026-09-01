---@module 'filetree.features.search.live_search'
--- Real-time incremental search/filter inside the tree buffer.
---
--- Opens a minimal floating input bar at the bottom of the tree window.
--- As the user types, visible nodes that do not match the query are dimmed
--- in real-time. Pressing <CR> commits the pattern to the filter feature
--- (if available); <Esc> cancels and clears the overlay.
---
--- Matching is done against the filename portion of each node path by default.
--- With config.match = "path", the full path is matched.
---
--- Config:
---   enabled      boolean
---   keymap       string?   Key to open live search (default "/").
---   match        "name"|"path"  What to match against (default "name").
---   hl_match     string    Highlight for matched lines (default "Search").
---   hl_dim       string    Highlight for dimmed (non-matched) lines (default "Comment").
---   commit_to_filter boolean  <CR> pushes pattern to filter feature (default true).
---   debounce_ms  integer   Input debounce before re-rendering (default 80ms).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree search          (open live search)
---   :Filetree search clear    (clear current overlay)

local notify = require("filetree.util.notify").create("[filetree.live_search]")

local kit = require("lib.nvim.ui.kit")
local bind = require("filetree.util.bind")
local M = {}

---@type FiletreeLiveSearchConfig
local _cfg = {
  enabled = false,
  keymap = "gs",
  match = "name",
  hl_match = "Search",
  hl_dim = "Comment",
  commit_to_filter = true,
  debounce_ms = 80,
}

---@type FiletreeAdapter?
local _adapter = nil

local _ns = vim.api.nvim_create_namespace("filetree_live_search")

-- ── Overlay helpers ───────────────────────────────────────────────────────────

---@internal
---@param bufnr integer?
local function clear_overlay(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, _ns, 0, -1)
  end
end

---@internal
---Highlight matching lines and dim non-matching ones in the tree buffer.
---@param tree_bufnr integer
---@param query string?
local function apply_overlay(tree_bufnr, query)
  clear_overlay(tree_bufnr)
  if not query or query == "" then return end

  local nodes = _adapter and _adapter.get_visible_nodes and _adapter.get_visible_nodes() or {}
  local pat = query:lower()

  for _, node in ipairs(nodes) do
    if not node.path or not node.line_number then goto continue end
    local subject = _cfg.match == "path" and node.path:lower()
      or vim.fn.fnamemodify(node.path, ":t"):lower()

    local matched = subject:find(pat, 1, true)
    if matched then
      -- Highlight match
      pcall(vim.api.nvim_buf_set_extmark, tree_bufnr, _ns, node.line_number - 1, 0, {
        line_hl_group = _cfg.hl_match,
        priority = 200,
      })
    else
      -- Dim non-match
      pcall(vim.api.nvim_buf_set_extmark, tree_bufnr, _ns, node.line_number - 1, 0, {
        line_hl_group = _cfg.hl_dim,
        priority = 200,
      })
    end
    ::continue::
  end
end

-- ── Floating input bar ────────────────────────────────────────────────────────

---@internal
---@param tree_winid integer
---@param tree_bufnr integer
local function open_input_bar(tree_winid, tree_bufnr)
  local win_width = vim.api.nvim_win_get_width(tree_winid)
  local win_pos = vim.api.nvim_win_get_position(tree_winid)
  local win_h = vim.api.nvim_win_get_height(tree_winid)

  local function return_to_tree()
    if vim.api.nvim_win_is_valid(tree_winid) then vim.api.nvim_set_current_win(tree_winid) end
  end

  kit.live_input({
    title = "/ search",
    relative = "editor",
    width = win_width - 2,
    row = win_pos[1] + win_h - 1,
    col = win_pos[2] + 1,
    filetype = "filetree_search",
    debounce = _cfg.debounce_ms,
    on_change = function(query)
      apply_overlay(tree_bufnr, query)
    end,
    on_cancel = function()
      clear_overlay(tree_bufnr)
      return_to_tree()
    end,
    on_submit = function(query)
      if _cfg.commit_to_filter and query ~= "" then
        local ok, filter = require("filetree.features").load("filter")
        if ok and filter and filter.set then
          filter.set(query)
          notify.info("Filter set: " .. query)
        end
      end
      return_to_tree()
    end,
  })
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Open the live-search input bar over the tree window.
function M.open()
  if not _adapter then return end
  local winid = _adapter.get_winid and _adapter.get_winid() or -1
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1

  if winid < 0 or not vim.api.nvim_win_is_valid(winid) then
    notify.warn("Tree window not found")
    return
  end
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    notify.warn("Tree buffer not found")
    return
  end

  open_input_bar(winid, bufnr)
end

---Clear the live-search overlay, if any.
function M.clear()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  clear_overlay(bufnr)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeLiveSearchConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  bind.bind("live_search", _cfg, {
    { name = "open", field = "keymap", rhs = M.open, desc = "live search" },
  })
end

function M.teardown()
  _adapter = nil
end

return M
