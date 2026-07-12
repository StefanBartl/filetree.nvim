---@module 'filetree.util.select'
---@brief Selection prompt — routes vim.ui.select through lib.nvim.ui.kit.
---@description
--- Drop-in for `vim.ui.select(items, opts, on_choice)`. When lib.nvim is present
--- it renders via `lib.nvim.ui.kit` (`kit.select`) for a consistent floating UI
--- across the author's plugins; otherwise it falls back to `vim.ui.select`. Call
--- sites keep the native signature:
---
---   local ui_select = require("filetree.util.select")
---   ui_select(items, { prompt = "…", format_item = f }, function(choice, idx) … end)

local _ok, kit = pcall(require, "lib.nvim.ui.kit")
local has_kit = _ok and type(kit) == "table" and type(kit.select) == "function"

---@param items any[]
---@param opts  table|nil   { prompt?, format_item? } (as vim.ui.select)
---@param on_choice fun(item: any|nil, idx: integer|nil)
return function(items, opts, on_choice)
  opts = opts or {}
  on_choice = on_choice or function() end

  if not has_kit then
    return vim.ui.select(items, opts, on_choice)
  end

  local format = type(opts.format_item) == "function" and opts.format_item or tostring
  local display = {}
  for i, item in ipairs(items) do
    display[i] = format(item)
  end

  -- kit.select sizes the float to its widest item by default, so the old
  -- `auto_width` workaround for hover_select's fixed min-width is no longer
  -- needed.
  kit.select({
    items     = display,
    title     = opts.prompt,
    on_select = function(_, index)
      local idx = type(index) == "table" and index[1] or index
      on_choice(items[idx], idx)
    end,
  })
end
