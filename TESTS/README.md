# TESTS/

Everything CI runs, plus the manual pass it cannot.

| | |
| --- | --- |
| [`smoke.lua`](smoke.lua) | integration: every feature module loads, opt-out defaults resolve, registry resolver + binding catalog work |
| [`units.lua`](units.lua) | unit: util layer, neo-tree adapter helpers, the reference engine's apply/undo layer and the chooser |
| [`menu.lua`](menu.lua) | unit: `integrations/menu.lua`, against a stubbed `filetree` module |
| [`cwd_mode.lua`](cwd_mode.lua) | unit: the cwd/root policy feature, against a stub adapter and a temp tree |
| [`sidebar_guard.lua`](sidebar_guard.lua) | unit: `&winfixbuf` pinning of the tree window, neo-tree event (un)subscription, no-op on a non-neotree adapter |
| [`gaps.lua`](gaps.lua) | unit: fs-heavy and lifecycle modules `units.lua`/`smoke.lua` had not reached yet — see "gaps.lua" below |
| [`adapter_lines.lua`](adapter_lines.lua) | integration: the adapter's line→node mapping, against a **real neo-tree and a real nvim-tree** — the only suite that needs a tree plugin |
| [`refs/`](refs/) | fixture-based: real on-disk multi-file projects, described below |
| [`MANUAL.md`](MANUAL.md) | the manual checklist for what a headless run cannot reach — real neo-tree, real floats, real clipboard |

All of them are headless and exit 0 on a pass, and CI gates on every one.
All but `adapter_lines.lua` run against a stub adapter and need no tree
plugin; that one needs neo-tree (plus nui/plenary/devicons) and prints a skip
instead of failing when they are absent, because what it tests — the mapping
between the lines a backend DREW and the nodes it reports for them — is
precisely what a stub cannot have. `MANUAL.md` describes each in more detail
and carries the lib.nvim resolution notes.

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
- Confirmed genuinely untested beyond a load-time `require()` (checked by
  grepping every existing suite for each name, not assumed): `features/infra/file_watcher.lua`,
  `features/nav/{auto_reveal,buffer_cycle,reveal_alt,tree_traverse}.lua`,
  `features/paths/lua_require_copy.lua`, `features/search/{filter,live_search}.lua`,
  `features/ui/{window_style,window_size_cycler,cursor_hide,tree_reset,size_info,preview}.lua`.
  Not reached this round; a later round should pick these up next.
  (`features/infra/handle_guard`, `features/infra/tree_integrity`,
  `features/nav/{auto_resize,no_name_guard}` looked similar at a glance but
  already have real suites in `units.lua` — verified before writing this
  list, not assumed either way.)

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
