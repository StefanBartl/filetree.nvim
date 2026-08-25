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
--- Two complementary passes:
---
---   `handle()` reacts to THIS window's own BufWinEnter, tying the action
---   causally to the buffer actually being looked at, so it fires
---   deterministically the moment a stray buffer becomes the focused one.
---
---   `sweep()` additionally reacts to BufAdd/BufDelete/BufWipeout with a pass
---   over every window (all tabs), catching a stray [No Name] buffer sitting
---   in some OTHER window that never itself refires BufWinEnter — e.g. it was
---   already there before this feature's autocmds attached, or its window
---   just isn't the one receiving focus events. Without this, such a buffer
---   could sit alongside real, usable buffers indefinitely.
---
--- Both defer one tick (`vim.schedule`) and re-validate at execution time —
--- BufDelete/BufWipeout in particular fire mid-transition, before Neovim has
--- settled the window's replacement buffer, so acting synchronously risks
--- catching a buffer that's about to be replaced anyway. Deferring past that
--- transition, then re-checking, is the same defensive shape `handle()`
--- already used for BufWinEnter's own equivalent risk (a race between this
--- guard and the user's own navigation).
---
--- Tree-aware by construction: the tree window (`adapter.get_winid()`) is
--- always excluded, so this can never race with the tree plugin's own
--- window/buffer bookkeeping during open/close — the failure mode
--- ("state.tree nil" during neo-tree's own startup sequence) that forced the
--- generic, adapter-unaware version of this guard to be disabled in the host
--- config it was ported from. `sweep()` is exactly that generic version's
--- shape (a sweep of every window), reused here now that it excludes the
--- tree window the same way `handle()` does.

local buffer = require("filetree.util.buffer")
local au = require("filetree.util.autocmd")

local M = {}

---@type integer?
local _augroup = nil

---Redirect `winid` (currently showing `bufnr`) to a real buffer and wipe the
---stray one, if `bufnr` is still a legitimate stray [No Name] buffer and a
---real buffer exists to redirect to. Shared by `handle()` (one window, tied
---to a BufWinEnter event) and `sweep()` (every window, tied to the buffer
---list changing) below — same redirect, two different triggers for it.
---@param winid integer
---@param bufnr integer
local function redirect_if_stray(winid, bufnr)
  if not vim.api.nvim_win_is_valid(winid) then return end
  if vim.api.nvim_win_get_config(winid).relative ~= "" then return end -- float
  if vim.api.nvim_win_get_buf(winid) ~= bufnr then return end -- moved on since
  if not buffer.is_stray_no_name(bufnr) then return end -- e.g. typed into it since

  local repl = buffer.find_named_buffer({ [bufnr] = true })
  if not repl then
    -- No real buffer to switch to -- this IS the legitimate case (e.g. the
    -- last file buffer just closed). Leave the [No Name] buffer as-is.
    return
  end

  pcall(vim.api.nvim_win_set_buf, winid, repl)
  pcall(vim.api.nvim_buf_delete, bufnr, {})
end

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
    redirect_if_stray(winid, bufnr)
  end)
end

---Sweep every window, across all tabs, for a stray [No Name] buffer sitting
---alongside real ones. See the module doc for why this is deferred +
---re-validated per window rather than acting inline.
---@param tree_winid integer|nil  The tree's own window, always skipped.
local function sweep(tree_winid)
  vim.schedule(function()
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if winid ~= tree_winid then redirect_if_stray(winid, vim.api.nvim_win_get_buf(winid)) end
    end
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

  au.acmd({ "BufAdd", "BufDelete", "BufWipeout" }, {
    group = _augroup,
    callback = function()
      sweep(adapter.get_winid())
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
