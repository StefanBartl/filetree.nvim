# Contributing to filetree.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/filetree.nvim/issues); pull
requests very welcome.

## Getting the repository into a session

Clone it and either symlink the checkout into your plugin directory or add it to
the runtime path directly — after your tree plugin has configured itself:

```lua
vim.opt.rtp:prepend("/path/to/filetree.nvim")
require("filetree").setup({ adapter = "neotree" })
```

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation.
- **A feature never names a backend.** Everything under `features/` talks to the
  adapter interface and nothing else. The moment a feature branches on
  `if adapter == "neotree"`, the whole premise of the plugin is gone. If the
  interface cannot express what a feature needs, extend the interface and
  implement it in all five adapters — that is the cost, and it is the right one.
- **Batteries included, opt-out by design.** A new feature is on by default
  unless there is an argument for why not, and that argument goes in
  [`FEATURES/README.md`](FEATURES/README.md) rather than being implicit in the
  default table.
- **Destructive operations are recoverable.** Trash before delete where a trash
  tool exists, safety backups before a batch rewrite, and a preview plus
  confirmation for anything that touches more than one file.
- **The reference engine rewrites source files.** Anything it changes must be
  matched by a parse, never a loose substring: a rename that also edits an
  unrelated string literal is worse than one that misses a link.
- Commands are registered through `lib.nvim.bindings.usercmd.composer`.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/filetree/adapter/` | One file per backend: neo-tree, nvim-tree, netrw, oil, mini.files |
| `lua/filetree/features/` | Every feature, written against the adapter interface only |
| `lua/filetree/refs/` | The reference engine: markdown, Lua, Python, TypeScript/JavaScript |
| `lua/filetree/bindings/` | The `:Filetree`/`:Ft` route tree, keymaps and autocmds |
| `lua/filetree/config/` | Defaults, the feature table, `setup()` validation |
| `lua/filetree/integrations/` | Soft-dependency bridges (nvzone/menu) |
| `lua/filetree/util/`, `assets/` | Shared helpers and static assets |
| `lua/filetree/health.lua` | `:checkhealth filetree` |
| `docs/` | Everything the README links to |
| `TESTS/` | The spec suite |

## Adding an adapter

[`api.md`](api.md) has the interface. In short: implement every method, including
the ones your backend answers poorly — an honest "not supported" is part of the
contract, and the features branch on capability, not on name. Then add the row to
[`FEATURES/BACKENDS.md`](FEATURES/BACKENDS.md) with what it does and does not
support, measured rather than assumed.

## Adding a feature

1. Write it under `features/`, against the adapter interface.
2. Give it an entry in the feature table with a default, and say in
   [`FEATURES/`](FEATURES/README.md) which category it belongs to and why its
   default is what it is.
3. Give it a keymap that can be remapped or disabled through the same entry.
4. Add a spec under `TESTS/`, including at least one adapter that does *not*
   support what it needs.
5. Document it in the matching `FEATURES/` page and in
   [`BINDINGS.md`](BINDINGS.md).

## Tests

`TESTS/` is a [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
busted-style suite that fakes the adapters, so no tree plugin has to be
installed. [GitHub Actions](../.github/workflows/ci.yml) runs it on every push
and PR to `main`.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a spec, update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why.
