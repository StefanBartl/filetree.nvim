---@module 'filetree.util.mutate'
---@brief The one way filetree.nvim moves a path on disk.
---@description
--- Wraps `lib.nvim.cross.fs.mutate.rename_file` with the two behaviours every
--- caller needs and each used to re-implement (smart_rename, rename_batch,
--- copy_move, move):
---
---   * **Windows sharing locks** — a move is the classic EPERM/EACCES/EBUSY
---     trigger (neo-tree's directory watcher, an indexer or AV still holding
---     the handle). lib.nvim retries those; `watch.release` frees neo-tree's
---     watcher on the source before each retry (a no-op unless the
---     handle_guard feature installed the registry).
---   * **Cross-device moves** — `uv.fs_rename` cannot cross filesystems or
---     drive letters and returns EXDEV, which is *not* transient and so is not
---     retried. `vim.fn.rename` can (it copies and deletes internally), so it
---     takes over for exactly that case: the rare cross-drive move keeps
---     working, while the common same-drive one keeps its retry protection.
---
---   local mutate = require("filetree.util.mutate")
---   local ok, err = mutate.move(src, dst)

local fsops = require("lib.nvim.cross.fs.mutate")
local watch = require("lib.nvim.neotree.watch")

local M = {}

---Move `src` to `dst`.
---@param src string
---@param dst string
---@return boolean ok
---@return string? err
function M.move(src, dst)
  local ok, err = fsops.rename_file(src, dst, {
    on_retry = function() watch.release(src) end,
  })
  if ok then return true, nil end

  if type(err) == "string" and err:match("^EXDEV") then
    if vim.fn.rename(src, dst) == 0 then return true, nil end
  end
  return false, err
end

return M
