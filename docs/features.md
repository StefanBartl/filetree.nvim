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
| `context_menu` | Right-click (`<RightMouse>`) opens a context menu via [nvzone/menu](https://github.com/nvzone/menu) — soft dependency, inert without it installed; see [docs/menu.md](menu.md) |

## `fileops` — create / edit / move

| Feature | What it does |
|---|---|
| `smart_create` | Smart create file or directory with templates (`a`) |
| `copy_move` | Stage copy/cut (`c`/`x`) and paste (`p`) nodes |
| `rename_batch` | Edit-buffer batch rename (`<leader>rb`) |
| `smart_rename` | Rename with LSP reference updates (`r`) |
| `create_from_template` | Create a file from a template — filename first, then a picker filtered to that extension; reorder with `<M-j>`/`<M-k>` (`A`) |
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
| `open_in_fm` | Show the node in the system file manager — a file selected in its parent directory, a directory navigated into (`<leader>fm`) |
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
| `watcher_quarantine` | Suppress watcher EPERM noise around file ops (Windows/WSL) _(complementary to `handle_guard` — this hides the error, `handle_guard` prevents it)_ |
| `handle_guard` | Release neo-tree's directory-watcher handles before a rename/move/trash so the Windows file-lock (EPERM/`ERROR_SHARING_VIOLATION`) can't happen in the first place; `:Filetree handles` inspects tracked handles _(opt-in)_ |
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
| `handle_guard` | Patches a neo-tree internal (`fs_watch`) and closes libuv handles it owns — opt-in until you want that behaviour. neo-tree adapter + Windows/WSL only; a no-op elsewhere |

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

When `reveal = true` (the default), cwd_sync auto-pauses for 2 seconds when
the cursor enters the tree window — the tree's own `<CR>`-driven open could
otherwise race cwd_sync's own reveal on the file it just opened. With
`reveal = false` this pause never triggers (there's no reveal of ours left to
race — the tree plugin owns that), so a file opened shortly after leaving the
tree — e.g. from a picker invoked with the cursor still in the tree window —
still gets its `chdir`.

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

### Create From Template

Press `A` (the `smart_create` "`a`" counterpart), or `:Filetree template`.
Workflow, in order:

1. **Filename first.** You're prompted for the new file's name before
   anything else — the destination path is fully known from this point on.
2. **Filtered picker.** The template list is narrowed to templates whose own
   extension matches the filename you just typed (`foo.lua` → only `.lua`
   templates). If nothing matches, or the filename has no extension, the full
   list is shown instead — a filter that leaves nothing to pick from is a
   dead end, not a useful restriction.
3. **Pick a template.** Variables substitute against the real destination
   (see below), then the file is created and opened.

**Built-in templates** ship with filetree.nvim itself — several per language
for the common ones, so the extension filter in step 2 leaves you with a real
choice rather than a single entry:

| Extension | Templates |
|---|---|
| `.lua` | `lua_module` · `lua_class` · `lua_spec` (busted/plenary) · `lua_types` (`@meta`) |
| `.ts` | `typescript_module` · `typescript_class` · `typescript_test` · `typescript_types.d` |
| `.tsx` | `typescript_react` |
| `.js` | `javascript_module` · `javascript_test` |
| `.py` | `python_module` · `python_class` · `python_test` · `python_main` |
| `.go` | `go_package` · `go_main` · `go_test` |
| `.rs` | `rust_module` · `rust_main` · `rust_test` |
| `.cs` | `csharp_class` · `csharp_interface` · `csharp_test` |
| `.c` / `.h` | `c_source` · `c_header` |
| `.cpp` / `.hpp` | `cpp_source` · `cpp_header` |
| `.zig` | `zig_module` · `zig_test` |
| `.json` | `json_object` · `json_package` · `json_tsconfig` |
| `.md` | `markdown_doc` · `markdown_readme` |
| `.yaml` / `.yml` | `yaml_document` · `yaml_workflow` (GitHub Actions) |
| `.toml` | `toml_config` |
| `.sh` / `.ps1` | `shell_script` · `powershell_script` |
| `.html` / `.css` | `html_page` · `css_stylesheet` |
| `.wat` | `wasm_module` |

They show up in the picker with a
`[builtin]` marker. **Add your own** by dropping a file into the template
directory (default `stdpath("data")/filetree/templates/`) — its filename
becomes the template name — or call `M.add_template(name, content)`. A user
template with the **same name** as a built-in shadows it entirely (name and
content); that's how you customize a shipped default.

**Reorder** while the picker is open, filter empty (not mid-search):
`<M-j>`/`<M-k>` move the highlighted template down/up, persisted immediately
to a `.order.json` sidecar in the template directory. A never-reordered or
newly-added template is appended alphabetically after the ones with an
explicit position.

**Variables:**

| Variable | Value |
|---|---|
| `${filename}` | Basename of the new file, without extension |
| `${ext}` | Extension of the new file, without the dot |
| `${date}` / `${year}` / `${month}` / `${day}` / `${time}` | Current date/time components |
| `${author}` | `config.author`, else `$USER`/`$USERNAME` |
| `${module}` | For a destination under a real `lua/` directory: the canonical Lua module path (`lua/plugins/test.lua` → `plugins.test`) via `lib.nvim.lua_ls.get_module_path` — the same resolver the `lua_require_copy` feature (`paths` category, above) is conceptually doing by hand. Otherwise a generic dotted path from the project root, any language (`src/foo/Bar.cs` → `src.foo.Bar`) |

```lua
local tpl = require("filetree").feature("create_from_template")
tpl.list()                                  -- all templates, in display order
tpl.add_template("go_test.go", "package ${filename}\n")
tpl.move("go_test.go", -1)                  -- same as pressing <M-k> on it
```

### Handle Guard

Fixes a sporadic Windows file-lock at the source, rather than hiding it like
`watcher_quarantine` does. neo-tree's own directory watchers (with
`use_libuv_file_watcher = true`) keep an OS handle open per expanded
directory and never close it — so renaming/deleting a watched directory can
intermittently fail with `EPERM` / `ERROR_SHARING_VIOLATION`, because
filetree's own watcher is still holding it.

Opt-in (patches a neo-tree internal + closes libuv handles), neo-tree
adapter + Windows/WSL only, a no-op elsewhere:

```lua
require("filetree").setup({
  features = { handle_guard = { enabled = true } },
})
```

Once enabled, it's wired automatically into the fileops that move/rename/
trash a watched path — no further configuration needed. Inspect live with
`:Filetree handles` (lists tracked handles, flags any pointing at a path
that no longer exists — the leak signature) or `:checkhealth filetree`.
