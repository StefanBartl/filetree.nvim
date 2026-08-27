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
summary) via the optional `lib.nvim.progress` dependency — see
[Progress indicators](../configuration.md#full-option-reference)'s
`progress_style` option (top-level `require("filetree").setup({...})`
config, not per-feature).

A cut+paste is a move, so it runs the [reference engine](#references)
too — the scan starts when you press `x`, and overlaps with you navigating
to the paste target. A copy never breaks a reference (the original stays
put), so copies are not scanned.

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

Cross-platform trash (not permanent delete) with undo — `d` to trash,
`U` to undo, `<leader>th` for trash history. How far back that reaches is
`features.trash.max_history` (default 50, `0` = unlimited): a preference,
not a limit protecting anything, since the history is a small JSON file. Marking multiple nodes and
trashing them opens one batch confirmation instead of one prompt per
file, and force-closes any open buffers backed by the deleted paths so
they don't linger as edits-to-nowhere. Same optional progress indicator
as Copy / Move above, for both the "delete all at once" and "confirm
each individually" batch paths.

When something links to the file being deleted, the plain yes/no becomes a
chooser — **Delete + remove refs** (blanks the dangling links to `REF!`),
**Inspect first** (pick which ones), **Delete, keep refs**, **Cancel**.
See [References](#references).

- **Module:** `lua/filetree/features/fileops/trash/`
- **Keymaps:** `d`, `U`, `<leader>th`

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

Deleting is the mirror image: trash offers to blank the now-dangling
markdown links to `REF!` before the file goes, so the break is visible
instead of silent. Code references are deliberately left alone there —
a `require("REF!")` is worse than an obviously stale one.

### Languages

| Provider | Covers | Default |
|---|---|---|
| `markdown` | `[text](./path)`, `![img](…)`, reference definitions `[id]: …`, HTML `src=`/`href=`, optionally `[[wiki]]` links | on |
| `lua` | `require("a.b")` / `require "a.b"`, including the submodule cascade when a directory moves | on |
| `python` | `import a.b`, `from a.b import x`, and relative `from .x import y` | on |
| `ts_js` | `import`/`export … from`, dynamic `import()`, CJS `require()`, relative specifiers plus `tsconfig`/`jsconfig` `paths` aliases | **off** |

`ts_js` is opt-in: `tsserver` implements `willRenameFiles` and does a
better job when it is running, so the textual provider is there for
projects without it.

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
capped libuv walk, which is slower but still correct.

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

`O` opens the node under the cursor, replacing the current editor buffer
rather than adding a new one — for when you don't want the previous
buffer kept around in the window.

- **Module:** `lua/filetree/features/fileops/open_replace/`
- **Keymaps:** `O`

## Open Variants

Open a node in a split (`sg`), vsplit (`sv`), tab (`st`), or add it to
the buffer list without switching focus (`gb`/`<S-CR>`) — every common
"open, but not by replacing my current window" shape in one feature.

- **Module:** `lua/filetree/features/fileops/open_variants/`
- **Keymaps:** `sg`, `sv`, `st`, `gb`/`<S-CR>`

## Buffer Save

Force-save the adjacent editor's buffer (`<C-s>`) or the node's own
buffer if it's open elsewhere (`<M-s>`), without leaving the tree window.

- **Module:** `lua/filetree/features/fileops/buffer_save/`
- **Keymaps:** `<C-s>`, `<M-s>`
