---@module 'filetree.features.ui.cursor_hide'
---@brief Hide the block cursor while the tree window is focused.
---@description
--- Creates a window-local highlight override (winhighlight) so the cursor
--- disappears when focus is inside a tree buffer, and reappears on leave.
--- Uses a dedicated `FiletreeCursorHidden` hl group with blend=100 so the
--- global Cursor group is never touched.
---
--- Adapter-agnostic: the tree filetypes come from the active adapter's
--- optional `filetypes` capability (same pattern as window_style), so this
--- generalizes to whichever backend is configured. A superset covering all
--- known trees is used as a fallback when an adapter omits it.
---
--- The winhighlight entry is merged into whatever is already set on the
--- window rather than replacing it outright, so it survives regardless of
--- whether the tree plugin's own winhighlight (e.g. neo-tree's Normal/
--- NormalNC/... mapping) was applied before or after this handler runs.
---
--- Config:
---   enabled  boolean (default true)
---
--- Note: could not be confirmed via headless Neovim testing (no UIEnter
--- without a real UI attached makes VeryLazy fire unpredictably relative to
--- a scripted test). Confirmed working in real interactive use.

local bufevents = require("filetree.util.bufevents")
local au = require("filetree.util.autocmd")
local M = {}

---Option schema (see `filetree.config.schema`): exactly what
---`features.cursor_hide` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {}

local DEFAULT_FILETYPES = { "neo-tree", "NvimTree", "netrw", "oil", "minifiles" }

---@type integer?
local _augroup = nil
---@type FiletreeAdapter?
local _adapter = nil

---Tree filetypes to target — the adapter's if declared, else the superset.
---@return table<string, boolean>
local function tree_filetypes()
  local ft = _adapter and _adapter.filetypes
  local list = (type(ft) == "table" and #ft > 0) and ft or DEFAULT_FILETYPES
  local set = {}
  for _, f in ipairs(list) do
    set[f] = true
  end
  return set
end

---@param config FiletreeCursorHideConfig
function M.setup(config, adapter)
  if not config.enabled then return end
  _adapter = adapter

  vim.api.nvim_set_hl(0, "FiletreeCursorHidden", { blend = 100, nocombine = true })

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_cursor_hide", true)

  -- `lib.nvim.ui.winhighlight` rather than string concatenation and a
  -- gsub. It is the same merge-and-strip this used to do by hand, minus
  -- two rough edges: appending did not dedupe, so applying twice left
  -- `Cursor:X,Cursor:X`, and the strip was a Lua pattern over a value
  -- other plugins also write.
  local wh = require("lib.nvim.ui.winhighlight")

  local function apply_hide(win, buf)
    if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then return end
    if not tree_filetypes()[vim.bo[buf].filetype] then return end
    wh.update(win, { Cursor = "FiletreeCursorHidden" })
  end

  local function apply_show(win, buf)
    if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then return end
    if not tree_filetypes()[vim.bo[buf].filetype] then return end
    -- Strips our override only; every other entry on the window stays.
    wh.remove(win, "Cursor")
  end

  -- Deferred via vim.schedule: the tree plugin's own window/renderer setup
  -- (still running synchronously within the same BufEnter/WinEnter cycle)
  -- can re-touch winhighlight after this callback returns, so applying
  -- immediately loses the race. Deferring to the next tick - after that
  -- setup has fully settled - is what made window_style's equivalent
  -- fallback reliable; same fix here.
  bufevents.register("cursor_hide", { "BufEnter:*", "WinEnter:*" }, {
    desc = "[filetree] Hide the cursor in the tree window",
    load = function(ctx)
      local win = vim.api.nvim_get_current_win()
      vim.schedule(function()
        apply_hide(win, ctx.buf)
      end)
    end,
  })

  au.acmd({ "BufLeave", "WinLeave" }, {
    group = _augroup,
    desc = "[filetree] Restore the cursor when leaving the tree window",
    callback = function(ev)
      local win = vim.api.nvim_get_current_win()
      vim.schedule(function()
        apply_show(win, ev.buf)
      end)
    end,
  })
end

function M.teardown()
  bufevents.unregister("cursor_hide")
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
  _adapter = nil
end

return M
