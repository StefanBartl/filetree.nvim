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

> **neo-tree `?` cheatsheet:** filetree keymaps appear there automatically —
> `setup()` injects them into neo-tree's mapping registry, no extra wiring needed.
> For **nvim-tree** (`g?`) and other adapters the keymaps are registered via
> `vim.keymap.set()` in a FileType autocmd (outside their help registry), so their
> built-in help won't list them — they still work; check `:nmap` in the tree
> buffer. See
> [neo-tree `?` cheatsheet integration](BINDINGS/KEYMAPS.md#neo-tree--cheatsheet-integration).
>
> Inside the neo-tree `?` help popup, filetree restores `/` to Neovim's **native
> search** (neo-tree otherwise maps `/` to run the tree filter), so you can search
> the cheatsheet text and page matches with `n`/`N`.

**Remap filetree feature keys:**

```lua
require("filetree").setup({
  keymaps = {
    ["gs"]    = "<leader>gs",   -- rename live_search key
    ["<C-m>"] = false,          -- disable marks clear
    ["<Tab>"] = "<leader>pv",   -- move preview to <leader>pv
  },
})
```

**Noop an adapter (neotree) built-in key:**

```lua
require("filetree").setup({
  -- disable neotree's native `i` (toggle node info) so shell_run can use it
  adapter_keymaps = { ["i"] = false },
  features = {
    shell_run = { enabled = true, keymap = "i" },
  },
})
```
