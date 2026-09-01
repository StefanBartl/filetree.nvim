---@module 'filetree.features.marks'
---@brief Node marking system — toggle marks, visual indicators, batch operations.
---@description
--- Marks are stored per-session as a set of absolute paths. Visual indicators
--- are rendered as extmarks in the tree buffer. Marked paths are exposed for
--- use in batch operations (copy, move, delete, etc.).

local notify = require("filetree.util.notify").create("[filetree.marks]")

local bufevents = require("filetree.util.bufevents")
local kit = require("lib.nvim.ui.kit")
local bind = require("filetree.util.bind")
local M = {}

---@type FiletreeMarksConfig
local _cfg = {
  enabled = false,
  indicator = "✓",
  hl_group = "DiagnosticOk",
  keymap = "m",
  keymap_all = "]m",
  keymap_unmark_all = "[m",
  -- Deliberately NOT "<C-m>": outside an extended encoding ("CSI u" /
  -- modifyOtherKeys) Ctrl+M and Enter are the same byte, 0x0D, and Neovim
  -- always resolves that byte to <CR> -- even when nothing maps <CR> at all.
  -- So a "<C-m>" mapping is not "last registration wins" shadowing, it simply
  -- never fires on such a terminal. See TESTS/smoke.lua check 6.
  keymap_clear = "<leader>mc",
  keymap_show = "<leader>ms",
  -- Navigation between marks. `Ngm` jumps to the Nth marked node.
  keymap_goto = "gm",
  keymap_next = "]M",
  keymap_prev = "[M",
}

---@type FiletreeAdapter?
local _adapter = nil

---@type table<string, boolean>  absolute path → marked
local _marks = {}

local _ns = nil
local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_marks") end
  return _ns
end

-- ── Internal ──────────────────────────────────────────────────────────────────

local function redraw()
  if not _adapter then return end
  local is_open, bufnr = _adapter.is_open()
  if not is_open or not bufnr then return end

  vim.api.nvim_buf_clear_namespace(bufnr, ns(), 0, -1)

  local nodes = _adapter.get_visible_nodes()
  for _, node in ipairs(nodes) do
    if _marks[node.path] then
      local line = node.line_number - 1
      if line >= 0 then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns(), line, 0, {
          virt_text = { { _cfg.indicator .. " ", _cfg.hl_group } },
          virt_text_pos = "overlay",
          priority = 100,
        })
      end
    end
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Toggle the mark on `path`.
---@param path string
---@return boolean  New marked state.
function M.toggle(path)
  if _marks[path] then
    _marks[path] = nil
  else
    _marks[path] = true
  end
  redraw()
  return _marks[path] == true
end

---Toggle mark on the node currently under the cursor.
---@return boolean?  New marked state, or nil when no node is found.
function M.toggle_current()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()
  if not node then
    notify.warn("no node under cursor")
    return nil
  end
  return M.toggle(node.path)
end

---Return true when `path` is marked.
---@param path string
---@return boolean
function M.is_marked(path)
  return _marks[path] == true
end

---Return all currently marked paths.
---@return string[]
function M.get_marked()
  local out = {}
  for p in pairs(_marks) do
    out[#out + 1] = p
  end
  table.sort(out)
  return out
end

---Return the count of marked items.
---@return integer
function M.count()
  local n = 0
  for _ in pairs(_marks) do
    n = n + 1
  end
  return n
end

---Clear all marks.
function M.clear_all()
  _marks = {}
  redraw()
end

---Mark all currently visible nodes.
function M.mark_all_visible()
  if not _adapter then return end
  local nodes = _adapter.get_visible_nodes()
  for _, node in ipairs(nodes) do
    _marks[node.path] = true
  end
  redraw()
end

---Unmark all currently visible nodes.
function M.unmark_all_visible()
  if not _adapter then return end
  local nodes = _adapter.get_visible_nodes()
  for _, node in ipairs(nodes) do
    _marks[node.path] = nil
  end
  redraw()
end

---Marked nodes that are actually on screen, in buffer order.
---
--- `get_marked()` returns paths sorted alphabetically, which is the right
--- answer for "what is marked" and the wrong one for navigation: jumping
--- between marks has to follow the tree as it is rendered, and a marked node
--- inside a collapsed directory has no line to jump to at all.
---@return { path: string, line: integer }[]
---@internal
local function visible_marks()
  if not _adapter then return {} end
  local out = {}
  for _, node in ipairs(_adapter.get_visible_nodes()) do
    if _marks[node.path] and node.line_number and node.line_number > 0 then
      out[#out + 1] = { path = node.path, line = node.line_number }
    end
  end
  table.sort(out, function(a, b)
    return a.line < b.line
  end)
  return out
end

---@internal
---@param line integer  1-based
local function goto_line(line)
  if not _adapter then return end
  local is_open, bufnr = _adapter.is_open()
  if not is_open or not bufnr then return end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
      return
    end
  end
end

---Jump to the `n`-th marked node (1-based, in render order).
---
--- Clamped rather than refused: with three marks, `9` going to the last one
--- is more useful than an error, and matches how `G` treats an out-of-range
--- count.
---@param n integer|nil  defaults to 1
---@return boolean moved
function M.goto_mark(n)
  local marks = visible_marks()
  if #marks == 0 then
    notify.info("No marked nodes visible")
    return false
  end
  local idx = math.max(1, math.min(n or 1, #marks))
  goto_line(marks[idx].line)
  return true
end

---Jump to the next marked node below the cursor, wrapping to the first.
---@param dir integer  1 forward, -1 backward
---@return boolean moved
function M.goto_adjacent_mark(dir)
  if not _adapter then return false end
  local marks = visible_marks()
  if #marks == 0 then
    notify.info("No marked nodes visible")
    return false
  end

  local is_open, bufnr = _adapter.is_open()
  if not is_open or not bufnr then return false end
  local cur = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      cur = vim.api.nvim_win_get_cursor(win)[1]
      break
    end
  end

  if dir > 0 then
    for _, m in ipairs(marks) do
      if m.line > cur then
        goto_line(m.line)
        return true
      end
    end
    goto_line(marks[1].line) -- wrap
  else
    for i = #marks, 1, -1 do
      if marks[i].line < cur then
        goto_line(marks[i].line)
        return true
      end
    end
    goto_line(marks[#marks].line) -- wrap
  end
  return true
end

---Mark every node in the current Visual selection.
---
--- The tree had no Visual-mode keymaps at all: marking a run of files meant
--- pressing `m` once per line. The selection's line range maps onto the
--- rendered nodes directly, which is the one thing a tree buffer's Visual
--- mode is genuinely good for.
---@param unmark boolean|nil  # clear instead of set
---@return integer changed
function M.mark_visual(unmark)
  if not _adapter then return 0 end
  local s_line = vim.fn.line("v")
  local e_line = vim.fn.line(".")
  if s_line > e_line then
    s_line, e_line = e_line, s_line
  end

  -- Leave Visual mode first: the marks redraw sets extmarks, and staying in
  -- Visual over a buffer that just changed leaves a stale selection.
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

  local changed = 0
  for _, node in ipairs(_adapter.get_visible_nodes()) do
    local ln = node.line_number
    if ln and ln >= s_line and ln <= e_line then
      local now = unmark and nil or true
      if _marks[node.path] ~= now then
        _marks[node.path] = now
        changed = changed + 1
      end
    end
  end

  redraw()
  return changed
end

---Show a floating summary of all marked paths.
function M.show()
  local marked = M.get_marked()
  if #marked == 0 then
    notify.info("No nodes marked")
    return
  end

  local lines = {
    string.format("Marked nodes (%d)", #marked),
    string.rep("─", 50),
  }
  for i, p in ipairs(marked) do
    lines[#lines + 1] = string.format("[%02d] %s", i, p)
  end

  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 1, vim.o.lines - 6)

  kit.viewer({
    lines = lines,
    title = "Marked Nodes",
    width = width,
    height = height,
  })
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeMarksConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  -- Redraw marks whenever the tree buffer is entered/refreshed
  bufevents.register("marks", { "BufEnter:*", "BufWritePost:*" }, {
    desc = "[filetree] Re-draw node marks in the tree",
    load = function()
      vim.defer_fn(redraw, 50)
    end,
  })

  -- Keymaps inside tree buffer
  bind.bind("marks", _cfg, {
    -- `keymap` is one action with two modes: on a line it toggles that node,
    -- over a selection it marks every node the range spans. Same key, same
    -- intent -- so one name, and one thing for a user to move.
    {
      name = "toggle",
      field = "keymap",
      desc = "toggle mark",
      binds = {
        {
          mode = "n",
          desc = "toggle mark",
          rhs = function()
            M.toggle_current()
          end,
        },
        {
          mode = "x",
          desc = "mark selection",
          rhs = function()
            local n = M.mark_visual(false)
            notify.info(("Marked %d node(s)"):format(n))
          end,
        },
      },
    },
    {
      name = "mark_all",
      field = "keymap_all",
      rhs = M.mark_all_visible,
      desc = "mark all visible",
    },
    {
      name = "unmark_all",
      field = "keymap_unmark_all",
      desc = "unmark all visible",
      binds = {
        { mode = "n", desc = "unmark all visible", rhs = M.unmark_all_visible },
        {
          mode = "x",
          desc = "unmark selection",
          rhs = function()
            local n = M.mark_visual(true)
            notify.info(("Unmarked %d node(s)"):format(n))
          end,
        },
      },
    },
    {
      name = "clear",
      field = "keymap_clear",
      desc = "clear all marks",
      rhs = function()
        M.clear_all()
      end,
    },
    {
      name = "show",
      field = "keymap_show",
      desc = "show marked nodes",
      rhs = function()
        M.show()
      end,
    },

    -- Navigation between marks. `Ngm` jumps to the Nth mark, matching how a
    -- count reads on `G`; `]M`/`[M` cycle, wrapping like every other
    -- next/prev pair in this plugin.
    {
      name = "goto",
      field = "keymap_goto",
      desc = "jump to the Nth marked node",
      rhs = function()
        M.goto_mark(vim.v.count ~= 0 and vim.v.count or 1)
      end,
    },
    {
      name = "next",
      field = "keymap_next",
      desc = "next marked node",
      rhs = function()
        M.goto_adjacent_mark(1)
      end,
    },
    {
      name = "prev",
      field = "keymap_prev",
      desc = "previous marked node",
      rhs = function()
        M.goto_adjacent_mark(-1)
      end,
    },
  })
end

function M.teardown()
  bufevents.unregister("marks")
  _marks = {}
  if _adapter then
    local _, bufnr = _adapter.is_open()
    if bufnr then pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns(), 0, -1) end
  end
  _adapter = nil
end

return M
