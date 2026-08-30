# filetree.nvim — Keymaps

All keymaps are buffer-local (tree window) unless marked **global**.
A `?` suffix means the field is optional; omit or set to `false` to disable.

Every one of them is declared as a named action through
[`lib.nvim.bindings.keymap`](https://github.com/StefanBartl/lib.nvim), which is
what lets a config field also hold a **list** of keys
(`keymap_abs = { "Y", "gy" }`) and what makes the `?` cheatsheet list the keys
you actually have rather than the ones this plugin ships with. Read them back
at runtime with `:lua vim.print(require("filetree.bindings").live())` —
`require("filetree.bindings").keymaps` is the shipped defaults instead.

> **neo-tree `?` cheatsheet:** filetree keymaps are shown there automatically
> (filetree injects them into neo-tree's mapping registry on `setup()`).
> For **nvim-tree** (`g?`) and other adapters the keymaps are set via the
> central tree-attach dispatcher, which is outside their help registry,
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
| `gm` | marks | `keymap_goto` | Go to the Nth marked node in render order (`Ngm`; a too-large count clamps to the last) |
| `]M` | marks | `keymap_next` | Next marked node, wrapping |
| `[M` | marks | `keymap_prev` | Previous marked node, wrapping |
| `-` | tree_traverse | `keymap_up` | Navigate to parent directory |
| `+` | tree_traverse | `keymap_down` | Set current dir as tree root |
| `L` | cwd_mode | `keymap_cycle` | Cycle the cwd policy (follow → project → lock) |
| `gp` | cwd_mode | `keymap_lock_here` | Lock the cwd to the node under the cursor |
| `<C-n>` | buffer_cycle | `keymap_next` | Next buffer in the adjacent editor window (tree keeps focus) |
| `<C-p>` | buffer_cycle | `keymap_prev` | Previous buffer in the adjacent editor window (tree keeps focus) |
| `[a` | path_copy | `keymap_abs` | Copy absolute path to clipboard |
| `]a` | path_copy | `keymap_dirname` | Copy absolute parent directory to clipboard |
| `[R` | path_copy | `keymap_project_root` | Copy absolute project root path to clipboard |
| `]R` | path_copy | `keymap_project_rel` | Copy path relative to project root (cwd-independent) |
| `d` | trash | `keymap` | Trash current node (or all marked) |
| `U` | trash | `keymap_undo` | Undo last trash operation |
| `<leader>th` | trash | `keymap_history` | Show trash history |
| `gs` | live_search | `keymap` | Open live search in tree |
| `I` | node_info | `keymap` | Show node info float |
| `rq` | lua_require_copy | `keymap` | Copy file as `require("…")` string |
| `[f` | copy_file_list | `keymap_files_abs` | Copy recursive file list (absolute) |
| `]f` | copy_file_list | `keymap_files_rel` | Copy recursive file list (relative) |
| `[F` | copy_file_list | `keymap_dirs_abs` | Copy recursive dir list (absolute) |
| `]F` | copy_file_list | `keymap_dirs_rel` | Copy recursive dir list (relative) |
| `a` | smart_create | `keymap` | Smart create file or directory |
| `/` | filter | `keymap` | Enter tree filter mode |
| `<C-c>` | filter | `keymap_clear` | Clear an applied filter directly |
| `<Tab>` | preview | `keymap` | Text/dir: toggle floating preview; image: open via backend; PDF: pdfport/system |
| `<CR>` | preview | `keymap_open` | Image/PDF: open via backend; other nodes: adapter's default `<CR>` |
| `D` | diff | `keymap` | Diff current node |
| `<leader>sm` | open_with | `keymap` | Open with system default |
| `r` | smart_rename | `keymap` | Rename with LSP reference update |
| `M` | move | `keymap` | Move current node (or all marked) to a prompted destination |
| `A` | create_from_template | `keymap` | Create from template — filename first, then a picker filtered to that extension |
| `<RightMouse>` | context_menu | `keymap` | Open a right-click context menu via nvzone/menu (soft dependency) |
| `<leader>rb` | rename_batch | `keymap` | Open batch rename buffer |
| `f` | find_files | `keymap_tree` | Find files (telescope/fzf-lua/builtin) |
| `tf` | find_files | `keymap_telescope` | Find files, forcing telescope specifically |
| `gr` | grep_in_dir | `keymap` | Grep in node directory |
| `tg` | grep_in_dir | `keymap_telescope` | Grep, forcing telescope specifically |
| `c` | copy_move | `keymaps.copy` | Stage node for copy |
| `x` | copy_move | `keymaps.cut` | Stage node for cut |
| `p` | copy_move | `keymaps.paste` | Paste staged nodes |
| `P` | copy_move | `keymaps.show` | Show copy/cut clipboard |
| `<C-c>` | copy_move | `keymaps.clear` | Clear copy/cut clipboard |
| `sg` | open_variants | `keymap_vsplit` | Open current node in a vertical split |
| `sv` | open_variants | `keymap_split` | Open current node in a horizontal split |
| `st` | open_variants | `keymap_tabnew` | Open current node in a new tab |
| `gb` | open_variants | `keymap_badd` | Add current node to buffer list (no focus switch) |
| `<S-CR>` | open_variants | `keymap_badd_alt` | Same as `gb` |
| `<C-s>` | buffer_save | `keymap_adjacent` | Force-save the adjacent editor buffer |
| `<M-s>` | buffer_save | `keymap_node` | Force-save buffer matching node under cursor |
| `w` | window_size_cycler | `keymap` | Cycle tree width through presets (normal → large → small → …) |
| `<leader>fm` | open_in_fm | `keymap` | Open node directory in system file manager |
| `i` | shell_run | `keymap` | Prompt for a shell command, run in node directory |
| `gP` | pdf_create | `keymap` | Create PDF(s) from the current node/marked nodes/folder via pdfport.nvim (confirms first) |

### Visual-mode keymaps

The only two this plugin binds in Visual mode. A line range over a rendered
tree is exactly a set of nodes, so marking a run of files is a motion rather
than one keypress per line.

| Key | Feature | Config field | Action |
|-----|---------|-------------|--------|
| `m` | marks | `keymap` | Mark every node in the selection |
| `[m` | marks | `keymap_unmark_all` | Unmark every node in the selection |

---

## Known conflicts

| Keys | Features | Notes |
|------|---------|-------|
| `/` | `filter` + neotree fuzzy finder | neotree uses `/` for its own search. Remap `filter.keymap` if using neotree. |
| `i` | `shell_run` + neotree built-in `i` (toggle node info) | filetree's `node_info` provides a better `I`; noop neotree's `i` via `adapter_keymaps`. |
| `<C-c>` | `filter.keymap_clear` + `copy_move.keymaps.clear` | Both default to `<C-c>`. Last one registered wins; remap one if you need both reachable at once. |
| `m` | `marks` + neotree built-in `m` (move) | filetree binds `m` to marking, shadowing neo-tree's own move. filetree's `M` does the same job and updates references while it's at it. |

### Keys deliberately not used

`<C-m>`, `<C-i>` and `<C-[>` are the same bytes as `<CR>`, `<Tab>` and `<Esc>`
(0x0D, 0x09, 0x1B). Neovim keeps both spellings as separate mappings, but a
terminal only sends the *distinct* sequence for the Ctrl form when an extended
encoding is active ("CSI u"/modifyOtherKeys, or the Windows console) — without
one, the byte always resolves to `<CR>`/`<Tab>`/`<Esc>`, and it does so even
when nothing maps those at all. A mapping on the Ctrl spelling is therefore
not "shadowed", it is simply dead for most users.

`marks.keymap_clear` sat on `<C-m>` until 2026-08-30 for exactly that reason;
it defaults to `<leader>mc` now. `TESTS/smoke.lua` check 6 folds the three
pairs together and fails the build if two default-on tree keymaps land on one
physical key, so this cannot come back unnoticed.

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
Because filetree sets its keymaps via the central tree-attach dispatcher (after
neo-tree's own setup), those keymaps work but would normally be invisible to `?`.

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
- The tree-attach dispatcher always runs, so keymaps behave identically
  regardless — the injection only adds cheatsheet visibility (and native `?`
  multi-key sub-menu grouping for prefixes like `]m` / `[m`).
- Keys resolve from your feature config; a field set to `false` is skipped, and
  omitted fields fall back to the feature's default key.
