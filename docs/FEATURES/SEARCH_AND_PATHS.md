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
(`[a`/`]a`), or the path relative to the project root (`[R`/`]R`) — keys
covering the "I need this path somewhere else" cases without a prompt.

Two more answer the cases where neither the cwd nor the project root is
the right frame of reference:

`]b` copies the path **relative to the buffer open in the editor**, in
the `./x` / `../x` form a Markdown link target needs. This is the one
that makes a pasted link actually resolve: with the cwd at the repo
root, `docs/ROADMAP/ROADMAP.md` is correct in the root README and wrong
in `docs/ROADMAP/Notes.md`, where the same file is `./ROADMAP.md`. `]b`
reads the open buffer's directory instead of the cwd, so it is right in
both. The base is the editor window's file, then the alternate file
(`#`), then the cwd — so it still answers something when the tree is the
only window.

`[e` copies the **absolute** path, but folds a configured environment
variable back into its root: `$REPOS_DIR/filetree.nvim/lua/x.lua` rather
than `E:/repos/filetree.nvim/lua/x.lua`. Written into a note, that path
still means the same file on a machine where the checkout lives on
another drive. The variables to try are `env_roots` (default
`{ "REPOS_DIR" }`, written without the `$`); the longest match wins, so
a `$REPOS_DIR` inside `$HOME` beats `$HOME`. With no variable matching,
the plain absolute path comes back.

```lua
path_copy = {
  enabled = true,
  keymap_buffer_rel = "]b",
  keymap_env_root = "[e",
  -- Longest match wins; each name is written without the `$`.
  env_roots = { "REPOS_DIR", "XDG_CONFIG_HOME", "HOME" },
}
```

- **Module:** `lua/filetree/features/paths/path_copy/`
- **Keymaps:** `[a`, `]a`, `[R`, `]R`, `]b`, `[e`

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
