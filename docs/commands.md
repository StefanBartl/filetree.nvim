# Commands

Full sub-command reference for `:Filetree` (configurable name):
→ [docs/BINDINGS/USERCOMMANDS.md](BINDINGS/USERCOMMANDS.md)

`:Ft` works out of the box as a short alias for `:Filetree`.

**Rename the command:**

```lua
require("filetree").setup({
  command = { name = "Ft", aliases = { "Filetree" } },
})
```

## Autocmds

Which features create behavioral autocmds and how to disable them:
→ [docs/BINDINGS/AUTOCMDS.md](BINDINGS/AUTOCMDS.md)
