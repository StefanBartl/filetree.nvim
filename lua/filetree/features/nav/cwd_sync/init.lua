---@module 'filetree.features.nav.cwd_sync'
--- Keep Neovim's cwd (and the tree root) in sync with the current buffer.
---
--- Debounced BufEnter/WinEnter handler for the active buffer's file:
---
---   1. Resolves the target root, in order: `root_markers` (default { ".git" },
---      cached via lib.nvim's find_root) → `use_project_root` (the broader
---      project_root marker set) → the file's own parent directory. Shared
---      with auto_reveal's out-of-root fallback via `filetree.util.target_dir`
---      (see that module).
---   2. change_dir (default true): if that root differs from the current cwd,
---      silently `chdir` to it — never prompts.
---   3. reveal (default true): also root the tree at the SAME resolved
---      directory and reveal the file there (fast-path scroll when already
---      visible, else adapter.open_reveal). Set `reveal = false` when the
---      underlying tree PLUGIN already follows the cwd on its own (neo-tree's
---      `bind_to_cwd` + `follow_current_file`; nvim-tree.lua's
---      `update_focused_file`) so the two reveals don't race — cwd_sync then
---      only manages the cwd. Adapters without such a native feature (netrw,
---      oil, mini_files) need `reveal = true` (the default) — cwd_sync's own
---      reveal is the only thing that does this job for them. See
---      doc/filetree.txt §5.3 for the full per-adapter table.
---
---      This feature (cwd_sync) is itself opt-in (disabled by default). Only
---      while it is OFF (or paused) does auto_reveal's `follow_root` (on by
---      default) act as a fallback and reveal the file itself — see that
---      module. Once cwd_sync is active, `reveal_active()` reports so
---      regardless of `reveal`'s own value: with `reveal = false` the intent
---      is "the adapter's native follow owns the tree UI here", and
---      auto_reveal firing its own re-root in that window would race that
---      native follow the exact way `reveal = false` exists to prevent (see
---      `M.reveal_active()`'s own comment for the full reasoning). A `reveal
---      = false` setup that turns out to need the fallback after all should
---      pair it with a working native follow, per the recipes below, rather
---      than lean on auto_reveal to paper over one that isn't firing.
---
--- No full tree refresh/rescan is issued — the reveal (or the tree plugin's own
--- cwd-follow) re-renders anyway, so a separate rescan would be redundant work.
---
--- Pauses automatically when the user navigates manually in the tree (detected
--- via cursor movement inside the tree window).

local notify = require("filetree.util.notify").create("[filetree.cwd_sync]")
local path = require("filetree.util.path")
local lib_debounce = require("lib.nvim.debounce")
local chdir = require("lib.nvim.fs.chdir")
local target_dir_util = require("filetree.util.target_dir")

local bufevents = require("filetree.util.bufevents")
local au = require("filetree.util.autocmd")
local M = {}

---Option schema (see `filetree.config.schema`): exactly what
---`features.cwd_sync` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {
  debounce_ms = { "number", min = 0 },
  parent_levels = { "number", min = 0 },
  keep_focus = "boolean",
  change_dir = "boolean",
  reveal = "boolean",
  use_project_root = "boolean",
  root_markers = { "table|false", of = "string" },
}

---@class CwdSyncState
---@field last_path       string?  Last file we revealed.
---@field last_root       string?  Tree root as of that reveal -- see do_reveal's dedup check.
---@field paused_until    number   Timestamp (uv.hrtime) after which sync resumes.

---@type CwdSyncState
local S = {
  last_path = nil,
  last_root = nil,
  paused_until = 0,
}

---Debounce handle built in M.setup() (needs `_cfg.debounce_ms`); `{ call, cancel }`.
---@type table?
local _debounce = nil

---@type integer?
local _augroup = nil

---@type FiletreeCwdSyncConfig
local _cfg = {}

---Whether M.setup() actually ran (the feature is enabled and active) -- unlike
---checking `_cfg.reveal` alone, this is false before any setup() and after
---teardown(), so `M.reveal_active()` cannot mistake "never configured" for
---"reveal explicitly enabled" (an unset field reads as `~= false`, i.e. true).
---@type boolean
local _active = false

---@type FiletreeAdapter?
local _adapter = nil

---Built in M.setup() from `_cfg.root_markers`/`use_project_root` via
---`filetree.util.target_dir` -- shared with auto_reveal's `follow_root`
---fallback so both features resolve the identical directory for the same
---file (see that module's header for why that makes redundant work safe).
---@type fun(file: string): string
local _resolve_target_dir

---@internal
---@return boolean
local function paused()
  local uv = vim.uv or vim.loop
  return uv.hrtime() < S.paused_until
end

---@internal
---@param ms integer?
local function pause(ms)
  local uv = vim.uv or vim.loop
  S.paused_until = uv.hrtime() + (ms or 2000) * 1e6
end

---Compare two directories for equality, ignoring separator style and a
---trailing slash.
---@param a string
---@param b string
---@return boolean
---@internal
local function same_dir(a, b)
  local na = path.slashify(a):gsub("/$", "")
  local nb = path.slashify(b):gsub("/$", "")
  return na == nb
end

---Ask the cwd_mode feature what its active policy wants for this file.
---
---Returns nil when the feature is absent or in "follow" mode — the deliberate
---"no policy" answer, which leaves the resolution below exactly as it was
---before cwd_mode existed.
---@internal
---@param file string
---@return FiletreeCwdDecision?
---@see filetree.features.nav.cwd_mode
local function policy(file)
  local registry = require("filetree.features")
  local mode = registry.require("cwd_mode")
  if not mode or type(mode.decide) ~= "function" then return nil end
  local ok, decision = pcall(mode.decide, file)
  return ok and decision or nil
end

---The directory scope cwd_sync's own chdir should use.
---
---Unlike `policy()` this is asked even in follow mode: the scope is a property
---of the cwd policy as such, not of any one mode. A `tab`-scoped setup whose
---buffer switches still moved the *global* cwd would only be half a policy.
---Falls back to "global" — the historical behaviour — when cwd_mode is absent
---or disabled.
---@return Lib.Fs.Chdir.Scope
---@internal
local function chdir_scope()
  local mode = require("filetree.features").require("cwd_mode")
  if mode and type(mode.scope) == "function" then
    local ok, scope = pcall(mode.scope)
    if ok and scope then return scope end
  end
  return "global"
end

---@internal
---@param path_ string
local function do_reveal(path_)
  if not _adapter then return end
  if paused() then return end
  -- The root check alongside `last_path` matters: without it, the tree's root
  -- changing out from under cwd_sync through some OTHER path (tree_traverse's
  -- `-`/`+`, a session restore, a manual `set_root`) left this dedup stuck on
  -- stale state -- re-entering the very file it last revealed then short-
  -- circuited here before ever reaching the chdir/reveal logic below, even
  -- though the tree was no longer actually rooted where that reveal had put
  -- it. `reveal_active()` has no visibility into this skip either, so
  -- auto_reveal's `follow_root` fallback (trusting cwd_sync to have handled
  -- it) silently didn't catch it -- the file stayed unrevealed by either
  -- feature until some other file was visited first.
  if S.last_path == path_ and S.last_root == (_adapter.get_root_path() or nil) then return end

  S.last_path = path_

  -- Resolve the target root ONCE (git root / project root / parent) and use it
  -- for BOTH the cwd and the tree root. Previously the reveal derived its own
  -- root from the file's parent, so the tree showed the parent dir even though
  -- the cwd had been chdir'd to the project root — that mismatch was the "tree
  -- shows parent instead of project root" bug.
  --
  -- A cwd_mode policy (lock / project / manual) overrides that resolution: it
  -- holds state this function cannot see — "stay in this directory no matter
  -- which buffer is focused" — and it also decides whether the cwd and the
  -- tree may move *at all*, which is why the two permissions are separate
  -- below. cwd_sync stays the executor; the policy decides.
  local decision = policy(path_)
  local allow_chdir = true
  local allow_reveal = true
  local root

  if decision then
    allow_chdir = decision.chdir ~= false
    allow_reveal = decision.reveal ~= false
    if not allow_chdir and not allow_reveal then return end
    root = decision.root
  end

  root = root or _resolve_target_dir(path_)
  S.last_root = root ~= "" and root or nil

  -- Silently chdir to the root when it differs. Never prompts. Deliberately no
  -- _adapter.refresh() here: the reveal below re-roots/re-renders the tree, so a
  -- separate full filesystem rescan would be redundant work (a big source of lag).
  -- lib.nvim.fs.chdir rather than vim.fn.chdir: the latter's scope is implicit
  -- (it changes the global cwd, the tab's or the window's depending on what the
  -- current window happens to carry), so a tab-scoped policy could not be
  -- honoured here at all. It also validates the path and returns an error
  -- instead of throwing.
  local cwd_changed = false
  if
    allow_chdir
    and _cfg.change_dir ~= false
    and root ~= ""
    and not same_dir(root, vim.fn.getcwd())
  then
    local ok, err = chdir(root, { scope = chdir_scope() })
    if ok then
      cwd_changed = true
    else
      notify.warn(err or ("could not change cwd to: " .. root))
    end
  end

  -- reveal = false: only manage the cwd; let the tree plugin's own cwd binding
  -- and follow handle rooting/revealing (e.g. neo-tree `bind_to_cwd = true` +
  -- `follow_current_file`). Doing our own reveal here would fight that — the two
  -- reveals race and the tree can settle on the file's parent instead of the root.
  if _cfg.reveal == false then return end

  -- The policy vetoed re-rooting: the buffer is outside the held root, and
  -- revealing it would drag the tree out of the directory the mode exists to
  -- hold. The cwd part above has already run (or been vetoed on its own).
  if not allow_reveal then return end

  -- Fast path: the file is already rendered in the current tree and the root did
  -- not change. Just move the tree cursor to its line instead of neo-tree's heavy
  -- show/reveal round-trip (which rescans the filesystem and re-renders). This is
  -- the common case — opening files within the same project — and is what caused
  -- the "nvim hangs when opening files" lag.
  if
    not cwd_changed
    and type(_adapter.get_node_line) == "function"
    and type(_adapter.scroll_to_line) == "function"
  then
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
      if vim.api.nvim_win_is_valid(cur_win) then vim.api.nvim_set_current_win(cur_win) end
    end, 50)
  end
end

---@internal
local function debounced_reveal()
  local file = vim.fn.expand("%:p")
  if file == "" or vim.fn.filereadable(file) == 0 then return end
  if _debounce then _debounce.call(file) end
end

---@param config FiletreeCwdSyncConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = config
  _adapter = adapter
  _active = true

  if _debounce then _debounce.cancel() end
  _debounce = lib_debounce.new(do_reveal, _cfg.debounce_ms or 150)

  _resolve_target_dir = target_dir_util.new({
    root_markers = _cfg.root_markers,
    use_project_root = _cfg.use_project_root,
  })

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_cwd_sync", true)

  -- Registered for both scopes: the check below is about the tree WINDOW,
  -- which is not the same question as "is the current buffer a tree buffer"
  -- -- the tree window can briefly show something else.
  bufevents.register("cwd_sync", { "BufEnter:*", "WinEnter:*" }, {
    desc = "[filetree] Sync the working directory to the entered file",
    priority = bufevents.PRIORITY.CWD,
    load = function()
      -- Skip if cursor is inside the tree window
      local tree_winid = adapter.get_winid()
      if tree_winid and vim.api.nvim_get_current_win() == tree_winid then
        -- Only pause when we do our own reveal: that's the only case where a
        -- file opened from inside the tree (e.g. <CR> on a node) could race
        -- our reveal against the tree plugin's native follow/reveal. With
        -- reveal=false, do_reveal never touches the tree UI (chdir only), so
        -- there is nothing to race — pausing here would just drop the chdir
        -- for the file the tree is about to open, and (worse) for anything
        -- else that happens to open within the pause window, e.g. a picker
        -- invoked while the cursor was still in the tree.
        if _cfg.reveal ~= false then
          pause(2000) -- user is navigating manually
        end
        return
      end
      debounced_reveal()
    end,
  })

  -- Startup catch-up: a session-restore plugin (or any code that opens/shows
  -- the tree very early) can focus a buffer whose file is not under the
  -- launch-time cwd BEFORE this BufEnter/WinEnter autocmd above ever gets a
  -- chance to fire for it — there is no "buffer switch" event to react to if
  -- the relevant buffer was already current when we registered. Run one sync
  -- pass for whatever buffer ends up focused once startup settles, so the cwd
  -- is correct by the time anything (ours or the user's own keymaps) shows
  -- the tree. Mirrors the vim_did_enter check filetree/init.lua already uses
  -- for its own neo-tree post-setup work: if VimEnter already fired by the
  -- time setup() runs (the common case — filetree.nvim typically loads on a
  -- lazy event well after VimEnter), run immediately instead of waiting for
  -- an event that has already passed.
  if vim.v.vim_did_enter == 1 then
    vim.schedule(debounced_reveal)
  else
    au.acmd("VimEnter", {
      group = _augroup,
      once = true,
      desc = "[filetree] Sync the working directory once, for a startup that beat setup()",
      callback = debounced_reveal,
    })
  end
end

function M.teardown()
  bufevents.unregister("cwd_sync")
  if _debounce then _debounce.cancel() end
  _resolve_target_dir = nil
  _active = false
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
  S.last_path = nil
  S.last_root = nil
  S.paused_until = 0
end

---Manually pause auto-reveal for `ms` milliseconds.
---@param ms integer
function M.pause(ms)
  pause(ms)
end

---Whether cwd_sync already has the current buffer switch covered, one way or
---another, so auto_reveal's `follow_root` fallback should stand down instead
---of re-rooting the tree itself for the same event.
---
---True whenever cwd_sync is active and not `paused()` -- deliberately
---REGARDLESS of `_cfg.reveal`. `reveal = false` does not mean "cwd_sync does
---nothing here"; it means "the adapter's own native cwd-follow (neo-tree
---`bind_to_cwd` + `follow_current_file`) owns the tree UI for this switch,
---cwd_sync only manages the cwd" -- see do_reveal's own `_cfg.reveal == false`
---branch and its comment. auto_reveal calling `_adapter.open_reveal()` of its
---own accord in that configuration would fight the very native follow
---`reveal = false` was set to defer to (doc/filetree.txt's cwd_sync section
---documents this exact "tree settles on the file's parent instead of the
---project root" race for cwd_sync's own reveal; the mechanism is identical
---whichever feature places the second, colliding call). A user who sets
---`reveal = false` without a working native follow configured is already
---outside this feature's documented recipe (doc/filetree.txt §5.3 pairs the
---two), so that misconfiguration -- not a race -- is the more honest failure
---mode to leave them with.
---
---Also false while `paused()` (the user just navigated manually in the tree):
---`do_reveal` bails out on that same check before it would reveal anything, so
---without this, auto_reveal would skip its own fallback for up to the pause
---duration trusting a reveal that is never going to happen -- leaving a file
---outside the tree's root unrevealed by either feature.
---@return boolean
function M.reveal_active()
  return _active and not paused()
end

return M
