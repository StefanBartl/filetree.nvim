# Features

Features live in category subfolders under `lua/filetree/features/<category>/` and
the tables below mirror those categories exactly (same order as
`filetree.features.CATEGORY_ORDER`, which also drives `:checkhealth filetree`).
All features are **on by default** unless marked _(opt-in)_ — those are collected
under [Default-disabled features](#default-disabled-features). Every tree-buffer
key is remappable; see [docs/BINDINGS/KEYMAPS.md](BINDINGS/KEYMAPS.md).

## `nav` — navigation & reveal

| Feature | What it does |
|---|---|
| `tree_traverse` | `-` go to parent dir, `+` set dir under cursor as tree root |
| `reveal_alt` | Reveal the alternate buffer `#` in the tree (`B`) |
| `auto_reveal` | Scroll to (or expand+reveal) the current file in the tree on buffer switch, never changing cwd/root |
| `layout_guard` | Opens an editor window when the tree would be the only window |
| `auto_resize` | Responsive tree width on `VimResized` _(opt-in)_ |
| `cwd_sync` | Silently `chdir` to the current file's project root (nearest `.git` ancestor by default) and root the tree there, then reveal the file _(opt-in)_ |

## `ui` — display

| Feature | What it does |
|---|---|
| `preview` | Toggle preview in the editor window (live-updates on cursor move) or a float; dispatch images / PDFs (`<Tab>`/`<CR>`); `<PageUp>`/`<PageDown>` page the preview |
| `node_info` | Node info float (`I`): path, type, size, mode, mtime; line count for files, recursive item count + aggregate size for folders |
| `breadcrumbs` | Path breadcrumbs for the current node |
| `size_info` | Show file / directory sizes |
| `window_size_cycler` | Cycle the tree width through presets (`w`) |
| `window_style` | Blank statusline (adapter-agnostic, on by default) + isolated tree highlights (opt-in) |
| `cursor_hide` | Hide the block cursor inside the tree (adapter-agnostic via adapter `filetypes`) |
| `tree_reset` | `<Esc>` clears preview + filter + live search |
| `opened_sync` | Re-render the tree on buffer open/close so the tree plugin's opened-file highlights stay in sync |
| `current_hl` | Highlight the current file + parent dir, optional sign-column icon on the focused file _(opt-in)_ |

## `fileops` — create / edit / move

| Feature | What it does |
|---|---|
| `smart_create` | Smart create file or directory with templates (`a`) |
| `copy_move` | Stage copy/cut (`c`/`x`) and paste (`p`) nodes |
| `rename_batch` | Edit-buffer batch rename (`<leader>rb`) |
| `smart_rename` | Rename with LSP reference updates (`r`) |
| `create_from_template` | Create a file from a template (`t`) |
| `trash` | Cross-platform trash + undo (`d` `U` `<leader>th`); one batch chooser for multi-mark deletes, force-closes the deleted file's buffers |
| `open_replace` | Open a file replacing the current editor buffer (`O`) |
| `open_variants` | Open in split/vsplit/tab, or badd without switching focus (`sg` `sv` `st` `gb`/`<S-CR>`) |
| `buffer_save` | Force-save adjacent / node buffer (`<C-s>`/`<M-s>`) |

## `search` — search & filter

| Feature | What it does |
|---|---|
| `filter` | Live tree filter (`/`) |
| `live_search` | Incremental search inside the tree (`gs`) |
| `find_files` | Find files via telescope / fzf-lua / mini.pick / builtin (`f`); force telescope specifically with `tf` |
| `grep_in_dir` | Grep in the node's directory (`gr`); force telescope specifically with `tg` |

## `paths` — paths & clipboard

| Feature | What it does |
|---|---|
| `path_copy` | Copy absolute path / parent dir (`[a` `]a`), or project root / path relative to it (`[R` `]R`) |
| `lua_require_copy` | Copy the node as a `require("…")` string (`rq`) |
| `copy_file_list` | Copy recursive file/dir lists (`[f` `]f` `[F` `]F`) |
| `markdown_links` | Copy current/recursive/marked nodes as Markdown links (`ML` `MR` `MM`) |

## `git`

| Feature | What it does |
|---|---|
| `git_status` | Git status decorations in the tree |

## `org` — marks & organization

| Feature | What it does |
|---|---|
| `marks` | Toggle marks, batch mark/unmark, show list (`m` `]m` `[m` `<C-m>` `<leader>ms`) |
| `session` | Persist / restore tree state |

## `system` — external programs

| Feature | What it does |
|---|---|
| `open_in_fm` | Open the node's directory in the system file manager (`<leader>fm`) |
| `open_with` | Open with a configured external app (`<leader>sm`) |
| `shell_run` | Prompt + run a shell command in the node's directory (`i`) |

## `lsp` — diagnostics & symbols

| Feature | What it does |
|---|---|
| `lsp_diagnostics` | LSP diagnostic decorations |

## `compare` — diff

| Feature | What it does |
|---|---|
| `diff` | Diff the current node (`D`) |

## `infra` — plumbing

| Feature | What it does |
|---|---|
| `ignore_list` | Hide `.git`, `node_modules`, build artefacts, … |
| `project_root` | Shared, cached project-root detection used by cwd_sync and other features |
| `file_watcher` | Refresh the tree on external filesystem changes |
| `watcher_quarantine` | Suppress watcher EPERM noise around file ops (Windows/WSL) |
| `hooks_api` | Programmatic hooks for other code to react to tree events |
| `safety` | Backup API used before destructive ops _(opt-in)_ |

## Default-disabled features

These stay **off** until you set `{ enabled = true }`, each for a concrete reason:

| Feature | Why it's opt-in |
|---|---|
| `cwd_sync` | Changes the global cwd automatically on buffer switch — aggressive. Coexists with `auto_reveal` (both on by default) via `cwd_sync.reveal`; see [docs/filetree.txt](../doc/filetree.txt) §5.3 |
| `current_hl` | Purely cosmetic; ships hardcoded colours that only fit some colorschemes |
| `safety` | A backup **API** with no keymaps — enabling it has no visible effect unless other code calls in |
| `auto_resize` | Automatic width management fights the manual `window_size_cycler` (on by default) |

## Feature reference

> The deep-dives below cover a few core features. For the complete list of
> features and their keys see the feature categories above and
> [docs/BINDINGS/KEYMAPS.md](BINDINGS/KEYMAPS.md).

### Layout Guard

When all editor windows close, opens a new one automatically. Fires on `BufDelete`, `BufWipeout`, `WinClosed`.

### CWD Sync

On `BufEnter` / `WinEnter`: silently `chdir` to the current file's project
root — resolved via `root_markers` (default `{ ".git" }`, cached), falling
back to `use_project_root` (the broader [project_root](#infra--plumbing)
marker set) and then the file's own parent directory. Never prompts.
Auto-pauses 2 seconds when the cursor enters the tree window (manual
navigation).

With `reveal = true` (the default) the tree is also rooted at that same
directory and the file revealed there. See
[cwd_sync `reveal` per adapter](configuration.md#cwd_sync-reveal-per-adapter) in
the configuration guide for when to set `reveal = false` instead.

```lua
require("filetree").feature("cwd_sync").pause(5000)
```

**neo-tree's own "File not in cwd?" prompt is suppressed automatically.**
neo-tree has a native confirm prompt that fires whenever a reveal is
requested (explicitly, or implicitly via `filesystem.follow_current_file`)
without an explicit `dir` and the target file isn't under the tree's current
root — and this can be triggered by *any* code calling neo-tree's command API,
not just filetree.nvim, including your own custom keymaps. As soon as
`require("filetree").setup({ adapter = "neotree" })` runs, filetree.nvim wraps
neo-tree's `command.execute` once so this prompt can never fire — every
at-risk call gets `reveal_force_cwd = true` applied automatically, while a
call that already sets `dir`, `reveal_force_cwd`, or an explicit
`reveal = false` is left untouched. No configuration needed.

### Project Root

Walks up from a file/directory looking for any of `markers` (`.git`,
`package.json`, `Cargo.toml`, `go.mod`, … — a broad default list covering most
ecosystems), returning the deepest directory that has one. Falls back to the
file's own parent directory (or cwd, if `fallback = "cwd"`) when nothing is
found.

Every directory resolved is cached for the session (not just the query
directory — every intermediate directory walked past en route to a found
root is cached too), so repeated lookups for files in the same project don't
re-walk the filesystem. Disable with `cache = false`, or clear it manually if
a `.git` gets added/removed under an already-visited directory:

```lua
require("filetree").feature("project_root").clear_cache()
require("filetree").feature("project_root").add_markers({ ".myproject" })  -- also clears the cache
```

### Current Highlight

Creates `FiletreeCurrentFile` and `FiletreeCurrentParent` highlight groups and applies them as extmarks on the tree buffer.

### Safety / Backup

```lua
local safety = require("filetree").feature("safety")
local bak = safety.before_delete("/path/to/file.lua")
safety.before_move("/path/src.lua", "/path/dst.lua")
safety.list_backups()
safety.toggle_dry_run()
```
