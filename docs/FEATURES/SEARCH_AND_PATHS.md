# Search & paths

Filtering, finding and grepping inside the tree, plus getting a node's
path — or its content, as a Markdown link — out of the tree and onto the
clipboard or into a buffer.

## Filter

Live-filters the tree listing as you type (`/`) — narrows what's shown
without leaving the tree, unlike find/grep below which open a separate
picker.

- **Module:** `lua/filetree/features/search/filter/`
- **Keymaps:** `/`

## Live Search

Incremental search inside the tree (`gs`) — jumps between matches without
filtering the listing down, complementing `filter` rather than
duplicating it.

- **Module:** `lua/filetree/features/search/live_search/`
- **Keymaps:** `gs`

## Find Files

`f` finds files via whichever picker engine is available — telescope,
fzf-lua, mini.pick, or a built-in fallback — auto-detected. `tf` forces
telescope specifically, for a config running more than one picker plugin
side by side.

- **Module:** `lua/filetree/features/search/find_files/`
- **Keymaps:** `f` (auto), `tf` (force telescope)

## Grep In Directory

`gr` greps inside the node's directory using the same auto-detected
picker engine as `find_files`; `tg` forces telescope specifically.

- **Module:** `lua/filetree/features/search/grep_in_dir/`
- **Keymaps:** `gr` (auto), `tg` (force telescope)

## Path Copy

Copies the node's absolute path or its parent directory's path
(`[a`/`]a`), or the path relative to the project root (`[R`/`]R`) — four
keys covering the "I need this path somewhere else" cases without a
prompt.

- **Module:** `lua/filetree/features/paths/path_copy/`
- **Keymaps:** `[a`, `]a`, `[R`, `]R`

## Lua Require Copy

`rq` copies the node as a `require("…")` string, resolved the same way
[FILEOPS.md](FILEOPS.md)'s `create_from_template` resolves its
`${module}` template variable — for a Lua file under a real `lua/`
directory, the canonical dotted module path.

- **Module:** `lua/filetree/features/paths/lua_require_copy/`
- **Keymaps:** `rq`

## Copy File List

Copies a recursive listing of files and/or directories under the node —
`[f`/`]f` for files, `[F`/`]F` for directories — useful for pasting a
directory's contents into an issue, a prompt, or a script.

- **Module:** `lua/filetree/features/paths/copy_file_list/`
- **Keymaps:** `[f`, `]f`, `[F`, `]F`

## Markdown Links

Copies the current node, a recursive listing, or every marked node as
Markdown links (`ML`/`MR`/`MM`) — for dropping references into a README
or a design doc directly from the tree, no manual path-to-link
formatting.

- **Module:** `lua/filetree/features/paths/markdown_links/`
- **Keymaps:** `ML`, `MR`, `MM`
