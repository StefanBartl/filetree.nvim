---@module 'filetree.features.opened_sync'
---@brief Keep the tree's "opened files" decoration in sync with real buffer state.
---@description
--- Tree plugins that colour the nodes of currently-open files (neo-tree's
--- `name.highlight_opened_files`, for instance) only re-evaluate that decoration
--- when they re-render — which does NOT reliably happen when you merely open or
--- close a buffer elsewhere. The result: a file you just closed still shows as
--- "open" in the tree until you manually close and reopen the tree.
---
--- This feature fixes that by asking the adapter for a cheap re-render
--- (`adapter.redraw()` — re-render from existing state, NO filesystem rescan)
--- shortly after a buffer is added, deleted, wiped, or (un)displayed. Debounced
--- so a burst of buffer events (e.g. `:bufdo`, session restore) collapses into a
--- single redraw, and a no-op when the tree isn't open or the adapter can't
--- redraw cheaply.

local au = require("filetree.util.autocmd")
local M = {}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer?
local _augroup = nil

---@type any?  pending uv debounce timer
local _timer = nil

---@type FiletreeOpenedSyncConfig
local _cfg = {}

local function cancel_timer()
  if _timer then
    pcall(function() _timer:stop(); _timer:close() end)
    _timer = nil
  end
end

local function redraw_now()
  if not _adapter then return end
  if not _adapter.is_open() then return end
  if type(_adapter.redraw) == "function" then
    pcall(_adapter.redraw)
  end
end

local function debounced_redraw()
  cancel_timer()
  local uv = vim.uv or vim.loop
  _timer = uv.new_timer()
  _timer:start(_cfg.debounce_ms or 60, 0, vim.schedule_wrap(function()
    cancel_timer()
    redraw_now()
  end))
end

---@param config FiletreeOpenedSyncConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  -- Nothing to sync if the adapter can't cheaply re-render.
  if type(adapter.redraw) ~= "function" then return end
  _cfg     = config
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_opened_sync", true)

  -- Buffer open/close/show/hide — the events that change which files count as
  -- "open". Deliberately NOT BufEnter (fires on every cursor-into-buffer and is
  -- far too chatty for a redraw); the set below already covers add/remove and
  -- window (un)display of a buffer.
  au.acmd({ "BufAdd", "BufDelete", "BufWipeout", "BufWinEnter", "BufWinLeave" }, {
    group    = _augroup,
    callback = debounced_redraw,
  })
end

function M.teardown()
  cancel_timer()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
