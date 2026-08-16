---@module 'filetree.util.progress'
--- Thin wrapper around lib.nvim.progress (optional dependency): a progress
--- indicator for an operation that runs over multiple files/nodes (batch
--- trash, batch paste, …), with style="auto" defaulting to fidget/notify, or
--- style="statusline" to feed lib.nvim's headless statusline registry
--- (`lib.nvim.progress.styles.statusline.active()`).
---
--- No-op (returns nil) when lib.nvim isn't installed — the operation still
--- runs, just without the indicator; callers guard every use with `if prog
--- then … end`.

local ok_progress, progress_mod = pcall(require, "lib.nvim.progress")

local M = {}

---Global style, set once from `setup({ progress_style = … })`. Per-call
---`opts.style` (if given) always wins. Mirrors util.notify's `set_debug`.
---@type Lib.Progress.Style?
local _style = nil

---@param style Lib.Progress.Style?
function M.set_style(style)
  _style = style
end

---Create a progress handle, or nil if lib.nvim.progress isn't installed.
---@param opts Lib.Progress.Opts
---@return table?
function M.create(opts)
  if not ok_progress then return nil end
  opts = opts or {}
  return progress_mod.create(vim.tbl_extend("keep", opts, { style = _style }))
end

return M
