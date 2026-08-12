# Backends

The five tree plugins filetree.nvim can drive through the
[adapter abstraction](CORE.md#backend-adapter-abstraction), plus the
plumbing that exists specifically because one of them (neo-tree, on
Windows/WSL) leaks OS-level file handles.

## neo-tree adapter

`adapter = "neotree"`. The most complete adapter — the only one with a
native `?` cheatsheet integration (filetree injects its own keymaps into
neo-tree's `window.mappings`, see `attach.lua`), a native "follow cwd"
feature (`bind_to_cwd`/`follow_current_file`) that `cwd_sync.reveal` should
defer to, and libuv directory watchers that motivate `handle_guard`/
`watcher_quarantine` below. Resolves the current node via `lib.nvim.neotree.node`
when `lib.nvim` is present, with a local fallback otherwise.

- **Module:** [`adapter/neotree.lua`](../../lua/filetree/adapter/neotree.lua) — `filetypes = {"neo-tree"}`
- **Config:** `opts.adapter = "neotree"`

## nvim-tree adapter

`adapter = "nvimtree"`. Talks to nvim-tree via its own `nvim-tree.api`
module. Has its own native cwd-follow (`update_focused_file.enable`), with
a **verified caveat**: `update_focused_file.update_root.enable` is not a
drop-in equivalent of neo-tree's `bind_to_cwd` — it actively drives the cwd
itself and falls back to the file's own directory (not a project root) when
nothing else matches, so with it enabled nvim-tree overwrites cwd_sync's
git-root-anchored cwd on every switch regardless of `cwd_sync.reveal`. Leave
`update_root` at its default `false` if `root_markers` should win.

- **Module:** [`adapter/nvimtree.lua`](../../lua/filetree/adapter/nvimtree.lua) — `filetypes = {"NvimTree"}`
- **Config:** `opts.adapter = "nvimtree"`

## netrw adapter

`adapter = "netrw"`. Neovim's built-in netrw, no external plugin dependency.
No native cwd-follow — `cwd_sync.reveal` should stay `true` here, or a
project switch is never revealed at all.

- **Module:** [`adapter/netrw.lua`](../../lua/filetree/adapter/netrw.lua) — `filetypes = {"netrw"}`
- **Config:** `opts.adapter = "netrw"`

## oil.nvim adapter

`adapter = "oil"`. Same shape as netrw: no native cwd-follow, so
`cwd_sync.reveal = true` (the default) is the only thing that reveals a
newly-focused file's project.

- **Module:** [`adapter/oil.lua`](../../lua/filetree/adapter/oil.lua) — `filetypes = {"oil"}`
- **Config:** `opts.adapter = "oil"`

## mini.files adapter

`adapter = "mini_files"`. Same shape again — no native cwd-follow.

- **Module:** [`adapter/mini_files.lua`](../../lua/filetree/adapter/mini_files.lua) — `filetypes = {"minifiles"}`
- **Config:** `opts.adapter = "mini_files"`

## Auto-resolution

`adapter = "auto"` (the default) tries `neotree → nvimtree → netrw → oil →
mini_files` in that fixed order and picks the first whose `is_available()`
returns true — so with both neo-tree and nvim-tree installed, neo-tree wins
unless the adapter is pinned explicitly.

- **Module:** [`adapter/init.lua`](../../lua/filetree/adapter/init.lua) (`M.resolve`)
- **Config:** `opts.adapter = "auto"` (default)

## File Watcher

Watches the tree root directory for filesystem changes via `vim.uv.fs_event`
(libuv) and auto-refreshes the tree — `ReadDirectoryChangesW` on Windows,
inotify/kqueue on POSIX. Debounces bursts of events before calling
`adapter.refresh()`, and re-arms whenever the tree root changes.

- **Module:** [`features/infra/file_watcher/init.lua`](../../lua/filetree/features/infra/file_watcher/init.lua)
- **Config:** `opts.features.file_watcher` — `enabled` (default **false**, opt-in), `debounce_ms` (500), `watch_recursive` (true), `ignore_events` (`{}`)
- **Usercmds:** `:Filetree watcher enter [ms]`, `:Filetree watcher exit`

## Watcher Quarantine

On Windows, libuv file watchers can emit spurious `EPERM` errors when a file
or directory is deleted/moved while watched. This feature suspends watching
for a configurable window and suppresses the resulting error notifications
— it hides the symptom rather than fixing the cause (see `handle_guard`
below for the fix). Complementary, not a replacement: the two can run
together.

- **Module:** [`features/infra/watcher_quarantine/init.lua`](../../lua/filetree/features/infra/watcher_quarantine/init.lua) (`M.enter`, `M.exit`, `M.is_active`, `M.wrap`)
- **Config:** `opts.features.watcher_quarantine` — `enabled` (default **false**), `duration_ms` (500), `silent` (true), `patch_neotree_watch` (true — wraps neo-tree's `fs_watch` callbacks to swallow EPERM)
- **Usercmds:** `:Filetree watcher enter [ms]`, `:Filetree watcher exit` (shared dispatcher with `file_watcher`)

## Handle Guard

Fixes the same Windows/WSL file-lock at its source instead of hiding it:
neo-tree's own directory watchers (with `use_libuv_file_watcher = true`)
keep an OS handle open per expanded directory and never close it, so
renaming/deleting a watched directory can intermittently fail with
`EPERM`/`ERROR_SHARING_VIOLATION` because filetree's own watcher is still
holding it. Once enabled it wires automatically into the fileops that move/
rename/trash a watched path (via `lib.nvim.cross.fs.mutate`'s `on_retry`
hook calling `M.release(path)`), closing the offending libuv handle so the
retry succeeds. neo-tree adapter + Windows/WSL only — a safe no-op
everywhere else, so the fileops' hook can always be passed unconditionally.

- **Module:** [`features/infra/handle_guard/init.lua`](../../lua/filetree/features/infra/handle_guard/init.lua) (`M.release`)
- **Config:** `opts.features.handle_guard.enabled` (default **false**, opt-in — patches a neo-tree internal and closes libuv handles it owns)
- **Usercmds:** `:Filetree handles` — lists tracked handles, flags any pointing at a path that no longer exists (the leak signature)
