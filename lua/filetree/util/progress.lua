---@module 'filetree.util.progress'
--- Thin wrapper around lib.nvim.progress (a hard dependency): a progress
--- indicator for an operation that runs over multiple files/nodes (batch
--- trash, batch paste, …), with style="auto" defaulting to fidget/notify, or
--- style="statusline" to feed lib.nvim's headless statusline registry
--- (`lib.nvim.progress.styles.statusline.active()`).

local progress_mod = require("lib.nvim.progress")

local M = {}

---Global style, set once from `setup({ progress_style = … })`. Per-call
---`opts.style` (if given) always wins. Mirrors util.notify's `set_debug`.
---@type Lib.Progress.Style?
local _style = nil

---@param style Lib.Progress.Style?
function M.set_style(style)
  _style = style
end

---Create a progress handle.
---@param opts Lib.Progress.Opts
---@return table?
function M.create(opts)
  opts = opts or {}
  return progress_mod.create(vim.tbl_extend("keep", opts, { style = _style }))
end

return M
