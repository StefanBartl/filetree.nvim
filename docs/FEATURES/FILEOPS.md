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

- **Module:** `lua/filetree/features/fileops/copy_move/`
- **Keymaps:** `c` (copy), `x` (cut), `p` (paste)

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
`U` to undo, `<leader>th` for trash history. Marking multiple nodes and
trashing them opens one batch confirmation instead of one prompt per
file, and force-closes any open buffers backed by the deleted paths so
they don't linger as edits-to-nowhere. Same optional progress indicator
as Copy / Move above, for both the "delete all at once" and "confirm
each individually" batch paths.

- **Module:** `lua/filetree/features/fileops/trash/`
- **Keymaps:** `d`, `U`, `<leader>th`

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
