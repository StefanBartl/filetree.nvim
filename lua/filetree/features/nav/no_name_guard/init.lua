---@module 'filetree.features.nav.no_name_guard'
---@brief Redirect stray [No Name] editor windows to a real buffer, then wipe them.
---@description
--- Neovim shows a scratch [No Name] buffer in a window whenever that window
--- has no buffer to display (a `:bd`/`:bwipeout` with no alternate, `:enew`,
--- or cycling back into a leftover one) — `BufWinEnter` fires for it exactly
--- at that moment, scoped to the one window involved. When another real file
--- buffer is open, that window is redirected to it and the stray buffer is
--- deleted outright; otherwise it's left alone (nothing else to show).
---
--- Deliberately scoped to the single (buffer, window) pair from the
--- triggering event rather than a sweep of every window in the tabpage: a
--- global sweep reacting to unrelated close events elsewhere (an LSP scratch
--- buffer, a completion float, another split) would occasionally catch a
--- [No Name] window the user had just deliberately tabbed into and yank them
--- back out of it — a race between the sweep and the user's own navigation.
--- Reacting to this window's own BufWinEnter instead ties the action
--- causally to the buffer actually being looked at, so it fires deterministically.
---
--- Tree-aware by construction: the tree window (`adapter.get_winid()`) is
--- always excluded, so this can never race with the tree plugin's own
--- window/buffer bookkeeping during open/close — the failure mode
--- ("state.tree nil" during neo-tree's own startup sequence) that forced the
--- generic, adapter-unaware version of this guard to be disabled in the host
--- config it was ported from.

local buffer = require("filetree.util.buffer")
local au = require("filetree.util.autocmd")

local M = {}

---@type integer?
local _augroup = nil

---Re-validate and act on one specific (bufnr, winid) pair. Deferred one tick
---so it runs after Neovim has fully settled the window/buffer switch that
---triggered BufWinEnter, and re-checked at execution time in case the user
---already typed into the buffer or navigated away in the meantime.
---@param bufnr integer
---@param winid integer
---@param tree_winid integer|nil  The tree's own window, always skipped.
local function handle(bufnr, winid, tree_winid)
  vim.schedule(function()
    if winid == tree_winid then return end
    if not vim.api.nvim_win_is_valid(winid) then return end
    if vim.api.nvim_win_get_config(winid).relative ~= "" then return end -- float
    if vim.api.nvim_win_get_buf(winid) ~= bufnr then return end -- user already moved on
    if not buffer.is_stray_no_name(bufnr) then return end -- e.g. typed into it since

    local repl = buffer.find_named_buffer({ [bufnr] = true })
    if not repl then
      -- No real buffer to switch to -- this IS the legitimate case (e.g. the
      -- last file buffer just closed). Leave the [No Name] buffer as-is.
      return
    end

    pcall(vim.api.nvim_win_set_buf, winid, repl)
    pcall(vim.api.nvim_buf_delete, bufnr, {})
  end)
end

---@param config FiletreeNoNameGuardConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  au.del_group(_augroup)
  _augroup = au.group("filetree_no_name_guard", true)

  au.acmd("BufWinEnter", {
    group = _augroup,
    callback = function(event)
      if not buffer.is_stray_no_name(event.buf) then return end
      handle(event.buf, vim.api.nvim_get_current_win(), adapter.get_winid())
    end,
  })
end

function M.teardown()
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
