---@module 'filetree.util.select'
---@brief Selection prompt — routes vim.ui.select through lib.nvim.ui.hover_select.
---@description
--- Drop-in for `vim.ui.select(items, opts, on_choice)`. When lib.nvim is present
--- it renders via `lib.nvim.ui.hover_select` for a consistent floating UI across
--- the author's plugins; otherwise it falls back to `vim.ui.select`. Call sites
--- keep the native signature:
---
---   local ui_select = require("filetree.util.select")
---   ui_select(items, { prompt = "…", format_item = f }, function(choice, idx) … end)

local _ok, hover = pcall(require, "lib.nvim.ui.hover_select")
local has_hover = _ok and type(hover) == "table" and type(hover.open) == "function"

---@param items any[]
---@param opts  table|nil   { prompt?, format_item? } (as vim.ui.select)
---@param on_choice fun(item: any|nil, idx: integer|nil)
return function(items, opts, on_choice)
  opts = opts or {}
  on_choice = on_choice or function() end

  if not has_hover then
    return vim.ui.select(items, opts, on_choice)
  end

  local format = type(opts.format_item) == "function" and opts.format_item or tostring
  local display = {}
  for i, item in ipairs(items) do
    display[i] = format(item)
  end

  hover.open({
    items     = display,
    title     = opts.prompt,
    on_select = function(_, index)
      local idx = type(index) == "table" and index[1] or index
      on_choice(items[idx], idx)
    end,
  })
end
