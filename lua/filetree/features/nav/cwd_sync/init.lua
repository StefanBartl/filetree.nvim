---@module 'filetree.features.cwd_sync'
---@brief Keep Neovim's cwd (and the tree root) in sync with the current buffer.
---@description
--- Debounced BufEnter/WinEnter handler for the active buffer's file:
---
---   1. Resolves the target root, in order: `root_markers` (default { ".git" },
---      cached via lib.nvim's find_root) → `use_project_root` (the broader
---      project_root marker set) → the file's own parent directory.
---   2. change_dir (default true): if that root differs from the current cwd,
---      silently `chdir` to it — never prompts.
---   3. reveal (default true): also root the tree at the SAME resolved
---      directory and reveal the file there (fast-path scroll when already
---      visible, else adapter.open_reveal). Set `reveal = false` when the tree
---      plugin already follows the cwd itself (e.g. neo-tree's `bind_to_cwd` +
---      `follow_current_file`) so the two reveals don't race — cwd_sync then
---      only manages the cwd. See doc/filetree.txt §5.3 for that setup.
---
--- No full tree refresh/rescan is issued — the reveal (or the tree plugin's own
--- cwd-follow) re-renders anyway, so a separate rescan would be redundant work.
---
--- Pauses automatically when the user navigates manually in the tree (detected
--- via cursor movement inside the tree window).

local notify = require("filetree.util.notify").create("[filetree.cwd_sync]")
local path = require("filetree.util.path")

local au  = require("filetree.util.autocmd")
local M = {}

---@class CwdSyncState
---@field timer           any?     Pending uv timer handle.
---@field last_path       string?  Last file we revealed.
---@field paused_until    number   Timestamp (uv.hrtime) after which sync resumes.
---@field user_navigated  boolean  Set when the user moved inside the tree manually.

---@type CwdSyncState
local S = {
  timer          = nil,
  last_path      = nil,
  paused_until   = 0,
  user_navigated = false,
}

---@type integer?
local _augroup = nil

---@type FiletreeCwdSyncConfig
local _cfg = {}

---@type FiletreeAdapter?
local _adapter = nil

---Cached marker-based root finder from lib.nvim.fs.find_root.
---@class FiletreeRootFinder
---@field find  fun(path: string): string?
---@field clear fun()

---nil when disabled via root_markers=false, or lib.nvim is unavailable
---@type FiletreeRootFinder?
local _root_finder = nil

local function paused()
  local uv = vim.uv or vim.loop
  return uv.hrtime() < S.paused_until
end

local function pause(ms)
  local uv = vim.uv or vim.loop
  S.paused_until = uv.hrtime() + (ms or 2000) * 1e6
end

local function cancel_timer()
  if S.timer then
    pcall(function()
      S.timer:stop()
      S.timer:close()
    end)
    S.timer = nil
  end
end

---Compare two directories for equality, ignoring separator style and a
---trailing slash.
---@param a string
---@param b string
---@return boolean
local function same_dir(a, b)
  local na = path.slashify(a):gsub("/$", "")
  local nb = path.slashify(b):gsub("/$", "")
  return na == nb
end

---Resolve the directory `file` should put Neovim's cwd in.
---Resolution order:
---  1. Nearest ancestor containing a configured stable marker (default `.git`),
---     via the cached lib.nvim finder. This keeps the cwd anchored to a stable
---     high-level root so opening files across a project doesn't cause frequent
---     cwd jumps. Disabled with `root_markers = false`.
---  2. The project_root feature's broader marker set (when use_project_root).
---  3. The file's own parent directory.
---@param file string
---@return string
local function target_dir(file)
  if _root_finder then
    local ok, root = pcall(_root_finder.find, file)
    if ok and root and root ~= "" then return root end
  end
  if _cfg.use_project_root ~= false then
    local registry = require("filetree.features")
    local proot = registry.require("project_root")
    if proot then
      local ok, root = pcall(proot.find, file)
      if ok and root and root ~= "" then return root end
    end
  end
  return path.parent(file)
end

local function do_reveal(path_)
  if not _adapter then return end
  if paused() then return end
  if S.last_path == path_ then return end

  S.last_path = path_

  -- Resolve the target root ONCE (git root / project root / parent) and use it
  -- for BOTH the cwd and the tree root. Previously the reveal derived its own
  -- root from the file's parent, so the tree showed the parent dir even though
  -- the cwd had been chdir'd to the project root — that mismatch was the "tree
  -- shows parent instead of project root" bug.
  local root = target_dir(path_)

  -- Silently chdir to the root when it differs. Never prompts. Deliberately no
  -- _adapter.refresh() here: the reveal below re-roots/re-renders the tree, so a
  -- separate full filesystem rescan would be redundant work (a big source of lag).
  local cwd_changed = false
  if _cfg.change_dir ~= false and root ~= "" and not same_dir(root, vim.fn.getcwd()) then
    if pcall(vim.fn.chdir, root) then
      cwd_changed = true
    else
      notify.warn("could not change cwd to: " .. root)
    end
  end

  -- reveal = false: only manage the cwd; let the tree plugin's own cwd binding
  -- and follow handle rooting/revealing (e.g. neo-tree `bind_to_cwd = true` +
  -- `follow_current_file`). Doing our own reveal here would fight that — the two
  -- reveals race and the tree can settle on the file's parent instead of the root.
  if _cfg.reveal == false then return end

  -- Fast path: the file is already rendered in the current tree and the root did
  -- not change. Just move the tree cursor to its line instead of neo-tree's heavy
  -- show/reveal round-trip (which rescans the filesystem and re-renders). This is
  -- the common case — opening files within the same project — and is what caused
  -- the "nvim hangs when opening files" lag.
  if not cwd_changed
    and type(_adapter.get_node_line) == "function"
    and type(_adapter.scroll_to_line) == "function" then
    local line = _adapter.get_node_line(path_)
    if line then
      _adapter.scroll_to_line(line)
      return
    end
  end

  -- Slow path: the node is not currently visible (its parent dir is collapsed) or
  -- the root changed — do a full reveal, rooting the tree at the resolved project
  -- root so the tree matches the cwd.
  local ok = _adapter.open_reveal(path_, _cfg.parent_levels or 0, root ~= "" and root or nil)
  if not ok then
    notify.warn("reveal failed for: " .. path_)
    return
  end

  if _cfg.keep_focus then
    -- Restore focus to the editor window after a brief delay
    local cur_win = vim.api.nvim_get_current_win()
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(cur_win) then
        vim.api.nvim_set_current_win(cur_win)
      end
    end, 50)
  end
end

local function debounced_reveal()
  cancel_timer()
  local file = vim.fn.expand("%:p")
  if file == "" or vim.fn.filereadable(file) == 0 then return end

  local uv = vim.uv or vim.loop
  S.timer = uv.new_timer()
  S.timer:start(_cfg.debounce_ms or 150, 0, vim.schedule_wrap(function()
    cancel_timer()
    do_reveal(file)
  end))
end

---@param config FiletreeCwdSyncConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = config
  _adapter = adapter

  -- Build the cached stable-root finder unless disabled (root_markers = false).
  -- Default markers are { ".git" } so the cwd anchors to the git root.
  _root_finder = nil
  local markers = _cfg.root_markers
  if markers == nil then markers = { ".git" } end
  if markers ~= false then
    local ok, find_root = pcall(require, "lib.nvim.fs.find_root")
    if ok and type(find_root) == "function" then
      _root_finder = find_root({ markers = markers })
    end
  end

  if _augroup then
    au.del_group(_augroup)
  end
  _augroup = au.group("filetree_cwd_sync", true)

  au.acmd({ "BufEnter", "WinEnter" }, {
    group    = _augroup,
    callback = function()
      -- Skip if cursor is inside the tree window
      local tree_winid = adapter.get_winid()
      if tree_winid and vim.api.nvim_get_current_win() == tree_winid then
        pause(2000) -- user is navigating manually
        return
      end
      debounced_reveal()
    end,
  })
end

function M.teardown()
  cancel_timer()
  _root_finder = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
  S.last_path      = nil
  S.paused_until   = 0
  S.user_navigated = false
end

---Manually pause auto-reveal for `ms` milliseconds.
---@param ms integer
function M.pause(ms)
  pause(ms)
end

return M
