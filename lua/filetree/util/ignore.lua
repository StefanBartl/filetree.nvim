---@module 'filetree.util.ignore'
---@brief Shared accessor for the ignore_list feature's path-output predicate.
---@description
--- `features.infra.ignore_list` resolves and owns the canonical ignore
--- basenames/patterns (user config → lib.nvim → built-in fallback) and hides
--- them from the tree display. This is the single call-through other
--- features use to get the *same* list as a predicate they can hand to
--- `filetree.util.fs.collect_files`/`collect_folders`, so recursive
--- path-output actions (copy_file_list, markdown_links, …) don't surface
--- `.git`, `node_modules`, etc. -- without duplicating the ignore rules.
--- Filesystem-mutating actions (copy_move, trash, rename_batch, …) must NOT
--- use this: they operate on the real, complete tree by design.

local M = {}

---Ignore predicate for `filetree.util.fs`'s `ignore_fn(name): boolean` shape.
---Ignores nothing if the ignore_list feature is disabled or unavailable, so
---callers stay correct even when the feature never loaded.
---@return fun(name: string): boolean
function M.predicate()
  local ok, ig = require("filetree.features").load("ignore_list")
  if ok and ig and type(ig.predicate) == "function" then return ig.predicate() end
  return function()
    return false
  end
end

return M
