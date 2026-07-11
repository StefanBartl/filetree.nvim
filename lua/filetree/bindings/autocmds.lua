---@module 'filetree.bindings.autocmds'
---@brief Catalog of the autocmds filetree.nvim registers, by event.
---@description
--- Behavioural autocmds only (feature keymaps are also bound via a FileType
--- autocmd but are cataloged in bindings.keymaps). All groups are named
--- `filetree_<feature>` and are cleared on re-setup. Per-feature autocmds can be
--- disabled via the top-level `autocmds = { <feature> = false }` config.

---@class FiletreeAutocmdEntry
---@field event   string|string[]
---@field feature string
---@field desc    string

---@type FiletreeAutocmdEntry[]
return {
  { event = "FileType",                    feature = "*",          desc = "Bind each enabled feature's tree-buffer keymaps" },
  { event = "CursorMoved",                 feature = "preview",    desc = "Live-update the preview as the cursor moves" },
  { event = "CursorMoved",                 feature = "current_hl", desc = "Re-highlight the current node line" },
  { event = { "BufEnter", "WinEnter" },    feature = "cwd_sync",   desc = "Reveal the current buffer's file in the tree" },
  { event = { "BufEnter", "WinEnter" },    feature = "auto_reveal",desc = "Scroll/highlight the current file (no cwd change)" },
  { event = { "BufLeave", "WinLeave" },    feature = "preview",    desc = "End/close the preview when leaving the tree" },
  { event = "BufWritePost",                feature = "marks",      desc = "Redraw mark indicators after writes" },
  { event = "ColorScheme",                 feature = "current_hl", desc = "Re-apply highlight groups after colorscheme change" },
  { event = "ColorScheme",                 feature = "window_style", desc = "Re-isolate tree highlight groups" },
  { event = "VimResized",                  feature = "auto_resize",desc = "Adjust tree width to the new column count" },
  { event = { "BufDelete", "BufWipeout", "WinClosed" }, feature = "layout_guard", desc = "Open an editor window if the tree is left alone" },
  { event = { "BufAdd", "BufDelete", "BufWipeout", "BufWinEnter", "BufWinLeave" }, feature = "opened_sync", desc = "Redraw the tree so opened-file highlights stay in sync" },
  { event = "BufDelete",                   feature = "*",          desc = "Invalidate the buffer-validation cache (util.buffer)" },
}
