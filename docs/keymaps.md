# Keymaps

All tree-buffer keymaps, defaults, and how to remap or disable them:
→ [docs/BINDINGS/KEYMAPS.md](BINDINGS/KEYMAPS.md)

**Machine-readable catalog:** [docs/BINDINGS.lua](BINDINGS.lua) returns every
keymap, `:Filetree` sub-command and autocmd as data
(`require("filetree.bindings").catalog()`), sourced from `lua/filetree/bindings/`
and the command dispatcher so it never drifts.

**which-key:** if [which-key.nvim](https://github.com/folke/which-key.nvim) is
installed, `setup()` registers leader-group labels automatically (v2 and v3 APIs);
individual tree keys carry a `desc` so which-key shows them out of the box.

> **`?` cheatsheet:** filetree's own paged cheatsheet (filetree keys, other keys,
> commands, and -- when two actions claim one key -- conflicts; `<Tab>` turns the
> page) is bound on every adapter, neo-tree included, and reads the keys that are
> actually bound. `:Filetree keys` moves a doubly-claimed key. See
> [the cheatsheet section](BINDINGS/KEYMAPS.md#the--cheatsheet-per-source-keys-conflicts).

## Remap filetree feature keys:

```lua
require("filetree").setup({
  keymaps = {
    ["gs"]    = "<leader>gs",   -- rename live_search key
    ["<leader>mc"] = false,     -- disable marks clear
    ["<Tab>"] = "<leader>pv",   -- move preview to <leader>pv
  },
})
```

## Noop an adapter (neotree) built-in key:

```lua
require("filetree").setup({
  -- disable neotree's native `i` (toggle node info) so shell_run can use it
  adapter_keymaps = { ["i"] = false },
  features = {
    shell_run = { enabled = true, keymap = "i" },
  },
})
```
