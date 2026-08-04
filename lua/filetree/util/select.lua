---@module 'filetree.util.select'
--- Selection prompt — routes vim.ui.select through lib.nvim.ui.kit.
---
--- Drop-in for `vim.ui.select(items, opts, on_choice)`. When lib.nvim is present
--- it renders via `lib.nvim.ui.kit` (`kit.select`) for a consistent floating UI
--- across the author's plugins; otherwise it falls back to `vim.ui.select`. Call
--- sites keep the native signature:
---
---   local ui_select = require("filetree.util.select")
---   ui_select(items, { prompt = "…", format_item = f }, function(choice, idx) … end)

local _ok, kit = pcall(require, "lib.nvim.ui.kit")
local has_kit = _ok and type(kit) == "table" and type(kit.select) == "function"

---Prompt the user to select one of `items`, via lib.nvim.ui.kit if available.
---@param items any[]
---@param opts  table|nil   { prompt?, format_item? } (as vim.ui.select)
---@param on_choice fun(item: any|nil, idx: integer|nil)
return function(items, opts, on_choice)
  opts = opts or {}
  on_choice = on_choice or function() end

  if not has_kit then
    return vim.ui.select(items, opts, on_choice)
  end

  -- kit.select sizes the float to its widest item by default, so the old
  -- `auto_width` workaround for hover_select's fixed min-width is no longer
  -- needed. format_item/index-remapping is kit.select's own job now too.
  kit.select({
    items     = items,
    title     = opts.prompt,
    format_item = opts.format_item,
    on_select = on_choice,
    -- kit.select reports cancellation through on_cancel rather than by
    -- calling on_select with nil; translate back since this shim's whole
    -- point is a vim.ui.select-shaped drop-in for its callers.
    on_cancel = function()
      on_choice(nil, nil)
    end,
  })
end
