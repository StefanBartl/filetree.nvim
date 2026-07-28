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
---   1. cwd_mode's held root, when a mode holds one (lock / project / …).
---   2. cwd_mode's marker walk from `path` (or the current buffer) — the same
---      walk that decides where the cwd goes, so a search and the cwd cannot
---      disagree about which directory is "the project".
---   3. project_root's own (broader) marker walk, when cwd_mode is disabled.
---   4. `getcwd()`.
---
--- Steps 2 and 3 are the same question asked of two different marker sets, and
--- the older code asked only the second: cwd_sync would anchor the cwd to the
--- git root while find_files scoped itself to the nearest `package.json` under
--- it. One walk now governs both; `nearest` mode is how you ask for the
--- package instead, deliberately.

local M = {}

---The authoritative root for `path`.
---@param path string?  File or directory to resolve for. Defaults to the current buffer's file, then the cwd.
---@return string
function M.find(path)
  local registry = require("filetree.features")

  local mode = registry.require("cwd_mode")
  if mode and type(mode.pinned) == "function" then
    -- `pinned()` rather than `root()`: root() falls back to the cwd, which
    -- would swallow the marker walks below in follow mode.
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

  if mode and type(mode.resolve) == "function" then
    local ok, root = pcall(mode.resolve, target)
    if ok and root and root ~= "" then
      return root
    end
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
