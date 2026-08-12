## Done

### lib.nvim (merged to `main`, commit `968d65e` + merge `5d1750b`)

- [x] **`fs.chdir`** — explicit scope (`:cd`/`:tcd`/`:lcd`) instead of
      `vim.fn.chdir()`'s implicit one; normkey canonicalization, trailing slash
      stripped so the result compares equal to `getcwd()`, `is_dir` check before
      the command runs, `false, err` instead of throwing.
- [x] **`fs.dir_guard`** — holds a directory via `DirChanged`, ignores its own
      changes (no re-assert loop), watches exactly the scope it holds.
      `bypass()`, `update()`, `on_violation()`, `release()`.
- [x] **`fs.find_root`: `skip_dirs` + `max_depth`** — a file under
      `node_modules/pkg/lib` resolves to the project above the vendor directory,
      not to the vendored package; the walk can be depth-bounded. Both work on
      the plain and the chain-caching path, and both are backward compatible.
- [x] **`ui.statusline`** — per-window badge; resolves its drawing strategy at
      attach time and falls back to a one-line float when `laststatus = 3`
      removes per-window statuslines.
- [x] Specs `docs/TESTS/cwd_spec.lua`, `docs/TESTS/statusline_spec.lua`; wiring
      in `docs/modules.md`. Full lib suite: 17/17.

### filetree.nvim (`main`, commits `60c86aa`, `9b90b38`)

- [x] **Feature `nav/cwd_mode`** — state machine, `decide()`, every mode,
      `root()` / `pinned()` / `component()` for other code.
- [x] **`project.sticky`** — a file with no root of its own (a scratch note,
      something in `/tmp`) does not drag the session out of its project. This is
      the part plain `root_markers` cannot express.
- [x] **cwd_sync hooks** — asks the policy; cwd target and tree root are now
      separately permitted (`reveal_outside`), because a lock needs them to
      disagree: a file outside the pinned root must not re-root the tree.
- [x] **`tree_traverse` reports manual re-roots** — otherwise a lock fights its
      own user: `+` re-roots the tree, the guard reverts the cwd, and the two
      end up pointing at different directories. The pin moves instead
      (`lock.follow_manual_root`).
- [x] **Lock enforcement** via `dir_guard` — a `:cd` from a picker, a session
      restore or another plugin is reverted (`lock.enforce`).
- [x] **Indicator** bottom-left in the tree window — `auto` (statusline, float
      under `laststatus=3`), labels/highlights configurable, pinned path elided
      to the tree width, `component()` for hand-built statuslines.
- [x] **Commands** `:Filetree cwd mode|scope|lock|here|unlock|toggle|status` with
      enum and `DIR` completion via composer; keymaps `L` (cycle), `gp` (lock here).
- [x] **Scope axis** (`global`/`tab`/`win`) end to end: cwd_sync's per-buffer
      change goes through `lib.nvim.fs.chdir` with the mode's scope instead of
      `vim.fn.chdir`'s implicit one, `set_scope()` re-anchors a held root, and
      `:Filetree cwd scope` changes it at runtime. Leaving `tab`/`win` cannot
      undo a `:tcd`/`:lcd` set in some *other* tab or window — Vim has no "clear
      everywhere" — which is documented rather than papered over.
- [x] **Project-scoped consumers** — `find_files`, `grep_in_dir`, `git_status`
      and `breadcrumbs` resolve through the new
      [`util.root`](../../lua/filetree/util/root.lua) (held root → project_root →
      cwd) instead of asking the current buffer. Before this, opening a file from
      another project under a lock silently moved all four there.
- [x] **Docs** — `:help filetree-cwd-mode`, `docs/BINDINGS/KEYMAPS.md`,
      `docs/BINDINGS/USERCOMMANDS.md`, defaults + `@types`.
- [x] **Persistence** (`persist`, off by default) — mode, scope and a lock's pin
      per project via `lib.nvim.store.project`, plus `:Filetree cwd forget`.
      Keyed by the project of the directory Neovim *started* in: keying by the
      current cwd would make the key move along with the state being saved. Only
      explicit actions write — project mode re-pins on every buffer switch, and
      persisting those would be a disk write per `BufEnter` for a value that is
      re-derived at startup anyway. A stored lock whose directory is gone is
      declined rather than restored. Uncovered a real lib defect on the way:
      `cache.disk` created only the cache root, so any namespace containing a
      slash — the form `store.project`'s own docs use — silently failed to write.
- [x] **`nearest` and `tree_leads`** — `nearest` walks package markers instead
      of VCS ones (a monorepo's `.git` is too coarse), sharing `skip_dirs` and
      `sticky` with `project` so there is one place to configure the filesystem
      side; `.git` stays as its last-resort marker so a file outside any package
      lands on the repository rather than walking to `/`. `tree_leads` reverses
      the direction: buffer switches move nothing, `+`/`-` moves the cwd. Mode
      names now live in one `MODES` table that also validates a persisted value,
      so a mode can only be added in one place.
- [x] **One root walk** — `cwd_mode.resolve()` is now the plugin's only
      marker-based walk; `cwd_sync.root_markers` and the `project_root` feature
      are the fallback for a cwd_mode-less setup. The three used to disagree:
      cwd_sync anchored the cwd to the git root while find_files scoped itself
      to the nearest `package.json` under it, with nothing to say which was
      right. Asking for the package instead of the repository is what `nearest`
      mode is for — a choice, not an accident of which feature answered.
- [x] **External statusline consumption** — `cwd_mode.badge()` returns
      `{ text, hl, mode, root }` for a hand-rolled or heirline-style component;
      `component()` stays the plain-text one-liner for lualine. Both are
      independent of `indicator.enabled` — the whole point is to run with it
      `false` (no internal badge, no double display) while still reading the
      state. A `User FiletreeCwdModeChanged` autocmd plus a scheduled
      `redrawstatus` fire whenever the rendered text/highlight would actually
      change (diffed against the last announced value, so a window-lifecycle-
      only refresh from `WinEnter`/`TabEnter` does not spam it), for a
      statusline plugin that does not already redraw on its own.
- [x] **`cwd_sync` dependency warning** — `project`/`nearest` mode's whole
      promise (following the focused file as it moves between projects/
      packages) runs through cwd_sync's `BufEnter` hook calling `decide()`.
      cwd_sync defaults to disabled, and without it those two modes only seed
      the initial pin and then silently do nothing on the next buffer switch —
      indistinguishable from a plain lock until you notice files elsewhere no
      longer move the root. `set_mode()` now warns once, on the switch, when
      cwd_sync is not genuinely active. `lock` and `tree_leads` do not depend
      on it (dir_guard and tree_traverse's manual re-root drive those
      directly) and never warn. Caught a bug in the first version of this
      check while writing its test: `registry.require("cwd_sync")` only tests
      that the module *file* can be required — true the moment anything has
      loaded it, regardless of whether `filetree.setup()` actually enabled it
      — so it always returned truthy. Fixed to read `filetree.feature(name)`,
      the `_active_features` table populated only by a real `setup()` run.
- [x] **breadcrumbs migrated to `lib.nvim.ui.statusline`** — its hand-rolled
      float (position/buffer/lifecycle management, ~50 lines) is now a call to
      the shared primitive, which gained an `anchor = "top"|"bottom"` option
      for the move (default `"bottom"`, unchanged for cwd_mode's badge).
      Forces `mode = "float"` rather than `"auto"`: breadcrumbs must stay
      pinned to the tree window's TOP row regardless of `laststatus`, and
      `"auto"` would otherwise alternate between an always-last-row statusline
      and a top-anchored float depending on the user's setting. Its `winbar`
      mode (sets `&winbar` on the EDITOR windows, with per-segment
      highlighting) is a different mechanism entirely and stays untouched.
      lib tests: `statusline_spec.lua` +2 (anchor="top" placement, default
      unchanged). filetree tests: 4 new checks in `test/units.lua`.
- [x] **Tests** — `test/cwd_mode.lua`, 111 checks — including the real
      `filetree.setup()` positive case the fix above hinges on: cwd_sync
      genuinely enabled must not warn. The suites accept
      `$FILETREE_LIB_NVIM` to run against a lib.nvim worktree before it is merged.
- [x] **`indicator.style`** — the badge text is no longer locked to full words.
      `"text"` (default, unchanged) / `"short"` (first-letter abbreviations) /
      `"numeric"` (one digit per mode, 0–5 — the only style that shows
      anything for `follow`) / `"icon"` (a Nerd Font glyph, no text). Each
      style reads its own table (`labels`, `labels_short`, `labels_numeric`,
      `icons`), so overriding one mode in one style never touches another.
      `hl` (the color) stays shared across all four — switching `style` only
      changes the text. The filled, capsule-like badge look (background color
      instead of just colored text, as a host statusline's `mode()` segment
      usually has) is left to the consuming statusline: `badge()` already
      hands over `{ text, hl }`, and wrapping that in a bg-filled highlight
      group with a fading separator is the host's call, not this plugin's —
      see the wkdnvchad statusline config for a worked example.

---
