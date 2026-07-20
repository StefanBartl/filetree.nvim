---@module 'filetree.util.window'
---@brief Window helpers — delegate to lib.nvim.window, with fallbacks.
---@description
--- Thin wrapper so filetree shares lib.nvim's floating/scratch-window
--- conventions when present, and still runs standalone otherwise.
---
---   local window = require("filetree.util.window")
---   window.nice_quit(winid)                 -- bind q/<Esc> to close winid
---   window.nice_quit(winid, { keys = {…} }) -- custom close keys

local _ok, lib = pcall(require, "lib.nvim.window")
local has_lib = _ok and type(lib) == "table" and type(lib.nice_quit) == "function"

local M = {}

---Bind `q` / `<Esc>` (Normal mode, buffer-local) to close `winid`.
---@param winid integer
---@param opts table|nil  { keys?: string[], force?: boolean }
---@return boolean ok true when the keymaps were attached
function M.nice_quit(winid, opts)
  opts = opts or {}
  if has_lib then
    return lib.nice_quit(winid, opts)
  end

  if not vim.api.nvim_win_is_valid(winid) then return false end
  local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
  if not ok then return false end

  local keys  = opts.keys or { "q", "<Esc>" }
  local force = opts.force == true
  for _, lhs in ipairs(keys) do
    vim.keymap.set("n", lhs, function()
      if vim.api.nvim_win_is_valid(winid) then
        pcall(vim.api.nvim_win_close, winid, force)
      end
    end, { buffer = bufnr, nowait = true, silent = true, desc = "filetree: close window" })
  end
  return true
end

return M
