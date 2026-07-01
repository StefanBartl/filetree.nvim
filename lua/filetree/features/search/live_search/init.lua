---@module 'filetree.features.live_search'
---@brief Real-time incremental search/filter inside the tree buffer.
---@description
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

local M = {}

---@type FiletreeLiveSearchConfig
local _cfg = {
  enabled          = false,
  keymap           = "gs",
  match            = "name",
  hl_match         = "Search",
  hl_dim           = "Comment",
  commit_to_filter = true,
  debounce_ms      = 80,
}

---@type FiletreeAdapter?
local _adapter = nil

local _ns    = vim.api.nvim_create_namespace("filetree_live_search")
local _timer = nil

local function uv() return vim.uv or vim.loop end

-- ── Overlay helpers ───────────────────────────────────────────────────────────

local function clear_overlay(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, _ns, 0, -1)
  end
end

local function apply_overlay(tree_bufnr, query)
  clear_overlay(tree_bufnr)
  if not query or query == "" then return end

  local nodes = _adapter and _adapter.get_visible_nodes and _adapter.get_visible_nodes() or {}
  local pat   = query:lower()

  for _, node in ipairs(nodes) do
    if not node.path or not node.line then goto continue end
    local subject = _cfg.match == "path"
      and node.path:lower()
      or vim.fn.fnamemodify(node.path, ":t"):lower()

    local matched = subject:find(pat, 1, true)
    if matched then
      -- Highlight match
      pcall(vim.api.nvim_buf_set_extmark, tree_bufnr, _ns, node.line - 1, 0, {
        line_hl_group = _cfg.hl_match,
        priority      = 200,
      })
    else
      -- Dim non-match
      pcall(vim.api.nvim_buf_set_extmark, tree_bufnr, _ns, node.line - 1, 0, {
        line_hl_group = _cfg.hl_dim,
        priority      = 200,
      })
    end
    ::continue::
  end
end

-- ── Floating input bar ────────────────────────────────────────────────────────

---@param tree_winid integer
---@param tree_bufnr integer
local function open_input_bar(tree_winid, tree_bufnr)
  local win_width = vim.api.nvim_win_get_width(tree_winid)
  local win_pos   = vim.api.nvim_win_get_position(tree_winid)
  local win_h     = vim.api.nvim_win_get_height(tree_winid)

  local bar_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bar_buf, 0, -1, false, { "" })
  vim.bo[bar_buf].buftype  = "prompt"
  vim.bo[bar_buf].filetype = "filetree_search"

  local bar_win = vim.api.nvim_open_win(bar_buf, true, {
    relative = "editor",
    style    = "minimal",
    border   = "rounded",
    width    = win_width - 2,
    height   = 1,
    row      = win_pos[1] + win_h - 1,
    col      = win_pos[2] + 1,
    title    = " / search ",
    title_pos = "left",
  })

  local function close_bar(commit)
    pcall(vim.api.nvim_win_close, bar_win, true)
    if not commit then
      clear_overlay(tree_bufnr)
    end
  end

  -- TextChangedI: debounced overlay
  local group = vim.api.nvim_create_augroup("filetree_live_search_input", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group  = group,
    buffer = bar_buf,
    callback = function()
      local line = vim.api.nvim_buf_get_lines(bar_buf, 0, 1, false)[1] or ""
      -- Strip prompt prefix if buftype=prompt added one
      local query = line:match("^%s*(.-)%s*$")

      if _timer then pcall(function() _timer:stop() end) end
      _timer = uv().new_timer()
      _timer:start(_cfg.debounce_ms, 0, vim.schedule_wrap(function()
        _timer = nil
        apply_overlay(tree_bufnr, query)
      end))
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    group  = group,
    buffer = bar_buf,
    once   = true,
    callback = function()
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  vim.fn.prompt_setprompt(bar_buf, "")

  local km_opts = { buffer = bar_buf, nowait = true, silent = true }

  -- <Esc> or <C-c>: cancel
  local function cancel()
    close_bar(false)
    pcall(vim.api.nvim_del_augroup_by_id, group)
    -- Return focus to tree
    if vim.api.nvim_win_is_valid(tree_winid) then
      vim.api.nvim_set_current_win(tree_winid)
    end
  end

  -- <CR>: commit pattern to filter feature
  local function commit()
    local line  = vim.api.nvim_buf_get_lines(bar_buf, 0, 1, false)[1] or ""
    local query = line:match("^%s*(.-)%s*$")
    close_bar(true)
    pcall(vim.api.nvim_del_augroup_by_id, group)

    if _cfg.commit_to_filter and query ~= "" then
      local ok, filter = require("filetree.features").load("filter")
      if ok and filter and filter.set then
        filter.set(query)
        notify.info("Filter set: " .. query)
      end
    end

    if vim.api.nvim_win_is_valid(tree_winid) then
      vim.api.nvim_set_current_win(tree_winid)
    end
  end

  vim.keymap.set({ "i", "n" }, "<Esc>",   cancel, km_opts)
  vim.keymap.set({ "i", "n" }, "<C-c>",   cancel, km_opts)
  vim.keymap.set({ "i", "n" }, "<CR>",    commit, km_opts)

  -- Start insert so user can type immediately
  vim.cmd("startinsert!")
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.open()
  if not _adapter then return end
  local winid = _adapter.get_winid and _adapter.get_winid() or -1
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1

  if winid < 0 or not vim.api.nvim_win_is_valid(winid) then
    notify.warn("Tree window not found"); return
  end
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    notify.warn("Tree buffer not found"); return
  end

  open_input_bar(winid, bufnr)
end

function M.clear()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  clear_overlay(bufnr)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeLiveSearchConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_live_search", { clear = true })

  if _cfg.keymap then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.keymap.set("n", _cfg.keymap, M.open, {
            buffer = buf, silent = true,
            desc   = "Filetree: live search",
          })
        end)
      end,
    })
  end
end

function M.teardown()
  _adapter = nil
  if _timer then pcall(function() _timer:stop(); _timer:close() end); _timer = nil end
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
