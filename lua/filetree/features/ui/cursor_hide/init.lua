---@module 'filetree.features.cursor_hide'
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
--- KNOWN GAP: this feature's winhighlight override could not be confirmed
--- live in headless Neovim testing (0/N across several rounds, including
--- with a real WinLeave+WinEnter focus-switch and a vim.schedule-deferred
--- callback), despite the module loading, its config resolving correctly,
--- and no error being thrown. A host-side fallback that recolors the global
--- Cursor group is kept alongside this until the discrepancy is understood
--- or this is confirmed working in a real interactive session.

local au  = require("filetree.util.autocmd")
local M = {}

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
  for _, f in ipairs(list) do set[f] = true end
  return set
end

---@param config FiletreeCursorHideConfig
function M.setup(config, adapter)
  if not config.enabled then return end
  _adapter = adapter

  vim.api.nvim_set_hl(0, "FiletreeCursorHidden", { blend = 100, nocombine = true })

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_cursor_hide", true)

  local function apply_hide(win, buf)
    if not tree_filetypes()[vim.bo[buf].filetype] then return end
    local ok, cur = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = win })
    local base = (ok and cur ~= "") and (cur .. ",") or ""
    pcall(vim.api.nvim_set_option_value, "winhighlight",
      base .. "Cursor:FiletreeCursorHidden", { win = win })
  end

  local function apply_show(win, buf)
    if not tree_filetypes()[vim.bo[buf].filetype] then return end
    local ok, cur = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = win })
    if not ok then return end
    -- Strip our override; leave any other winhighlight entries intact.
    local cleaned = cur:gsub(",?Cursor:FiletreeCursorHidden,?", ""):gsub("^,", ""):gsub(",$", "")
    pcall(vim.api.nvim_set_option_value, "winhighlight", cleaned, { win = win })
  end

  -- Deferred via vim.schedule: the tree plugin's own window/renderer setup
  -- (still running synchronously within the same BufEnter/WinEnter cycle)
  -- can re-touch winhighlight after this callback returns, so applying
  -- immediately loses the race. Deferring to the next tick - after that
  -- setup has fully settled - is what made window_style's equivalent
  -- fallback reliable; same fix here.
  au.acmd({ "BufEnter", "WinEnter" }, {
    group = _augroup,
    callback = function(ev)
      vim.schedule(function() apply_hide(vim.api.nvim_get_current_win(), ev.buf) end)
    end,
  })

  au.acmd({ "BufLeave", "WinLeave" }, {
    group = _augroup,
    callback = function(ev)
      local win = vim.api.nvim_get_current_win()
      vim.schedule(function() apply_show(win, ev.buf) end)
    end,
  })
end

function M.teardown()
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
  _adapter = nil
end

return M
