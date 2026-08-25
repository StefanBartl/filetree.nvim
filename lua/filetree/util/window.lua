---@module 'filetree.util.window'
--- Window helpers — delegate to lib.nvim.window, with fallbacks.
---
--- Thin wrapper so filetree shares lib.nvim's floating/scratch-window
--- conventions when present, and still runs standalone otherwise.
---
---   local window = require("filetree.util.window")
---   window.nice_quit(winid)                 -- bind q/<Esc> to close winid
---   window.nice_quit(winid, { keys = {…} }) -- custom close keys
---   window.open_editor_window(adapter)      -- new editor window, never on the tree's side

local _ok, lib = pcall(require, "lib.nvim.window")
local has_lib = _ok and type(lib) == "table" and type(lib.nice_quit) == "function"

local M = {}

---Bind `q` / `<Esc>` (Normal mode, buffer-local) to close `winid`.
---@param winid integer
---@param opts table|nil  { keys?: string[], force?: boolean }
---@return boolean ok true when the keymaps were attached
function M.nice_quit(winid, opts)
  opts = opts or {}
  if has_lib then return lib.nice_quit(winid, opts) end

  if not vim.api.nvim_win_is_valid(winid) then return false end
  local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
  if not ok then return false end

  local keys = opts.keys or { "q", "<Esc>" }
  local force = opts.force == true
  for _, lhs in ipairs(keys) do
    vim.keymap.set("n", lhs, function()
      if vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, force) end
    end, { buffer = bufnr, nowait = true, silent = true, desc = "filetree: close window" })
  end
  return true
end

-- ── Editor-window placement ───────────────────────────────────────────────────

---Which screen edge the tree sidebar belongs to, so a new window can be placed
---on the OPPOSITE one.
---
---Asks the adapter first (`get_position()` — neo-tree keeps this in its own
---state and it survives the window being closed), then falls back to reading
---the tree window's actual column. The geometry fallback is deliberately
---skipped when the tree spans the full width: that is exactly the "tree is the
---only window" case, where the sidebar has been stretched over the whole screen
---and its column says nothing about which side it is configured for.
---
---Returns nil when the tree has no side at all (float / "current" position, no
---tree open, adapter can't say) — callers then place the window with plain
---`:vsplit`, i.e. wherever 'splitright' wants it.
---@param adapter FiletreeAdapter?
---@return "left"|"right"|nil
function M.tree_side(adapter)
  if adapter and type(adapter.get_position) == "function" then
    local ok, pos = pcall(adapter.get_position)
    if ok then
      if pos == "left" then return "left" end
      if pos == "right" then return "right" end
      if pos then return nil end -- "float" / "current": no side to stay clear of
    end
  end

  local win = adapter and adapter.get_winid and adapter.get_winid()
  if not win or not vim.api.nvim_win_is_valid(win) then return nil end
  if vim.api.nvim_win_get_config(win).relative ~= "" then return nil end -- float
  if vim.api.nvim_win_get_width(win) >= vim.o.columns then return nil end
  return vim.api.nvim_win_get_position(win)[2] == 0 and "left" or "right"
end

---Command modifier that pins a new vertical split to the edge AWAY from `side`.
---Absolute (`topleft` / `botright`) on purpose: a bare `:vsplit` places the new
---window according to 'splitright' relative to the current window, so with the
---default (`splitright = false`) splitting the tree window put the new window
---to its LEFT — visually moving a left sidebar over to the right, which is the
---bug this exists to prevent.
---@param side "left"|"right"|nil
---@return string modifier  "" when there is no side to avoid.
function M.away_modifier(side)
  if side == "left" then return "botright" end
  if side == "right" then return "topleft" end
  return ""
end

---Open a new editor window that does not disturb the tree's side of the screen.
---
---Focus: normally lands in the new window (as a plain `:vsplit` would). When the
---caller runs while a FLOATING window is focused (a picker, an input prompt —
---layout_guard fires from autocmds that can trigger mid-picker), the split is
---made from the tree window via `nvim_win_call`, which restores the previous
---current window afterwards, so the float keeps focus and is not torn out from
---under the user.
---@param adapter FiletreeAdapter?
---@param opts { empty?: boolean }?  empty = start the window on a scratch `:enew` buffer.
---@return integer? winid  The new window, or nil when it could not be created.
function M.open_editor_window(adapter, opts)
  opts = opts or {}
  local modifier = M.away_modifier(M.tree_side(adapter))
  local cmd = vim.trim(modifier .. " vsplit")
  if opts.empty then cmd = cmd .. " | enew" end

  local new_win
  local function create()
    vim.cmd(cmd)
    new_win = vim.api.nvim_get_current_win()
  end

  local tree_win = adapter and adapter.get_winid and adapter.get_winid()
  local cur = vim.api.nvim_get_current_win()
  local in_float = vim.api.nvim_win_get_config(cur).relative ~= ""

  local ok
  if in_float and tree_win and vim.api.nvim_win_is_valid(tree_win) then
    ok = pcall(vim.api.nvim_win_call, tree_win, create)
  else
    ok = pcall(create)
  end

  if not ok then
    -- Vertical split refused (too narrow, 'winminwidth'): fall back horizontally.
    ok = pcall(function()
      vim.cmd(opts.empty and "new" or "split")
      new_win = vim.api.nvim_get_current_win()
    end)
  end
  return ok and new_win or nil
end

return M
