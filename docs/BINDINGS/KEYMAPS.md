# filetree.nvim — Keymaps

All keymaps are buffer-local (tree window) unless marked **global**.
A `?` suffix means the field is optional; omit or set to `false` to disable.

> **neo-tree `?` cheatsheet:** filetree keymaps are shown there automatically
> (filetree injects them into neo-tree's mapping registry on `setup()`).
> For **nvim-tree** (`g?`) and other adapters the keymaps are set via
> `vim.keymap.set()` in a FileType autocmd, which is outside their help registry,
> so their built-in help will not list them (the keymaps still work — check with
> `:nmap` in the tree buffer). See
> [neo-tree `?` cheatsheet integration](#neo-tree--cheatsheet-integration) for details.

---

## Tree-buffer keymaps

| Key | Feature | Config field | Action |
|-----|---------|-------------|--------|
| `m` | marks | `keymap` | Toggle mark on current node |
| `]m` | marks | `keymap_all` | Mark all nodes in current directory |
| `[m` | marks | `keymap_unmark_all` | Unmark all nodes in current directory |
| `<leader>mc` | marks | `keymap_clear` | Clear all marks |
| `<leader>ms` | marks | `keymap_show` | Show floating list of marked nodes |
| `-` | tree_traverse | `keymap_up` | Navigate to parent directory |
| `+` | tree_traverse | `keymap_down` | Set current dir as tree root |
| `[a` | path_copy | `keymap_abs` | Copy absolute path to clipboard |
| `]a` | path_copy | `keymap_rel` | Copy relative path to clipboard |
| `<leader>yp` | path_copy | `keymap_pick` | Open path-format picker |
| `<leader>yn` | path_copy | `keymap_name` | Copy filename only |
| `gB` | git_blame | `keymap` | Toggle git blame float |
| `gs` | live_search | `keymap` | Open live search in tree |
| `I` | node_info | `keymap` | Show node info float |
| `rq` | lua_require_copy | `keymap` | Copy file as `require("…")` string |
| `<M-p>` | find_or_grep_menu | `keymap` | Open find/grep picker menu |
| `[f` | copy_file_list | `keymap_files_abs` | Copy recursive file list (absolute) |
| `]f` | copy_file_list | `keymap_files_rel` | Copy recursive file list (relative) |
| `[F` | copy_file_list | `keymap_dirs_abs` | Copy recursive dir list (absolute) |
| `]F` | copy_file_list | `keymap_dirs_rel` | Copy recursive dir list (relative) |
| `a` | smart_create | `keymap` | Smart create file or directory |
| `/` | filter | `keymap` | Enter tree filter mode |
| `b` | bookmarks | `keymap` | Toggle bookmark |
| `<Tab>` | preview | `keymap` | Text/dir: toggle floating preview; image: open via backend; PDF: pdfport/system |
| `<CR>` | preview | `keymap_open` | Image/PDF: open via backend; other nodes: adapter's default `<CR>` |
| `D` | diff | `keymap` | Diff current node |
| `gn` | notes | `keymap` | Toggle note on current node |
| `cl` | color_labels | `keymap` | Open color-label picker |
| `<C-o>` | jump_list | `keymap_back` | Navigate backwards in jump list |
| `<C-n>` | jump_list | `keymap_fwd` | Navigate forwards in jump list |
| `go` | outline | `keymap` | Show LSP outline for current file |
| `cd` | compare_dirs | `keymap` | Compare directories |
| `gp` | pin_node | `keymap` | Pin current node |
| `gw` | workspace | `keymap_switch` | Switch workspace root |
| `gi` | ignore_patterns | `keymap` | Toggle ignore-pattern highlighting |
| `az` | archive | `keymap_zip` | Zip current node |
| `at` | archive | `keymap_tar` | Tar.gz current node |
| `gs` | git_actions | `keymap_stage` | Stage current node ⚠️ conflicts with live_search |
| `gS` | git_actions | `keymap_unstage` | Unstage current node |
| `gl` | git_actions | `keymap_log` | Show git log for current file |
| `<C-d>` | duplicate_node | `keymap` | Duplicate current node |
| `ox` | open_with | `keymap` | Open with system default |
| `<F2>` | smart_rename | `keymap` | Rename with LSP reference update |
| `gt` | tag_system | `keymap` | Edit tags for current node |
| `df` | diagnostics_filter | `keymap` | Toggle diagnostic filter |
| `<C-p>` | quick_open | `keymap` | Open frecency-sorted quick-open picker |
| `gh` | harpoon_integration | `keymap_add` | Add to harpoon |
| `gH` | harpoon_integration | `keymap_menu` | Open harpoon quick-menu |
| `gx` | file_permissions | `keymap_exec` | Toggle execute bit |
| `gX` | file_permissions | `keymap_chmod` | Interactive chmod prompt |
| `gP` | file_permissions | `keymap_show` | Show stat details |
| `t` | create_from_template | `keymap` | Create from template |
| `sl` | symlink | `keymap_follow` | Follow symlink |
| `sL` | symlink | `keymap_create` | Create symlink to current |
| `R` | rename_batch | `keymap` | Open batch rename buffer |
| `T` | open_terminal | `keymap` | Open terminal in node directory |
| `f` | find_files | `keymap_tree` | Find files (telescope/fzf-lua/builtin) |
| `<leader>fr` | recent_files | `keymap_tree` | Open recent files picker (not `r` — that is neo-tree's native rename) |
| `gr` | grep_in_dir | `keymap` | Grep in node directory |
| `gR` | grep_in_dir | `keymap_cword` | Grep `<cword>` in node directory |
| `yy` | copy_move | `keymaps.copy` | Stage node for copy |
| `xx` | copy_move | `keymaps.cut` | Stage node for cut |
| `p` | copy_move | `keymaps.paste` | Paste staged nodes |
| `P` | copy_move | `keymaps.show` | Show copy/cut clipboard |
| `ya` | path_utils | `keymaps.copy_abs` | Copy absolute path |
| `yr` | path_utils | `keymaps.copy_rel` | Copy relative path |
| `yn` | path_utils | `keymaps.copy_name` | Copy filename |
| `yd` | path_utils | `keymaps.copy_dir` | Copy parent directory |
| `yq` | path_utils | `keymaps.to_require` | Copy as `require()` string |
| `ym` | path_utils | `keymaps.md_link` | Copy as Markdown link |
| `<C-s>` | buffer_save | `keymap_adjacent` | Force-save the adjacent editor buffer |
| `<M-s>` | buffer_save | `keymap_node` | Force-save buffer matching node under cursor |
| `w` | window_size_cycler | `keymap` | Cycle tree width through presets (normal → large → small → …) |
| `<leader>fm` | open_in_fm | `keymap` | Open node directory in system file manager |
| `i` | shell_run | `keymap` | Prompt for a shell command, run in node directory |

---

## Global keymaps

| Key | Feature | Config field | Action |
|-----|---------|-------------|--------|
| `<leader>ftp` | picker | `keymaps.trigger_reveal` | Enter picker + reveal current file |
| `<leader>ftc` | picker | `keymaps.trigger_cwd` | Enter picker at cwd |

---

## Known conflicts

| Keys | Features | Notes |
|------|---------|-------|
| `gs` | `live_search` + `git_actions.keymap_stage` | Both default to `gs`. Enable only one, or remap the other. |
| `<Tab>` | `preview` + neotree picker (inside picker mode) | neotree's picker uses `<Tab>` to cycle filter. Only conflicts when the picker feature is active simultaneously. |
| `/` | `filter` + neotree fuzzy finder | neotree uses `/` for its own search. Remap `filter.keymap` if using neotree. |
| `ya`/`yr`/`yn` | `path_utils` + `path_copy` | Both provide path-copy commands. Enable only one. |
| `i` | `shell_run` + neotree built-in `i` (toggle node info) | filetree's `node_info` provides a better `I`; noop neotree's `i` via `adapter_keymaps`. |

---

## Overriding adapter (neotree) native keymaps

Use `adapter_keymaps` to noop or remap any key that the adapter (neotree) sets
natively — filetree.nvim applies these overrides after the adapter's own
buffer-local keymaps are in place.

```lua
require("filetree").setup({
  -- noop neotree's built-in `i` (toggle node info); our `node_info` uses `I`
  adapter_keymaps = {
    ["i"] = false,   -- false → <Nop>
  },
  features = {
    shell_run  = { enabled = true, keymap = "i" },
    node_info  = { enabled = true, keymap = "I" },
  },
})
```

`false` maps the key to `<Nop>`.  A string value remaps to that target key.

---

## Remapping keys

Use the top-level `keymaps` table to rename or disable any key globally across all features:

```lua
require("filetree").setup({
  keymaps = {
    -- rename
    ["gs"]   = "<leader>gs",   -- live_search: gs → <leader>gs
    -- disable
    ["<leader>mc"] = false,     -- marks.keymap_clear: disabled
  },
  features = { ... },
})
```

The remap runs after all feature configs are merged, so it overrides both defaults
and any per-feature overrides the user has set.

To remap a single feature only, set it directly in the feature config:

```lua
require("filetree").setup({
  features = {
    live_search = { enabled = true, keymap = "<leader>gs" },
  },
})
```

---

## neo-tree `?` cheatsheet integration

neo-tree builds its `?` help screen from its `window.mappings` config (via
`state.resolved_mappings`) — it does **not** read the buffer's actual keymaps.
Because filetree sets its keymaps via a FileType autocmd (after neo-tree's own
setup), those keymaps work but would normally be invisible to `?`.

### Automatic (default)

You don't need to do anything. `require("filetree").setup(config)` injects the
enabled feature keymaps into neo-tree's live config (and any open tree) after
neo-tree is configured, so they appear in `?` with a `filetree: …` label:

```lua
-- filetree plugin spec — that's it
config = function()
  require("filetree").setup({
    adapter = "neotree",
    features = {
      marks         = { enabled = true, keymap = "m" },
      tree_traverse = { enabled = true, keymap_up = "-", keymap_down = "+" },
      -- …
    },
  })
end
```

The injection runs once when Neovim finishes starting (or immediately if filetree
is loaded after startup), which handles the `lazy = false` ordering race where
neo-tree's `setup()` may run before or after filetree's.

### Explicit (optional)

If you'd rather not rely on post-setup config mutation, call
`require("filetree").attach(opts, config)` **before** `neo-tree.setup(opts)` to
inject the same entries into the `opts` table yourself. Point both `attach` and
`setup` at one shared config table so they can't drift:

```lua
-- neo-tree plugin spec
config = function(_, opts)
  require("filetree").attach(opts, require("config.filetree"))
  require("neo-tree").setup(opts)
end

-- filetree plugin spec
config = function()
  require("filetree").setup(require("config.filetree"))
end
```

### Notes

- Integration is neo-tree-specific. For other adapters the keymaps still work but
  won't appear in their native help; verify with `:nmap` in the tree buffer.
- The FileType autocmds always run, so keymaps behave identically regardless —
  the injection only adds cheatsheet visibility (and native `?` multi-key sub-menu
  grouping for prefixes like `]m` / `[m`).
- Keys resolve from your feature config; a field set to `false` is skipped, and
  omitted fields fall back to the feature's default key.
