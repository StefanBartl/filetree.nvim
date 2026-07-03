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

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type integer?
local _augroup = nil

local function do_reset()
  -- 1. Preview
  local ok1, preview = require("filetree.features").load("preview")
  if ok1 and preview.close then pcall(preview.close) end

  -- 2. Filter
  local ok2, filter = require("filetree.features").load("filter")
  if ok2 and filter.clear then pcall(filter.clear) end

  -- 3. Live search
  local ok3, ls = require("filetree.features").load("live_search")
  if ok3 and ls.clear then pcall(ls.clear) end

  -- 4. Watcher quarantine
  local ok4, wq = require("filetree.features").load("watcher_quarantine")
  if ok4 and wq.is_active and wq.is_active() then pcall(wq.exit) end

  -- 5. Search highlights
  vim.cmd("nohlsearch")
end

---@param config FiletreeTreeResetConfig
function M.setup(config, _adapter)
  if not config.enabled then return end

  local keymap = config.keymap or "<Esc>"

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_tree_reset", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        map("n", keymap, do_reset, {
          buffer = buf,
          silent = true,
          desc   = "Filetree: reset tree UI state (preview, filter, search)",
        })
      end)
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
