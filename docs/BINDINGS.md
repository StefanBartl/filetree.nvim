# filetree.nvim — Binding Cheatsheet

The entry point to every keymap, `:Filetree` sub-command and autocommand this
plugin registers.

filetree.nvim carries more bindings than fits one readable page, so the detail
lives in three files next to this one. This page is the map: what exists, where
it is documented, and the handful of facts that are easy to get wrong.

| Surface | Detail page | Count |
| --- | --- | --- |
| Keymaps | [`BINDINGS/KEYMAPS.md`](BINDINGS/KEYMAPS.md) | 72 tree-buffer keys across 33 features |
| User commands | [`BINDINGS/USERCOMMANDS.md`](BINDINGS/USERCOMMANDS.md) | one `:Filetree` composer, 22 sub-command groups |
| Autocommands | [`BINDINGS/AUTOCMDS.md`](BINDINGS/AUTOCMDS.md) | one shared attach autocmd + 12 behavioural ones |

**Machine-readable:** [`docs/BINDINGS.lua`](BINDINGS.lua) returns the same data
as a table (`require("filetree.bindings").catalog()`), read straight from
`lua/filetree/bindings/` and the command dispatcher — so it cannot drift from
what actually runs. Inspect it live with:

```vim
:lua vim.print(require("filetree.bindings").catalog())
```

## Table of content

  - [What is bound where](#what-is-bound-where)
    - [Keymaps](#keymaps)
    - [User commands](#user-commands)
    - [Autocommands](#autocommands)
  - [Keymap prefixes at a glance](#keymap-prefixes-at-a-glance)
  - [Known conflicts](#known-conflicts)
  - [Remapping and disabling](#remapping-and-disabling)
  - [The neo-tree `?` cheatsheet](#the-neo-tree--cheatsheet)

---

## What is bound where

### Keymaps

**Keymaps are buffer-local to the tree window.** They are not global keys: they
exist only while the cursor is in the tree, which is why a single letter like
`d`, `r` or `a` is safe here and would not be anywhere else.

They are registered by **one** shared `FileType` autocommand
(`util.tree_attach`, augroup `filetree_tree_attach`) that dispatches to every
enabled feature's `on_attach(buf)`. No feature creates its own attach
autocommand. Dispatch is deferred with `vim.schedule()` so the callbacks land
after the adapter (neo-tree and friends) has finished its own render-time
keymap setup.

### User commands

**Commands are global.** There is exactly one: `:Filetree`, built with
`lib.nvim.bindings.usercmd.composer`, with sub-command dispatch and tab completion at
every level. `:Ft` is registered as an alias out of the box — `:Ft marks show`
is `:Filetree marks show`. Both the name and the aliases are configurable via
`setup({ command = … })`.

### Autocommands

**Behavioural autocommands** are the second category: reveal, cwd sync, git
refresh, diagnostics, breadcrumbs and so on. Each belongs to a feature and each
can be switched off individually through the top-level `autocmds` table.

To see what is actually registered — with the file and line it came from —
ask the plugin instead of a document:

```lua
vim.print(require("filetree.bindings.autocmds").lines())     -- one line each
vim.print(require("filetree.bindings.autocmds").by_event())  -- grouped by event
```

That is read back from `lib.nvim.bindings.autocmd`'s record of what it
created, not maintained by hand. The hand-written version of this list used
to claim fourteen entries against forty-six real ones.

## Keymap prefixes at a glance

Enough to predict where a key lives without opening the full table:

| Prefix | Meaning | Examples |
| --- | --- | --- |
| `[` / `]` | Paired copy/navigation actions — `[` for the "absolute/upper" variant, `]` for the "relative/lower" one | `[a`/`]a` path, `[R`/`]R` project root, `[f`/`]f` file list, `[m`/`]m` mark all/unmark all. Two paths have no counterpart and so stand alone: `]b` (relative to the open buffer) and `[e` (`$REPOS_DIR/…` or `$NVIM_CONFIG_DIR/…`) |
| `<leader>` | The few actions that open a panel or reach outside the tree | `<leader>ms` marks list, `<leader>th` trash history, `<leader>rb` batch rename, `<leader>fm` file manager, `<leader>sm` system open |
| `s` | Open the node somewhere else | `sg` vsplit, `sv` split, `st` tab |
| `t` | Force pickers.nvim specifically, where a generic key already exists | `tf` find, `tg` grep |
| bare letters | The everyday node operations | `a` create, `r` rename, `d` trash, `M` move, `c`/`x`/`p` copy/cut/paste, `D` diff, `I` info |

## Known conflicts

Three are known and documented rather than silently resolved, because each has a
legitimate other owner (a filetree key shadowing one of neo-tree's own). Two
features of filetree never share a key by default; if you configure them onto
one, `:Filetree keys` lists the clash and offers free alternatives:

| Keys | Colliding owners | Resolution |
| --- | --- | --- |
| `/` | `filter` vs. neo-tree's own fuzzy finder | Remap `filter.keymap` if you want neo-tree's search back |
| `i` | `shell_run` vs. neo-tree's built-in `i` (node info) | filetree's `node_info` on `I` is the better one; noop neo-tree's `i` via `adapter_keymaps` |
| `m` | `marks` vs. neo-tree's built-in `m` (move) | filetree binds marking; its own `M` does the move *and* updates references |

`adapter_keymaps` is the escape hatch for the adapter's own keys:
`["i"] = false` maps it to `<Nop>`, a string value remaps it. The overrides are
applied after the adapter's buffer-local keymaps are in place.

## Remapping and disabling

Three levels, from broad to narrow:

```lua
require("filetree").setup({
  -- 1. globally, by key: rename or drop any key across all features
  keymaps = {
    ["gs"]    = "<leader>gs",  -- live_search: gs → <leader>gs
    ["<leader>mc"] = false,    -- marks.keymap_clear: gone
  },

  -- 2. per feature: set the field directly
  features = {
    live_search = { enabled = true, keymap = "<leader>gs" },
  },

  -- 3. per adapter key: noop or remap what neo-tree binds itself
  adapter_keymaps = { ["i"] = false },
})
```

The `keymaps` remap runs *after* all feature configs are merged, so it beats
both the defaults and any per-feature override.

Behavioural autocommands are switched off by feature name:

```lua
require("filetree").setup({
  autocmds = { auto_reveal = false, cwd_sync = false },
})
```

## The `?` cheatsheet

`?` opens filetree's own paged cheatsheet on every adapter, neo-tree included. It
reads what is actually bound (filetree's keys from the registry, everything else
from the buffer), in pages: filetree keys, other keys (the adapter's and other
plugins'), commands, and -- only when two actions claim one key -- conflicts.
`<Tab>` turns the page. See
[the cheatsheet section](BINDINGS/KEYMAPS.md#the--cheatsheet-per-source-keys-conflicts).

`:Filetree keys` resolves a key two actions claim: it recommends free alternatives
and moves the action you pick.
