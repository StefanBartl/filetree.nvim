---@module 'filetree.util.select'
--- Selection prompt — routes vim.ui.select through ui.kit.
---
--- Drop-in for `vim.ui.select(items, opts, on_choice)`. Renders via `ui.kit`
--- (`kit.select`) for a consistent floating UI across the author's plugins.
--- ui.nvim is a required dependency (see docs/installation.md) and ui.kit is
--- bare-required the same way it is everywhere else in this plugin; there is
--- no `vim.ui.select` fallback. Call sites keep the native signature:
---
---   local ui_select = require("filetree.util.select")
---   ui_select(items, { prompt = "…", format_item = f }, function(choice, idx) … end)

local kit = require("ui.kit")

---Prompt the user to select one of `items`, via ui.kit.
---@param items any[]
---@param opts  table|nil   { prompt?, format_item?, relative?, width?, height? } (the first
---                         two as vim.ui.select; the rest forwarded to kit.select as-is, nil
---                         by default so every existing caller keeps kit.select's own default
---                         (cursor-anchored) placement/sizing — pass `relative = "editor"` for
---                         a centered float instead, e.g. a picker over a long list of full
---                         paths that reads better centered than pinned near the cursor.
---@param on_choice fun(item: any|nil, idx: integer|nil)
return function(items, opts, on_choice)
  opts = opts or {}
  on_choice = on_choice or function() end

  -- kit.select sizes the float to its widest item by default, so the old
  -- `auto_width` workaround for hover_select's fixed min-width is no longer
  -- needed. format_item/index-remapping is kit.select's own job now too.
  kit.select({
    items = items,
    title = opts.prompt,
    format_item = opts.format_item,
    relative = opts.relative,
    width = opts.width,
    height = opts.height,
    on_select = on_choice,
    -- kit.select reports cancellation through on_cancel rather than by
    -- calling on_select with nil; translate back since this shim's whole
    -- point is a vim.ui.select-shaped drop-in for its callers.
    on_cancel = function()
      on_choice(nil, nil)
    end,
  })
end
