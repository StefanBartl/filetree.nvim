---@module 'filetree.util.root'
---@brief The one answer to "which project are we in right now".
---@description
--- Several features need a project root: find_files scopes its search to one,
--- grep_in_dir searches inside one, git_status decorates the tree from one,
--- breadcrumbs count relative to one. Each of them resolved it by hand, with
--- the same chain — `project_root.find(<current buffer>)`, else `getcwd()`.
---
--- That chain has a blind spot: it asks the *buffer*. Open a file from another
--- project while cwd_mode holds a root (a lock, or a sticky project) and every
--- one of those features silently switches to the other project, even though
--- the tree, the cwd and the mode badge all still say otherwise — git_status
--- would decorate a tree rooted at /notes with the status of /repos/foo.
---
--- So the mode gets asked first. Resolution order:
---
---   1. cwd_mode's held root, when a mode holds one (lock / project).
---   2. project_root's marker walk from `path` (or the current buffer).
---   3. `getcwd()`.
---
--- In follow mode — the default — step 1 never fires and this behaves exactly
--- like the hand-rolled chain it replaces.

local M = {}

---The authoritative root for `path`.
---@param path string?  File or directory to resolve for. Defaults to the current buffer's file, then the cwd.
---@return string
function M.find(path)
  local registry = require("filetree.features")

  local mode = registry.require("cwd_mode")
  if mode and type(mode.pinned) == "function" then
    -- `pinned()` rather than `root()`: root() falls back to the cwd, which
    -- would swallow the project_root walk below in follow mode.
    local ok, held = pcall(mode.pinned)
    if ok and held and held ~= "" then
      return held
    end
  end

  local target = path
  if not target or target == "" then
    target = vim.api.nvim_buf_get_name(0)
  end
  if not target or target == "" then
    target = vim.fn.getcwd()
  end

  local ok_pr, pr = registry.load("project_root")
  if ok_pr and pr and type(pr.find) == "function" then
    local ok, root = pcall(pr.find, target)
    if ok and root and root ~= "" then
      return root
    end
  end

  return vim.fn.getcwd()
end

return M
