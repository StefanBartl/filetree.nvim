# File operations

Creating, editing, moving and opening nodes from the tree — the mutating
half of filetree.nvim, as opposed to [NAVIGATION](NAVIGATION.md)'s
read-only movement around it.

## Smart Create

`a` creates a file or directory under the cursor, template-aware — typing
a trailing `/` creates a directory, anything else a file, with parent
directories created as needed.

- **Module:** `lua/filetree/features/fileops/smart_create/`
- **Keymaps:** `a`

## Copy / Move

Stage one or more nodes with `c` (copy) or `x` (cut), then `p` to paste
them under the cursor's directory — the same stage-then-paste model as a
system file manager, works across multiple marked nodes at once.

If any staged item's name already exists at the paste target, a prompt
appears before anything is touched: **Overwrite** (replaces the existing
item — backed up first when `use_safety` is on), **Keep both** (pastes
alongside it as `name (2).ext`), **Skip** (leaves that item out of this
paste; a skipped cut stays staged so you can resolve it and paste again
instead of it silently vanishing), or **Cancel** (aborts the whole paste,
nothing is touched). No conflicts means no prompt — pasting into an empty
or non-colliding directory behaves exactly as before.

A multi-item paste shows a progress indicator (current item, N/M, final
summary) via `lib.nvim.progress` — see
[Progress indicators](../configuration.md#full-option-reference)'s
`progress_style` option (top-level `require("filetree").setup({...})`
config, not per-feature).

A cut+paste is a move, so it runs the [reference engine](#references)
too — the scan starts when you press `x`, and overlaps with you navigating
to the paste target. A copy never breaks a reference (the original stays
put), so copies are not scanned.

Staged nodes are marked in the tree with a ` C`/` X` overlay. That marker
is drawn on the node's own line, so it needs the adapter to resolve a line to
a node (see [Backends](BACKENDS.md#line-resolved-decorations)): it shows on
neo-tree and nvim-tree, and is absent on netrw, oil and mini.files. The
staging and the paste itself work on all five either way.

**Copying a symlink copies the link, not its target.** A staged symlink —
file or directory — pastes as a new symlink pointing at the same target,
instead of being silently dereferenced into an independent copy of whatever
it points at. This matters most for a symlinked *directory*: without it,
pasting one would deep-copy everything behind the link (potentially huge,
and unboundedly recursive through a symlink cycle, since a real directory
tree cannot have one but a naive walk following links does not know that).
An ordinary (non-link) directory or file still copies its actual content, as
always.

- **Module:** `lua/filetree/features/fileops/copy_move/`
- **Keymaps:** `c` (copy), `x` (cut), `p` (paste)
- **See also:** [Move](#move) (`M`) for the one-prompt variant

## Move

`M` moves the node under the cursor — or every marked node — to a
destination typed into one prompt, instead of the cut / navigate / paste
round trip. `<Tab>` completes directories; the destination can be relative
to the cwd, absolute, or `~`-prefixed.

What the destination means depends on what is moving:

- several nodes, or a destination that already **is** a directory → the
  items move *into* it under their own names;
- a single node and a destination that doesn't exist yet → that becomes
  the node's new full path, so `M` doubles as move-and-rename (typing
  `docs/Test.md` for a `Test.md` at the root does both at once).

A destination directory that doesn't exist is offered for creation rather
than silently created, and name collisions ask the same **Overwrite /
Keep both / Cancel** question a paste does.

References are handled by the [reference engine](#references) below: the
scan starts the moment you press `M`, so it runs while you are still
typing the destination.

- **Module:** `lua/filetree/features/fileops/move/`
- **Keymaps:** `M`
- **Commands:** `:Filetree move [destination]`

## Batch Rename

`<leader>rb` opens an edit-buffer listing every node in view; editing a
line and saving renames the corresponding file — a bulk rename express
lane for renaming several files at once without one prompt per file.

- **Module:** `lua/filetree/features/fileops/rename_batch/`
- **Keymaps:** `<leader>rb`

## Smart Rename

`r` renames the node under the cursor and updates every LSP reference to
it project-wide, the same guarantee an IDE's "rename symbol" gives you,
applied to a file/module rename instead of a variable.

Whatever the language server does *not* rewrite — markdown links always,
plus `require()`/`import` statements when no server handled the rename
(for Lua that is always, since lua_ls never implements
`workspace/willRenameFiles`) — is picked up by the
[reference engine](#references).

- **Module:** `lua/filetree/features/fileops/smart_rename/`
- **Keymaps:** `r`

## Create From Template

- **Tab:** true
- **Module:** `lua/filetree/features/fileops/create_from_template/`
- **Keymaps:** `A` (smart_create's `a` counterpart), `:Filetree template`

Press `A`, or run `:Filetree template`. Workflow, in order:

1. **Filename first.** You're prompted for the new file's name before
   anything else — the destination path is fully known from this point on.
2. **Filtered picker.** The template list narrows to templates whose own
   extension matches the filename you just typed (`foo.lua` → only `.lua`
   templates). No match, or no extension typed, falls back to the full
   list — a filter that would leave nothing to pick from is skipped
   rather than enforced.
3. **Pick a template.** Variables substitute against the real destination,
   then the file is created and opened.

**Built-in templates** ship with filetree.nvim itself, several per common
language so the extension filter in step 2 leaves a real choice: Lua
(`lua_module`/`lua_class`/`lua_spec`/`lua_types`), TypeScript/TSX/JS,
Python, Go, Rust, C#, C/C++, Zig, JSON, Markdown, YAML, TOML, shell/
PowerShell, HTML/CSS, WAT — shown in the picker with a `[builtin]` marker.

**Add your own** by dropping a file into the template directory (default
`stdpath("data")/filetree/templates/`) — its filename becomes the
template name — or call `M.add_template(name, content)`. A user template
with the **same name** as a built-in shadows it entirely, which is how you
customize a shipped default.

**Reorder** while the picker is open with an empty filter:
`<M-j>`/`<M-k>` move the highlighted template down/up, persisted
immediately to a `.order.json` sidecar in the template directory. A
never-reordered or newly-added template is appended alphabetically after
the ones with an explicit position.

**Variables:** `${filename}` (basename, no extension), `${ext}`,
`${date}`/`${year}`/`${month}`/`${day}`/`${time}`, `${author}`
(`config.author`, else `$USER`/`$USERNAME`), and `${module}` — for a
destination under a real `lua/` directory, the canonical Lua module path
(`lua/plugins/test.lua` → `plugins.test`) via
`lib.nvim.lua_ls.get_module_path`; otherwise a generic dotted path from
the project root for any language (`src/foo/Bar.cs` → `src.foo.Bar`).

```lua
local tpl = require("filetree").feature("create_from_template")
tpl.list()                   -- all templates, in display order
tpl.add_template("go_test.go", "package ${filename}\n")
tpl.move("go_test.go", -1)   -- same as pressing <M-k> on it
```

## Trash

Cross-platform trash with undo — `d` to trash, `U` to undo, `<leader>th`
for trash history. How far back that reaches is `features.trash.max_history`
(default 50, `0` = unlimited): a preference, not a limit protecting
anything, since the history is a small JSON file. Marking multiple nodes and
trashing them opens one batch confirmation instead of one prompt per
file, and force-closes any open buffers backed by the deleted paths so
they don't linger as edits-to-nowhere. Same progress indicator
as Copy / Move above, for both the "delete all at once" and "confirm
each individually" batch paths.

`features.trash.mode` is `"trash"` by default — Windows Recycle Bin,
macOS Finder/Trash, or `gio trash`/`trash-put` on Linux (XDG-trash
fallback when neither is installed), all via `lib.nvim.fs.trash`. Set it
to `"permanent"` to skip the OS trash and delete for good instead — no
shell, same libuv/Vim-builtin primitive the "Overwrite" paste resolution
uses. Opt-in on purpose: a permanent delete has no `U`/history entry to
fall back on, so the confirm dialog's wording changes to make that
explicit ("Permanently delete (cannot be undone)?") rather than sharing
the "Send to trash?" phrasing.

When something links to the file being deleted, the plain yes/no becomes a
chooser — **Delete + remove refs** (blanks the dangling links to `REF!`),
**Inspect first** (pick which ones), **Delete, keep refs**, **Cancel**.
Undoing such a delete with `U` restores the `REF!` markers along with the
file. See [References](#references). For a large batch, the reference
rewrite can still be in flight when `U` fires — undo does not wait for it.
`U` still restores the file immediately; if the rewrite finishes after that,
a warning names how many references it touched and points at
`:Filetree refs undo` to revert those separately.

`:Filetree trash dry-run` covers that reference rewrite too, not just the
delete: it reports what *would* be marked and writes nothing. It is the one
part of a delete that touches files the user did not select, so a dry-run
has even less business making it than the delete itself — and every line of
a dry-run, down to the closing summary, reports in the conditional, so
nothing in the output reads as though it had happened.

A dangling symlink (its target no longer exists) can still be trashed —
the existence check that gates `d` reads the dirent itself
(`filetree.util.conflict.exists`, `fs_lstat`-aware), not just
`filereadable`/`isdirectory`, both of which follow the link and see nothing
through a broken one.

- **Module:** `lua/filetree/features/fileops/trash/`
- **Keymaps:** `d`, `U`, `<leader>th`
- **Config:** `features.trash.mode` (`"trash"` | `"permanent"`, default `"trash"`)

## Dry run for copy/move and batch rename (2026-08-24)

`:Filetree copymove dry-run` and `:Filetree renamebatch dry-run` toggle
`dry_run` at runtime, logging the plan instead of executing it.

`trash` and `safety` already had such a toggle; copy/move and batch rename
had `dry_run` as a config key only, so previewing meant editing the config
and reloading. That asymmetry was the wrong way round — these two are the
destructive *bulk* operations you most want to see once before letting them
run. Closes the flag/option audit's entry.

The command is `renamebatch`, not `rename`: `rename` is already a leaf
command that opens the batch-rename buffer, and declaring a table under the
same key would simply be overwritten by it.

- **Module:** `features/fileops/copy_move/init.lua`,
  `features/fileops/rename_batch/init.lua` (`toggle_dry_run`)
- **Usercmds:** `:Filetree copymove dry-run`,
  `:Filetree renamebatch dry-run`

## References

Moving a file breaks everything that pointed at it. The reference engine
(`lua/filetree/refs/`) is the one place that knows how to fix that, and
**every** mutating feature above routes through it — smart rename, batch
rename, the `M` move, cut+paste, and trash.

### What happens

1. The scan starts the moment you press the key, while the file is still
   at its old path — so it overlaps with you typing a new name or
   navigating to a target, and can never miss a reference because the file
   moved out from under it.
2. The move/rename runs strictly after that scan finished.
3. Each found reference is re-expressed for the new location, preserving
   how it was written: an absolute link stays absolute, `./x` keeps its
   `./`, an aliased TypeScript import stays aliased, an extensionless
   specifier stays extensionless.
4. You get one chooser for the whole operation, across all languages:

```
7 reference(s) in 4 file(s) (5 markdown, 2 lua)
  ▸ Update all
  ▸ Select…       → picker (Telescope / fzf-lua / quickfix), Tab to multi-select
  ▸ Show diff     → read-only unified diff, then back to this chooser
  ▸ Leave as-is
```

Every rewrite is content-verified at the exact byte range the scan
recorded, so a line that changed in the meantime is skipped rather than
corrupted; a file that is open in a buffer is patched **in that buffer**
(and written back only if it had no unsaved changes). `:Filetree refs
undo` reverts the last batch of rewrites.

The undo is verified the same way: each entry keeps both the line's
pre-rewrite content and what the rewrite wrote, and restores only while
the line still holds the latter. A line edited since — by hand, or by a
later rewrite that touched the same line — is left alone and reported as
skipped, rather than silently replaced with a version from before the
edit. That matters most for the `U` path below, which can revert an apply
made long ago on files the user has been editing since.

Every path the engine carries is normalized to forward slashes the moment
the candidate list is built, so the file it reports is spelled the same way
whether ripgrep or the built-in walk found it — and the file list in the
chooser and its notifications reads `lua/proj/a.lua` on every OS, never
`lua\proj\a.lua`.

When the change spans more than eight files, the rewrites (and an undo of
them) run in chunks across event-loop ticks with the same optional
`lib.nvim.progress` indicator the paste and trash flows use
(`updating references… N/total`), so a project-wide rename never freezes
the editor. A smaller change is applied synchronously, as before.

Deleting is the mirror image: trash offers to blank the now-dangling
markdown links to `REF!` before the file goes, so the break is visible
instead of silent. Code references are deliberately left alone there —
a `require("REF!")` is worse than an obviously stale one.

Undoing that delete undoes both halves. A delete is two mutations — the
file goes to the trash, and the references pointing at it become `REF!` —
so restoring the file with `U` (or `:Filetree trash undo`) also reverts
exactly that rewrite, rather than handing back a file every link still
calls broken. The trash history entry keeps the undo token of its own
rewrite, so this stays correct even when unrelated renames pushed newer
reference updates on top in the meantime, and when the cascade trashed
orphaned assets right after the file. The refs go back only once the file
itself is actually back; a restore that failed leaves the markers alone.
References that can no longer be restored — already reverted by hand with
`:Filetree refs undo`, or dropped off the bottom of the `refs.undo_depth`
stack — are reported instead of silently skipped, since those stay broken.

### Cascade-delete-assets

The opposite direction of the same delete: `refs.outgoing_assets` looks at
what the file *about to be deleted* itself links out to (via
`docs/ROADMAP/IDEAS/Cascade_Delete_Assets.md`) and offers to delete those
targets too, once nothing else still references them — a markdown note
linking to `assets/shot.png` deletes the screenshot along with the note
instead of leaving it orphaned. Three checks gate every candidate: it must
resolve under a configured assets root (`{"assets"}` by default, checked
relative to the linking file's own directory first, then the project root),
its extension must be on an allowlist (image/video shapes; never a
denylist — an unrecognized extension is never offered by accident), and no
OTHER surviving file may still reference it.

**Off by default** (`refs.outgoing_assets.enabled = false`), independently
of the main `on_delete` switch above — a user may want incoming REF!
markers without cascade-delete-assets, or vice versa. It is opt-in until
this has real mileage: unlike the incoming-refs direction, which only ever
*marks* a link, this one *deletes files*, and doing that automatically by
default the first time someone upgrades is the wrong default to risk.
Wired into `d`/trash's confirm dialog regardless of the flag, but a no-op
while off — turning it on needs nothing beyond the config below.

### Languages

| Provider | Covers | Default |
|---|---|---|
| `markdown` | `[text](./path)`, `![img](…)`, reference definitions `[id]: …`, HTML `src=`/`href=`, optionally `[[wiki]]` links | on |
| `lua` | `require("a.b")` / `require "a.b"`, including the submodule cascade when a directory moves | on |
| `python` | `import a.b`, `from a.b import x`, and relative `from .x import y` | on |
| `ts_js` | `import`/`export … from`, dynamic `import()`, CJS `require()`, relative specifiers plus `tsconfig`/`jsconfig` `paths` aliases | **off** |
| `plaintext` | a bare filesystem path written as running text — `see ../Test/Tester.md for the format` in prose, or the same in a code comment — with no link/require/import syntax around it | **off** (experimental) |

`ts_js` is opt-in: `tsserver` implements `willRenameFiles` and does a
better job when it is running, so the textual provider is there for
projects without it.

`plaintext` is opt-in **and experimental** (`refs.experimental.plaintext`,
so it is clear it is new and its config shape may still move). A bare token
has a wider false-positive surface than a bracketed link, so the resolver is
the only thing between "looks like a path" and "gets rewritten": a token is
touched **only when it resolves to exactly the file that moved**, the same
test the markdown provider applies. It scans prose/text files in full
(`.md`, `.txt`, `.rst`, `.org`, `.adoc`, …) and — unless
`experimental.plaintext.comments = false` — the comment lines of source
files (`.lua`, `.py`, `.js`, `.ts`, …); a path in a string literal on a real
code line is left to that language's own provider. It never touches a token
already inside link/`src=`/`href=`/`[id]:`/`[[wiki]]` syntax (the markdown
provider owns those) or an external URL. gopath.nvim resolves the same
kind of bare path *under the cursor* for navigation — this is the write
side of the same idea, applied after a move.

A markdown file can link to *any* file type, so the markdown provider
runs for every move — renaming `foo.lua` fixes the docs that link to it,
not just the modules that require it.

References are matched by **resolving** each target against the file it
appears in and comparing absolute paths — never by comparing text. That
is what makes `../Test.md` from a subdirectory a match while a same-named
file in a different directory is not.

### Configuration

One central `refs` block, not per feature:

```lua
require("filetree").setup({
  refs = {
    enabled   = true,
    providers = { markdown = true, lua = true, python = true, ts_js = false },
    on_rename = "ask",    -- "ask" | "auto" | "off"
    on_move   = "ask",
    on_delete = "ask",
    copy      = false,    -- a copy leaves the original in place: nothing breaks
    picker    = "auto",   -- "auto" | "telescope" | "fzf-lua" | "quickfix"
    prefer_lsp = true,    -- don't re-do what a language server already rewrote
    wiki_links = false,   -- also scan [[wiki]]-style links
    experimental = {
      -- Rewrite bare paths written as running text / code comments, not just
      -- paths inside link/require/import syntax. Opt-in; shape may change.
      plaintext = {
        enabled  = false,
        comments = true,   -- also scan comment lines in source files
        -- extensions         = { … }  -- override the prose/text file list
        -- comment_extensions = { … }  -- override the source-file list
      },
    },
    -- Cascade-delete-assets: opt-in, independent of `on_delete` above.
    outgoing_assets = {
      enabled    = false,
      on_delete  = "ask",  -- "ask" | "auto" | "off"
      -- roots      = { "assets" }  -- override the default asset-folder name(s)
      -- extensions = { "png", … }  -- override the default extension allowlist
    },
    scan = {
      root              = "project",  -- "project" (nearest root) | "cwd"
      respect_gitignore = true,
      max_files         = 5000,       -- cap for the ripgrep-free fallback walk
      timeout_ms        = 3000,
    },
    undo = true,
  },
})
```

The scan uses **ripgrep** as a pre-filter when it is installed (only files
that mention the name at all are read). Without ripgrep it falls back to a
capped libuv walk, which is slower but still correct. Over ~20 extension-
matching files that walk reads them in chunks across event-loop ticks with a
`[filetree.refs]` progress indicator instead of freezing the editor for the
whole scan.

The per-feature options this replaces — `check_markdown_refs`,
`refs_picker_prefer`, `smart_rename.update_references` — are migrated
automatically, with a one-time notice telling you what moved where.

### Adding a language

Providers are pluggable; a third-party one registers the same way the
built-ins do:

```lua
require("filetree.refs").register({
  name = "rust",
  plan = function(old_path, ctx)
    -- return nil when this provider has nothing to do for old_path
    return {
      needles    = { "…" },   -- fixed strings for the ripgrep pre-filter
      extensions = { "rs" },  -- which files may hold such a reference
      extract    = function(file, lineno, text) return { --[[ FiletreeRef… ]] } end,
      retarget   = function(ref, new_path) return "…" end,
    }
  end,
})
```

See `lua/filetree/@types/refs.lua` for the full contract and
`lua/filetree/refs/providers/` for four worked examples.

- **Module:** `lua/filetree/refs/`
- **Commands:** `:Filetree refs undo`, `:Filetree refs status`

## Open Replace

Opens the node under the cursor into an existing editor window — never
into the tree's own — in two shapes that differ in what becomes of the
buffer already sitting there.

`O` **replaces**: `:edit` over the editor window. The previous buffer
stays in the buffer list, it just isn't on screen any more.

`<M-CR>` (and `<C-CR>`) **swaps**: the previous buffer is closed as well,
and the new file takes over the slot it held in the bufferline. Reach for
it when the buffer list is a working set rather than a history — opening
five files to find the one you wanted otherwise leaves four behind to
close by hand.

A swap refuses to run when the focused buffer has unsaved changes: it
says so and does nothing at all, rather than opening the file and quietly
leaving the old buffer behind (which would just be `O`). Write it first,
or use `O`.

**Keeping the slot** needs a buffer list that has slots. Neovim's own
order is the buffer numbers, and those only ever increase — a file opened
now can never sort ahead of one opened earlier, and no API moves it,
because there is nothing to move: the order isn't stored, it's derived.
Tabline plugins in the NvChad lineage keep `vim.t.bufs`, a per-tabpage
list they order themselves, and that one *can* be rewritten — so the new
buffer is put back at the index the replaced one held. Without such a
list the swap still swaps; the new file simply lands where its buffer
number puts it, which is last. Nothing errors, and there is nothing to
configure for it — the list is either there or it isn't.

Two keys for one action because which of them the terminal delivers
isn't ours to decide: many terminals send plain `<CR>` for Ctrl+Enter, in
which case `<C-CR>` never fires and the tree's own `<CR>` behaves as
always. Alt+Enter travels further, so it's the primary.

```lua
open_replace = {
  keymap          = "O",        -- replace; previous buffer stays listed
  keymap_swap     = "<M-CR>",   -- swap; previous buffer closed
  keymap_swap_alt = "<C-CR>",   -- same, where the terminal distinguishes it
  close_tree      = true,       -- close the tree after `keymap`
  swap_close_tree = false,      -- ... and after a swap
  keep_position   = true,       -- new buffer takes the replaced one's slot
},
```

- **Module:** `lua/filetree/features/fileops/open_replace/`
- **Keymaps:** `O`, `<M-CR>`, `<C-CR>`

## Open Variants

Open a node in a split (`sg`), vsplit (`sv`), tab (`st`), or add it to
the buffer list without switching focus (`gb`/`<S-CR>`) — every common
"open, but not by replacing my current window" shape in one feature.

On a **directory**, `<S-CR>` does something else entirely: it collapses the
node via `adapter.collapse_node()`, since the adapter's own `<CR>` only ever
expands (there's no toggle to undo it — see the note below). `gb` stays
file-only; only `<S-CR>` picks up the directory case.

- **Module:** `lua/filetree/features/fileops/open_variants/`
- **Keymaps:** `sg`, `sv`, `st`, `gb`/`<S-CR>`

### Collapsing a drilled-into directory (neo-tree)

neo-tree's `filesystem.group_empty_dirs` merges a chain of directories that
hold nothing but another single directory into one display line —
`personal` containing only `All` containing only `Finish` renders as
`personal/All/Finish`. Each `<CR>` lazily loads one more level and rebuilds
that merged node from scratch, which can leave it reporting
`is_expanded() == false` right after the very expand that just opened it —
so `<CR>` never recognizes it as open, and every further press just drills
one level deeper with no way back to `personal`.

`<S-CR>` collapses the node when it is expanded, and falls back to its
nearest collapsible ancestor when it isn't (the same fallback neo-tree's own
`close_node` command — bound to `C` by default — uses). Each merge step
re-parents the replacement node onto the *grandparent* of whatever it just
absorbed, so a chain merged all the way from a top-level directory ends up
parented directly on the tree root — nothing left to structurally collapse
without hiding the whole tree. For that case `<S-CR>` falls back once more,
to a plain refresh: a re-scan rebuilds the top level fresh from disk, which
is unmerged and collapsed because the node was never actually marked
expanded to begin with.

- **Module (adapter side):** `M.collapse_node()` in
  `lua/filetree/adapter/neotree.lua`

## Buffer Save

Force-save the adjacent editor's buffer (`<C-s>`) or the node's own
buffer if it's open elsewhere (`<M-s>`), without leaving the tree window.

- **Module:** `lua/filetree/features/fileops/buffer_save/`
- **Keymaps:** `<C-s>`, `<M-s>`

## Link Create

`:Filetree link` creates a symlink or hardlink inside the current tree
directory, pointing at a path you type into a prompt. The link is named
after the target's basename, and lands in the node under the cursor — its
own directory if it is one, otherwise its parent, the same resolution
Smart Create uses.

A directory target only ever gets a symlink: neither Windows nor POSIX
lets an unprivileged process hard-link a directory. A file target is
offered the Symlink / Hardlink choice.

`:Filetree link mark [path]` / `:Filetree link paste` are a faster
mark-once, paste-many pair for the same job. Marking with no path uses the
node under the cursor when the tree is focused, else the focused editor
buffer's file; an explicit path (relative or absolute) always wins.
Pasting inserts the marked source into the node under the cursor and picks
the link kind itself instead of asking: directories always get a symlink;
files get a hardlink on Windows (needs no elevation or Developer Mode,
unlike a Windows symlink) and a symlink elsewhere. Marking again replaces
the previous source; pasting does not clear it, so one marked source can
be linked into several places in a row.

Usercmd-first, like Path Copy's format picker: no key is bound by
default, so set `features.link_create.keymap` (or `.keymap_mark` /
`.keymap_paste`) if you want one.

A link created this way is not just another entry in the listing — see
[Link Marker](UI.md#link-marker) for the `⇢` sign that sets it apart in the
tree, and Node Info's `I` window for the `Link to:` / hard-link detail.

- **Module:** `lua/filetree/features/fileops/link_create/`
- **Commands:** `:Filetree link`, `:Filetree link mark [path]`, `:Filetree link paste`
- **Config:** `features.link_create.keymap` / `.keymap_mark` / `.keymap_paste` (all unset by default)
