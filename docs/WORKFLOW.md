# Workflow — getting real use out of filetree.nvim day to day

Every feature here is documented on its own elsewhere
(`docs/FEATURES/CORE.md`, `BACKENDS.md`, `CWD_MODES.md`, `NAVIGATION.md`,
`docs/BINDINGS/KEYMAPS.md`). This is the different question: once several
features exist across five backends and a whole cwd-policy stack, *how do
they actually combine* in daily use, and where do they collide.

## Pick the backend first, then read its caveat — `opts.adapter`

`opts.adapter = "auto"` (the default) tries `neotree → nvimtree → netrw →
oil → mini_files`, first `is_available()` wins — fine for a single-tree
setup, but pin it explicitly (`opts.adapter = "neotree"`, etc.) the moment
two tree plugins are installed side by side, or "auto" silently always
picks neo-tree over nvim-tree regardless of which one you actually meant to
configure that session. See [BACKENDS.md](FEATURES/BACKENDS.md) for the
full per-adapter table; the two traps worth internalizing before touching
`cwd_sync`:

- **neo-tree**: already follows the buffer natively
  (`bind_to_cwd`/`filesystem.follow_current_file`). Leave `cwd_sync.reveal
  = false` here — `true` races neo-tree's own reveal of the file `<CR>`
  just opened.
- **nvim-tree**: `update_focused_file.update_root.enable` is *not* a
  drop-in equivalent of neo-tree's `bind_to_cwd` — it drives the cwd
  itself and, unlike neo-tree, falls back to the file's own parent
  directory (not a project root) when nothing else matches. Leave it
  `false` if `cwd_sync.root_markers` should be the thing that wins.
- **netrw / oil.nvim / mini.files**: no native cwd-follow at all, so
  `cwd_sync.reveal = true` (the default) is the only thing that reveals a
  newly-focused file's project — turning it off here just means files stop
  getting revealed, with nothing native to pick up the slack.

## `cwd_mode` vs `cwd_sync` — a policy in front of an executor, not two overlapping features

`cwd_sync` is stateless: every `BufEnter` re-derives a root from whatever
file is focused. `cwd_mode` is the opt-in state layer in front of it — pick
a mode, and `cwd_sync` asks `cwd_mode.decide()` before moving anything
instead of always re-deriving. The trap: **`project`/`nearest` mode do
nothing without `cwd_sync` actually enabled.** Both only seed the *initial*
pin at `setup()`/`:Filetree cwd mode project` time; the mechanism that
would keep following the file across project boundaries is `cwd_sync`'s own
`BufEnter` hook calling `decide()` again, and `cwd_sync` defaults to
**disabled**. Symptom: the badge shows `PROJECT`, the first file you opened
after switching modes is in the right place, and then every subsequent
buffer switch silently does nothing — indistinguishable from `lock` until
you notice files elsewhere stop moving the root. `set_mode()` warns once
when this happens; if you see that warning, the fix is `opts.features.
cwd_sync.enabled = true`, not touching `cwd_mode` at all. `lock` and
`tree_leads` don't have this dependency — `dir_guard` and
`tree_traverse`'s manual-reroot reporting drive those directly, so they
work with `cwd_sync` off.

A concrete daily sequence for a monorepo: `L` (cycle) to `nearest` so the
cwd tracks the package boundary (`package.json`/`Cargo.toml`/`go.mod`)
instead of the repo root that plain `project` mode would use — then `gp`
on a specific vendored subtree to drop into `lock` when you need to pin
somewhere `nearest`'s own walk wouldn't stop, e.g. mid-refactor inside
`node_modules/some-pkg` itself. `:Filetree cwd status` at any point shows
the resolved mode, scope and root without needing the statusline badge
visible.

## `+`/`-` under a lock: the pin moves, it doesn't fight you

`tree_traverse`'s `+` (root here) and `-` (up to parent) look like they'd
conflict with a `lock` or `tree_leads` mode — re-root manually while
something else is pinning the cwd, and naively the guard would just revert
it back a tick later. It doesn't: a manual re-root is reported to
`cwd_mode.notify_manual_root()`, and `lock.follow_manual_root` (on by
default) moves the pin to match instead of reverting the tree. Net effect:
`+`/`-` always "just work" as an explicit override regardless of which mode
is active — the only thing to know is that under `lock` this *redefines*
where the lock sits, so a `+` two directories too deep during a distracted
moment quietly relocates the pin, not just the tree view. `:Filetree cwd
status` is the fast way to confirm the pin actually landed where you meant
after a `+` under lock, before relying on it for the rest of a session.

## Every path mutation goes through the reference engine — plan for the chooser

Smart rename, batch rename, `M` (move), cut+paste and trash all hand their
scan/ask/rewrite work to `filetree.refs`. In daily use that changes two things
about how a rename feels.

**The scan starts on the keypress, not on the confirmation** — while the file
is still at its old path, so it overlaps with you typing the new name and
cannot miss a reference because the file moved out from under it. The rename
runs strictly after the scan finishes. That is why a rename in a large tree
sometimes pauses briefly *after* you hit enter: the work already happened, and
you are waiting on the tail of it.

**You get one chooser per operation, across every language** — not one per
file and not one per provider. *Update all* / *Select…* / *Show diff* /
*Leave as-is*. Reach for *Show diff* the first few times in a new project;
after that *Update all* is the honest default, because every rewrite is
content-verified at the byte range the scan recorded and a line that changed
in the meantime is skipped rather than corrupted. `:Filetree refs undo`
reverts the last batch.

**`ts_js` is off by default and that is not an oversight.** `tsserver`
implements `willRenameFiles` and does the job better while it is running; the
textual provider exists for projects without it. Turn it on when you are
working in a TS tree with no language server attached — not as a general
"more coverage is better" setting.

**Deleting is the mirror image, and deliberately asymmetric.** Trash offers to
blank now-dangling markdown links to `REF!` so the break is visible; code
references are left alone, because a `require("REF!")` is worse than an
obviously stale one.

The markdown provider runs for *every* move regardless of the moved file's
type — a markdown file can link to anything — so renaming `foo.lua` fixes the
docs that point at it, not only the modules that require it.

## `M` instead of cut, navigate, paste

Moving used to be three steps in two places. `M` is one prompt: move into a
directory, or move-and-rename in a single step for a single node. Cut+paste
still exists and is still right when the target is somewhere you want to
*navigate* to and look at first — but for a target you can name, the prompt is
the shorter path, and it starts its reference scan while you type.

Paste prompts to resolve a name conflict rather than silently overwriting or
silently skipping, and batch trash/paste show a progress indicator, so a large
operation is distinguishable from a hung one.

## Marks are a set — treat them like one

`m` in Visual mode marks every node in the selection and `[m` unmarks; those
are the only Visual-mode keymaps filetree binds, and they exist because a line
range over a rendered tree is exactly a set of nodes. Marking a run of twelve
files is a `V` motion, not twelve keypresses.

Navigation over marks follows the tree **as rendered**, not the alphabetical
order `get_marked()` returns: `]M`/`[M` cycle with wrap, `Ngm` goes to the Nth
mark, and an out-of-range count clamps to the last one the way `G` does. A
mark inside a collapsed directory has no line to jump to at all — if `]M`
seems to skip one, expand first rather than assuming the mark was lost.

## Dry-run the two bulk operations before letting them run

`:Filetree copymove dry-run` and `:Filetree renamebatch dry-run` toggle
`dry_run` at runtime and log the plan instead of executing it. These are the
destructive *bulk* operations, so this is the one worth using habitually on an
unfamiliar tree — trash and safety already had a runtime toggle; these two used
to be a config key, which meant previewing required editing the config and
reloading.

The command is `renamebatch`, not `rename`: `rename` is already the leaf
command that opens the batch-rename buffer.

## `gp` is shared between `cwd_mode` and the PDF bridge — know which one is live

`cwd_mode.lock_here` and `pdf_open.open_default` both default to the same
key, `gp` (tree buffer). This isn't a bug — `pdf_open` ships **disabled by
default** (`opts.features.pdf_open.enabled = false`), so out of the box
`gp` unambiguously means "lock cwd here". The trap only appears once you
turn `pdf_open` on for a PDF-heavy workflow: `attach.lua` binds both
against the same lhs, and whichever feature's `setup()` runs later wins the
mapping silently — no error, no warning, just one of the two features
losing its key. If you're enabling `pdf_open`, remap one of the two
explicitly (`keymap_lock_here` on `cwd_mode`, or `keymap_open` on
`pdf_open`) rather than relying on load order to sort it out for you.

`pdf_open.default_mode = "picker"` is worth knowing before you decide which of
the two to keep: it asks which backend to open with instead of committing to
one, the same way gopath.nvim's and markdown.nvim's pdfport integrations
already do. The prompt always includes "system application", so it works
without pdfport.nvim installed rather than showing an empty list.

## Reading Complexity → Hierarchy is a general habit; here it's Analysis panels → Backends table

There's no cross-repo Analysis tab in filetree.nvim, but the same "don't
guess, check the per-backend table" habit applies directly to `cwd_sync` /
adapter combinations: before assuming a re-root problem is a filetree bug,
check whether the adapter in play has its own native cwd-follow fighting
it (see the per-adapter list above). Most "cwd_sync doesn't work" reports
are actually "cwd_sync and the adapter's own native follow are both
enabled and disagreeing" — `:checkhealth filetree` surfaces the adapter in
use and whether `cwd_sync`/`cwd_mode` are active, which is the fastest way
to rule that out before digging into `root_markers` or `skip_dirs`.

## Windows/WSL: `handle_guard` and `watcher_quarantine` solve different halves of the same bug

Both exist because neo-tree's own directory watchers (`use_libuv_file_
watcher = true`) keep an OS handle open per expanded directory and never
close it, so renaming/deleting a watched directory can intermittently fail
with `EPERM`/`ERROR_SHARING_VIOLATION`. They are not alternatives:

- **`handle_guard`** (opt-in) fixes it at the source — releases the libuv
  handle before the fileop runs, wired automatically into
  `move`/`rename`/`trash` once enabled. `:Filetree handles` lists tracked
  handles and flags any pointing at a path that no longer exists (the leak
  signature) — worth a glance if renames feel flaky before assuming it's
  something else.
- **`watcher_quarantine`** (opt-in) hides the symptom instead — suspends
  watching for a window and suppresses the resulting error notification.

Both can run together (`watcher_quarantine` complements rather than
replaces `handle_guard`), but if EPERM errors persist with only
`watcher_quarantine` on, that's expected — it never touches the handle
itself, only the noise. Reach for `handle_guard` first if the goal is
actually fixing renames rather than just quieting the error.

## `project.sticky` is what keeps a scratch buffer from dragging a locked session away

A `/tmp` file, an unsaved scratch buffer, or anything with no root marker
of its own is exactly the case plain `root_markers` walking can't express
cleanly — it has no root, so a naive walk falls through to *something*,
often the wrong project. `project.sticky` (on `cwd_mode`'s `project`/
`nearest` modes) means a rootless file simply doesn't move the pin at all
rather than falling back to whatever the walk finds first. Worth knowing
before debugging "why didn't the cwd follow that scratch file I opened" —
it's not a bug, `sticky` is doing exactly what it's for.

## Templates: filename first is deliberate, not an implementation detail

`A` (create-from-template) asks for the destination filename *before*
showing the template picker, specifically so the picker can filter to
extension-matching templates (`foo.lua` → only `.lua` templates) — typing
the name last would mean picking a template blind, with no guarantee it
matches what you're about to name the file. If the filtered list looks
empty or wrong, check the extension you typed rather than assuming the
template is missing — a typo'd extension (`.lua` vs `.lu`) silently falls
back to the *full* unfiltered list rather than erroring, which can look
like "the filter isn't working" when it's actually "nothing matched, so
you're seeing everything".
