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

local M = {}

---@type integer?
local _augroup = nil

local function do_reset()
  -- 1. Preview
  local ok1, preview = pcall(require, "filetree.features.preview")
  if ok1 and preview.close then pcall(preview.close) end

  -- 2. Filter
  local ok2, filter = pcall(require, "filetree.features.filter")
  if ok2 and filter.clear then pcall(filter.clear) end

  -- 3. Live search
  local ok3, ls = pcall(require, "filetree.features.live_search")
  if ok3 and ls.clear then pcall(ls.clear) end

  -- 4. Watcher quarantine
  local ok4, wq = pcall(require, "filetree.features.watcher_quarantine")
  if ok4 and wq.is_active and wq.is_active() then pcall(wq.exit) end

  -- 5. Search highlights
  vim.cmd("nohlsearch")
end

---@param config FiletreeTreeResetConfig
function M.setup(config, _adapter)
  if not config.enabled then return end

  local keymap = config.keymap or "<Esc>"

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_tree_reset", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.keymap.set("n", keymap, do_reset, {
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
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
