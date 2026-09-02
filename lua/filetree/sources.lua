---@module 'filetree.sources'
---@brief Which tree sources a feature's keymaps belong to.
---@description
--- A tree is not one thing. neo-tree renders a filesystem, a buffer list, a
--- git status, a symbol outline and a diagnostics list through the same window
--- and the same `neo-tree` filetype -- so "bind this key on tree buffers" binds
--- it in all five, whether or not the feature has anything to act on there.
---
--- This module is the one list of exceptions, and it is one list on purpose:
--- filetree puts its keys into a tree along two entirely separate paths, and
--- before this they could disagree without anyone noticing.
---
---   * `util.tree_attach` -> `util.bind` binds the actual keys, buffer-locally,
---     from a single `FileType neo-tree` autocmd. This is what a keypress
---     reaches.
---   * `attach.inject` writes `window.mappings` entries so the keys appear in
---     neo-tree's `?` cheatsheet. This is what a reader sees.
---
--- Both now ask here. A feature restricted to `filesystem` is neither bound nor
--- listed anywhere else.
---
--- A feature absent from `RESTRICTED` is unrestricted and reaches every source,
--- which is what all of them did before this module existed. Add one only with
--- a reason of the same kind as the one below.

local M = {}

--- Feature -> the neo-tree sources its keymaps may reach.
---
--- `trash` is restricted because its three actions all presuppose a filesystem
--- node: trash the node under the cursor, undo that, list what was trashed.
--- A `document_symbols` outline or a `diagnostics` list has no such node, so
--- `d`, `U` and `<leader>th` were keys that either did nothing useful there or
--- -- worse -- reached the trash store from a tree that has nothing to do with
--- it. `<leader>th` additionally shadowed lsp.nvim's global inlay-hint toggle
--- in trees where nothing was offered in exchange.
---@type table<string, string[]>
M.RESTRICTED = {
  trash = { "filesystem" },
}

--- May `feature`'s keymaps appear in `source`?
---
--- `source` is `nil` when the caller does not know which tree it is looking at:
--- an adapter other than neo-tree (NvimTree has no sources), or a shared
--- `window.mappings` table that every source inherits. Those two cases want
--- opposite answers, so they are not conflated:
---
---   * `strict = false` (default) -- "unknown" means *allow*. This is the
---     binding path: a non-neo-tree adapter must keep behaving as it always
---     did rather than silently lose keys.
---   * `strict = true` -- "unknown" means *deny*. This is the shared-table
---     path: being inherited by every source is exactly what a restricted
---     feature must not do.
---@param feature string
---@param source string|nil
---@param strict boolean|nil
---@return boolean
function M.allows(feature, source, strict)
  local allowed = M.RESTRICTED[feature]
  if not allowed then return true end
  if source == nil then return not strict end
  return vim.tbl_contains(allowed, source)
end

--- The neo-tree source a tree buffer is showing, if it says.
---
--- neo-tree sets `b:neo_tree_source` in its renderer, which is *after* the
--- `FileType` event -- measured 2026-09-02: nil in a `FileType neo-tree`
--- callback, `"filesystem"` by the next `vim.schedule` tick. `tree_attach`
--- already defers its dispatch by exactly one tick (it has to, to land past
--- the adapter's own keymaps), so by the time this is called the value is
--- there. Anything else -- another adapter, a buffer neo-tree has not rendered
--- -- answers `nil`, which `allows` reads as "do not restrict".
---@param buf integer
---@return string|nil
function M.of_buffer(buf)
  local ok, src = pcall(vim.api.nvim_buf_get_var, buf, "neo_tree_source")
  if ok and type(src) == "string" and src ~= "" then return src end
  return nil
end

return M
