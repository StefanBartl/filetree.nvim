# TESTS/

Everything CI runs, plus the manual pass it cannot.

| | |
| --- | --- |
| [`smoke.lua`](smoke.lua) | integration: every feature module loads, opt-out defaults resolve, registry resolver + binding catalog work |
| [`units.lua`](units.lua) | unit: util layer, neo-tree adapter helpers, the reference engine's apply/undo layer and the chooser |
| [`menu.lua`](menu.lua) | unit: `integrations/menu.lua`, against a stubbed `filetree` module |
| [`cwd_mode.lua`](cwd_mode.lua) | unit: the cwd/root policy feature, against a stub adapter and a temp tree |
| [`sidebar_guard.lua`](sidebar_guard.lua) | unit: `&winfixbuf` pinning of the tree window, neo-tree event (un)subscription, no-op on a non-neotree adapter |
| [`nav_switch_toggle.lua`](nav_switch_toggle.lua) | unit: `source_switcher` (pick / cycle / display names for neo-tree sources) and `tree_toggle` (global positional toggle keys), plus the neo-tree adapter's E95 self-heal in `toggle_at` and the bookkeeping of its `renderer.redraw` hook install (a failed wrap is never marked as installed; a reload re-points instead of stacking) — against a stubbed `neo-tree` / `neo-tree.command` / `neo-tree.ui.renderer` |
| [`config_schema.lua`](config_schema.lua) | unit: the per-feature option schemas (`filetree.config.schema`) — the engine, the `setup()` paths (typo, wrong type, out-of-range, non-table body, the deprecated `refs` options), and a drift check that every feature module exports a `SCHEMA` accepting its own defaults and declaring every option it reads |
| [`create_from_template.lua`](create_from_template.lua) | unit: `create_from_template`'s template-first flow — `M.move` never crossing the `[custom]`/`[builtin]` boundary, header rows only for mixed sets, filename pre-filled from the picked template, and the reorderable picker's cursor kept off header rows (against a `ui.kit` picker double that owns a real results window) |
| [`gaps.lua`](gaps.lua) | unit: fs-heavy and lifecycle modules `units.lua`/`smoke.lua` had not reached yet — see "gaps.lua" below |
| [`adapter_lines.lua`](adapter_lines.lua) | integration: the adapter's line→node mapping, against a **real neo-tree and a real nvim-tree** — the only suite that needs a tree plugin — plus two neo-tree-only regression pins: a background-tab redraw resolving the tree's own per-tab state (not whichever tab is current), and two simultaneously live per-tab trees each resolving and decorating their own tree without bleeding into the other's |
| [`group_empty_dirs_collapse.lua`](group_empty_dirs_collapse.lua) | integration: `<S-CR>` (`open_variants.open_badd_or_collapse`) collapsing a neo-tree `group_empty_dirs` merged directory line, against a **real neo-tree** — drives the actual `<CR>`/`<S-CR>` buffer keymaps, not the adapter function directly |
| [`neotree_redraw_hook.lua`](neotree_redraw_hook.lua) | integration: the `renderer.redraw` monkeypatch (`adapter/neotree.lua`'s `install_redraw_hook`/`hoist_redraw_hook`) against a **real neo-tree**, run in its own process — real `copy_to_clipboard`/`cut_to_clipboard` (`y`/`x`) in the exact load order a lazily-loaded neo-tree.nvim gives, and the last-resort tab probe's ghost-state cleanup |
| [`refs/`](refs/) | fixture-based: real on-disk multi-file projects, described below |
| [`MANUAL.md`](MANUAL.md) | the manual checklist for what a headless run cannot reach — real neo-tree, real floats, real clipboard |

All of them are headless and exit 0 on a pass. `.github/workflows/ci.yml`'s
`test` job gates on the ten stub-based suites above `adapter_lines.lua` in
the table, plus `refs/run.lua`; it does not install neo-tree/nui/devicons, so
the three real-neo-tree suites (`adapter_lines.lua`, `group_empty_dirs_collapse.lua`,
`neotree_redraw_hook.lua`) always print a skip there today rather than
running for real — a pre-existing CI gap, not something this pass closes.
All but `adapter_lines.lua`,
`group_empty_dirs_collapse.lua` and `neotree_redraw_hook.lua` run against a
stub adapter and need no tree plugin; those three need neo-tree (plus
nui/plenary/devicons, and lib.nvim for the first) and print a skip instead
of failing when they are absent, because what they test needs a real
backend: `adapter_lines.lua`'s line→node mapping is precisely what a stub
cannot have, `group_empty_dirs_collapse.lua` exercises neo-tree's own
merge/replace machinery (`ui/renderer.lua`'s `group_empty_dirs` branch), and
`neotree_redraw_hook.lua` needs a real, controllable `require()` order against
neo-tree's own modules that a stub cannot reproduce. `MANUAL.md` describes
each in more detail and carries the lib.nvim resolution notes.

`neotree_redraw_hook.lua` deliberately reloads core neo-tree modules and
controls their `require()` order, which no other suite in this repo may
safely do once it shares a process with other neo-tree-backed checks — so it
runs in its OWN `nvim -l` process rather than being folded into
`adapter_lines.lua`.

## gaps.lua

Added in the test-coverage campaign's round 26 pass over this repo (129
`lua/` files is too large for one uniform pass — see the campaign handover
for the full accounting). Split into its own file rather than appended to
`units.lua`, which was already ~5000 lines. Same framework-free
`check`/`eq` harness and rtp/`TMP_ROOT` setup as `units.lua`.

Covers, with real (not merely load-time) assertions, in risk order:

- **fs ops / argv / error paths**: `util/conflict.lua` (collision-name
  generation, incl. dotfile and multi-dot-extension edge cases),
  `refs/pathutil.lua` (the reference engine's Windows-safe path core —
  backslash/forward-slash equivalence, case-insensitive comparison, the
  three `resolve_candidates()` target styles, `retarget()`'s per-style
  spelling, `remap_under()`'s directory-move cascade), `util/markdown_refs.lua`
  (disk + live-buffer patch layer, content-verified skip of a drifted line),
  `features/infra/safety/backup.lua` (real mkdir/copy/prune against a
  **stubbed `lib.nvim.cross.run_argv`** — no real `xcopy`/`cp` process
  spawned, but the real argv shape is asserted), `features/fileops/buffer_save`
  (force-save the adjacent editor buffer or the node under the cursor, incl.
  three no-crash error paths).
- **the refs↔fileops.nvim bridge**: a contract pin asserting
  `filetree.refs.outgoing_assets`/`outgoing_assets_mode` are still functions
  — the exact two-function presence check fileops.nvim's
  `integrations/filetree_assets.lua` uses to decide filetree.nvim is
  installed and current enough to cascade-delete assets through.
- **caching / state machines**: `features/infra/watcher_quarantine.lua`
  (enter/exit/is_active/is_path_quarantined, the `vim.notify` EPERM-swallow
  patch and its exact restore, `wrap()`'s error passthrough).
- **buffer/window lifecycle**: `features/fileops/open_replace.lua`
  (replace vs. swap, the modified-buffer refusal that avoids E89, the
  already-open-file short-circuit, the closed buffer's slot), `features/nav/layout_guard.lua`
  (a new editor window appears when the last one closes next to the tree;
  no-op when the tree itself is reported closed).
- **adapter helpers**: `adapter/mini_files.lua`, stubbed at `mini.files` in
  `package.loaded` — same pattern as the existing neo-tree adapter-helpers
  suite in `units.lua`, including the adapter's own documented doubled-slash
  quirk after a Windows drive letter.
- **no subprocess needed, previously untested**: `features/lsp/lsp_diagnostics.lua`
  (severity aggregation, incl. a directory node summing its children) against
  real `vim.diagnostic.set()`; `features/compare/diff.lua` (stage/diff/
  diff_marked's exactly-2-marks gate); `features/git/git_status.lua`
  (`git status --porcelain` line parsing for every status code, incl. a
  quoted rename, against a **stubbed `vim.system`** — no real git process).

Deliberately not added in this pass (left for a later round, not because
they are exempt from the "raise coverage" goal):

- `features/system/shell_run.lua` (real `termopen`/`jobstart` terminal
  spawn), `features/system/open_with.lua` (a detached `vim.system` +
  `vim.ui.open`, meant to hand off to an OS app and not come back) — no
  stable stub seam short of replacing those vim.fn entry points wholesale.
- `features/system/pdf_create.lua`/`pdf_open.lua` — delegate to
  `util/pdf.lua`'s soft dependency on pdfport.nvim; not audited deeply
  enough this round to say whether that wrapper is cleanly stubbable the
  way `util/markdown_refs.lua`'s soft dependency was.
- `features/org/session.lua` — real fs read/write is straightforward to
  stub, but its `VimLeavePre`/`BufHidden` autosave timing and stdpath("data")
  override need more care than this pass's budget allowed.
- `util/usercmd.lua`, `util/progress.lua` — thin present/absent dependency
  wrappers (same shape as the existing "util.map / util.autocmd" section in
  `units.lua`); low risk, cheap to add, just not reached this round.
- `util/bind.lua` — already exercised indirectly by every feature's own
  keymap-binding tests; a dedicated suite would mostly repeat that coverage.

Round 26 also flagged `features/infra/file_watcher.lua`,
`features/nav/{auto_reveal,buffer_cycle,reveal_alt,tree_traverse}.lua`,
`features/paths/lua_require_copy.lua`, `features/search/{filter,live_search}.lua`,
and `features/ui/{window_style,window_size_cycler,cursor_hide,tree_reset,size_info,preview}.lua`
as confirmed genuinely untested beyond a load-time `require()`, for a later
round to pick up next. Round 27 (below) is that round, and closes all of
them.

### Round 27 (follow-up to round 26; still `gaps.lua`)

Closed every file round 26's list above deferred. Also re-audited round 26's
other skip reasons for rot before adding anything new: `features/system/shell_run.lua`,
`open_with.lua`, `pdf_create.lua`/`pdf_open.lua`, `org/session.lua`,
`util/usercmd.lua`, `util/progress.lua`, and `util/bind.lua` are all still
accurately described above — none gained a stub seam or a sibling-checkout
dependency since. neo-tree.nvim/nui.nvim/plenary.nvim/nvim-web-devicons are
real installs on a dev machine under `$LOCALAPPDATA/nvim-data/lazy`, and
`adapter_lines.lua`'s own candidate search already finds them there (that
suite is simply not one of the seven CI runs — it needs a real tree plugin
and prints a skip without one, which is what CI would get); nothing to close
there.

Covers, with real assertions, in risk order:

- **Windows path/separator + navigation** (highest risk: this is a file-tree
  UI with cursor/line navigation): `nav/auto_reveal.lua`'s `under_root()`
  exercised with a backslash-spelled adapter root against a forward-slash
  buffer path (both readings must agree it is inside), the `cursor_in_tree`
  guard (a forced `reveal_current()` while the cursor sits IN the tree must
  never fire `open_reveal`), and the `only_if_open` guard; `paths/lua_require_copy.lua`'s
  `copy_require_relative()` against the REAL `getcwd()` on this platform
  (Windows hands back backslashes regardless of how `:cd` was spelled);
  `nav/tree_traverse.lua`'s filesystem-root guard (walks to the real OS root
  via `fnamemodify(...,":h")`'s own fixed point, not a guessed drive-letter
  string) and its `cwd_mode.notify_manual_root` cross-feature notification.
- **keymap-bound features with no exported entry point**, driven through a
  real `filetree.setup()` plus a real `FileType`-fired tree buffer (the same
  mechanism `units.lua`'s own keymap-override tests use): `nav/reveal_alt.lua`
  (`B`, incl. the alternate-buffer-vanished guard), `ui/tree_reset.lua` (`<Esc>`
  fanning out to preview/filter/watcher_quarantine, real state checked before
  and after), `ui/window_style.lua` (statusline blanking + highlight
  isolation, incl. the WinEnter re-assert and an adapter-declared
  `filetypes`/`hl_groups` table replacing the default superset), `ui/cursor_hide.lua`
  (real `lib.nvim.ui.winhighlight` merge-in/strip-out on enter/leave),
  `ui/window_size_cycler.lua` (real window-width changes via
  `nvim_win_set_width`, incl. `2w` jumping straight to preset #2 instead of
  looping two steps, and an out-of-range count clamped to the last preset).
- **exported functions, called directly**: `nav/buffer_cycle.lua` (`<C-n>`/`<C-p>`
  cycling a REAL adjacent editor window while focus stays in the tree),
  `search/filter.lua` (extmark dimming, the native-backend-selected-but-not-installed
  fallback path this campaign's own regression note describes, and `enter()`
  via a stubbed `ui.kit.live_input`), `search/live_search.lua` (match="name"
  vs. match="path", and `commit_to_filter` handing the query to the real
  `filter` feature), `ui/size_info.lua` (real file sizes via `uv.fs_stat`,
  async directory sizes via a stubbed `vim.system` exercising the real
  POSIX/Windows command branch and its output parsing — the same seam this
  campaign already uses for `git_status.lua`), `ui/preview.lua` (float-mode
  text/hex/directory rendering in a real floating window, buffer-mode
  showing/restoring the adjacent editor window's buffer, and the image/pdf
  dispatch guard with `backend = false`).
- **libuv, for real, no stub**: `infra/file_watcher.lua` — a real
  `vim.uv.new_fs_event()` watching a real temp directory, a real file written
  into it, the debounced `adapter.refresh()` actually firing, and re-`setup()`
  not doubling its own `DirChanged` autocmd.

One genuine bug found and fixed directly, in test infrastructure rather than
shipped code: the `filetree.health` regression test above (pinned in round
26) simulates `lib.nvim.bindings.usercmd.composer` being unavailable and
calls `health.check()`, which itself does `pcall(require, "filetree")`. If
nothing in the process had required the bare `filetree` module before that
point, this was the first attempt — and `filetree.commands` requires
`composer` unconditionally (no pcall; see its own file header), so loading
`filetree` for the first time while composer is sabotaged throws for real.
`health.check()`'s own pcall swallows that fine, but Lua's module loader then
permanently caches `filetree` (and `filetree.commands`) as failed, so every
LATER `require("filetree")` in the same process fails with "loop or previous
error loading module" even after composer is restored right after — exactly
what broke this round's own `reveal_alt`/`window_style`/etc. sections the
first time *they* called the real `require("filetree")`. Fixed by clearing
those two cache entries once the health test finishes restoring its own
state, right where composer itself is restored.

Two more bugs, also in this test file rather than the plugin: `nav.reveal_alt`'s
test used `:edit` to bring a real alternate-file buffer into the SAME window
an about-to-be-current empty scratch tree buffer already occupied — Vim's own
`:edit` recycles the CURRENT buffer's number when it is empty/unnamed/unmodified,
which silently wiped the tree buffer's just-bound keymaps; fixed by editing
the other file *before* the tree buffer becomes current, and by switching a
second stand-in buffer in via `bufadd()` + `:buffer` (existing buffer
numbers, so no new-buffer-reuse) rather than a second `:edit`. `ui.window_size_cycler`'s
test resized a window that was the ONLY window in its tabpage — with no
sibling column to redistribute space from or to, `nvim_win_set_width` on it
is a no-op — fixed by adding a real sibling split first.

## refs/

Fixture-based regression tests that need real, on-disk multi-file projects —
too heavy for the unit-style checks above, which run against in-memory stubs.
Self-contained: fixtures plus a runnable `run.lua`.

Verifies the reference engine ([`lua/filetree/refs/`](../lua/filetree/refs/))
and the features that drive it: cross-file references — markdown links,
`require()`/`import` statements — must follow a file when it is renamed or
moved, and must NOT follow a similar-but-different name.

Run it from the repo root:

```
nvim --clean --headless -u NONE -l TESTS/refs/run.lua
```

For each language it copies `fixtures/<lang>/` to a scratch temp dir, renames
the "hub" module through the real feature (`smart_rename.rename_current()`
with a stubbed adapter and a stubbed `kit.input` — no tree plugin, no LSP
server, no floating window), and asserts every referencing file was rewritten
— plus a negative control that must stay untouched. It also covers the
directory-rename submodule cascade, the live-buffer patch (references in an
open buffer are patched in memory, not only on disk), the `M` move feature,
and `refs undo`.

The engine runs in `auto` mode there: the chooser is UI, covered by
`TESTS/units.lua`; this suite is about what lands on disk.

Currently covers Lua, Python, TS/JS (incl. `.tsx`/dynamic `import()`) and
Markdown (inline links, HTML `href=`, reference definitions).

To add another language: drop a `fixtures/<lang>/` tree with a project marker
file (anything in `project_root`'s marker list works — `.luarc.json`,
`pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, ...) and add a
`LANGS` entry in `run.lua` pointing at the hub file and the files that
reference it. Note: a language needs a provider in
[`lua/filetree/refs/providers/`](../lua/filetree/refs/providers/) before a
fixture for it will do anything.
