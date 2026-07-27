# CWD Modes — status

Root policy for filetree.nvim: a mode that decides where the cwd and the tree
root belong, instead of re-resolving it from the focused buffer on every switch.

User-facing docs: `:help filetree-cwd-mode`.
Feature: [`features/nav/cwd_mode`](../../lua/filetree/features/nav/cwd_mode/init.lua).

## The idea in one paragraph

`cwd_sync` is stateless — every `BufEnter` re-derives a root from the file. A
*mode* is by definition state ("keep the cwd here regardless of which buffer is
focused"), so it lives in its own feature. `cwd_mode` holds the state and
answers `decide(file)`; `cwd_sync` stays the executor and asks before it
changes anything. In `follow` mode `decide()` returns `nil`, which is the
deliberate "no policy" answer — the feature is then completely inert.

| Mode | Behaviour | Badge |
|---|---|---|
| `follow` | No policy; cwd_sync's own resolution applies unchanged | *(none)* |
| `project` | Holds the project root while the focused file is inside it | `PROJECT` |
| `lock` | Pins the cwd to one directory; enforced against foreign `:cd` | `LOCK` |
| `manual` | Nothing automatic; explicit action only | `MANUAL` |

---

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

- [x] **Feature `nav/cwd_mode`** — state machine, `decide()`, all four modes,
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
- [x] **Tests** — `test/cwd_mode.lua`, 64 checks. The suites accept
      `$FILETREE_LIB_NVIM` to run against a lib.nvim worktree before it is merged.

---

## Open

### 1. Persistence
- [ ] `persist` via `lib.nvim.store.project`: mode + pin survive a restart, keyed
      per project. The lib side already exists and is unused here.

### 2. More modes
- [ ] **`nearest`** — root at the nearest package boundary (`package.json`,
      `Cargo.toml`, `pyproject.toml`) instead of the VCS root. In a monorepo
      `.git` is too coarse. Mostly a `project.markers` preset plus a label.
- [ ] **`tree_leads`** — direction reversal: whatever you root the tree at with
      `+` becomes the cwd, rather than the buffer deciding.

### 3. Collapse the three root resolvers
`project_root`, `cwd_sync.root_markers` and `cwd_mode.project.markers` each walk
for a root with their own marker set. `util.root` now puts one door in front of
them, but they can still drift apart.

- [ ] Make cwd_mode the single resolver; leave the others as the fallback used
      only when cwd_mode is disabled.

### 4. Smaller follow-ups
- [ ] Move `breadcrumbs`' hand-rolled winbar/float handling onto
      `lib.nvim.ui.statusline` — the second consumer was the argument for
      building that module.
- [ ] `cwd_sync` is default-off, so `project`/`lock` only affect buffer switches
      once it is enabled. Documented, but still a stumbling block — consider
      whether an active mode should imply it.
- [ ] Pre-existing, unrelated: 7 failing `trash.undo` checks in `test/units.lua`
      (Windows Recycle Bin, environment-dependent).
