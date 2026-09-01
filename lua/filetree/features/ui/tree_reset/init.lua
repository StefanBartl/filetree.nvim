---@module 'filetree.features.tree_reset'
---@brief Single-key reset for all active UI state in the tree.
---@description
--- Binds a key (default <Esc>) in the tree buffer that performs a coordinated
--- teardown of every piece of transient UI state that filetree.nvim may have
--- left open:
---
---   1. Close the preview floating window (features/preview)
---   2. Clear the filter dimming         (features/filter)
---   3. Clear the live-search dimming    (features/live_search)
---   4. Exit watcher quarantine          (features/watcher_quarantine)
---   5. Clear Neovim search highlights   (:nohlsearch)
---
--- Each step is guarded with pcall so a missing or disabled feature is silently
--- skipped.  The reset key itself does NOT close the tree window.
---
--- Config:
---   enabled  boolean
---   keymap   string?   Key in tree buffer (default "<Esc>").

local bind = require("filetree.util.bind")
local M = {}

local function do_reset()
  -- 1. Preview
  local ok1, preview = require("filetree.features").load("preview")
  if preview and preview.close then pcall(preview.close) end

  -- 2. Filter
  local ok2, filter = require("filetree.features").load("filter")
  if filter and filter.clear then pcall(filter.clear) end

  -- 3. Live search
  local ok3, ls = require("filetree.features").load("live_search")
  if ls and ls.clear then pcall(ls.clear) end

  -- 4. Watcher quarantine
  local ok4, wq = require("filetree.features").load("watcher_quarantine")
  if wq and wq.is_active and wq.is_active() then pcall(wq.exit) end

  -- 5. Search highlights
  vim.cmd("nohlsearch")
end

---@param config FiletreeTreeResetConfig
function M.setup(config, _adapter)
  if not config.enabled then return end

  bind.bind("tree_reset", config, {
    {
      name = "reset",
      field = "keymap",
      default = "<Esc>",
      rhs = do_reset,
      desc = "reset tree UI state (preview, filter, search)",
    },
  })
end

function M.teardown() end

return M
