> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# filetree.nvim

```
  ███████╗██╗██╗     ███████╗████████╗██████╗ ███████╗███████╗
  ██╔════╝██║██║     ██╔════╝╚══██╔══╝██╔══██╗██╔════╝██╔════╝
  █████╗  ██║██║     █████╗     ██║   ██████╔╝█████╗  █████╗
  ██╔══╝  ██║██║     ██╔══╝     ██║   ██╔══██╗██╔══╝  ██╔══╝
  ██║     ██║███████╗███████╗   ██║   ██║  ██║███████╗███████╗
  ╚═╝     ╚═╝╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝
                              .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)

**Adapter-agnostic filetree features for Neovim.** Your features live here, your
tree plugin stays swappable.

filetree.nvim works with neo-tree.nvim and nvim-tree.lua — plus netrw, oil.nvim
and mini.files — through one adapter interface, so changing tree plugins costs
you the plugin, not the workflow you built on top of it.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Integrations](#integrations)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

- [Installation](docs/installation.md) — requirements and setup for every plugin manager.
- [Configuration](docs/configuration.md) — the full option reference, adapter selection, per-adapter `cwd_sync` behaviour, and the ignore list.
- [Features](docs/FEATURES/README.md) — every feature by category, the default-disabled ones, and deep dives into the core.
- [Keymaps](docs/keymaps.md) — remapping, disabling, which-key integration, and the neo-tree cheatsheet.
- [Commands](docs/commands.md) — the `:Filetree` command tree and its autocmds.
- [Lua API](docs/api.md) — the public API, and how to register a custom adapter.
- [Menu integration](docs/menu.md) — using filetree.nvim's actions with nvzone/menu.
- [Bindings](docs/BINDINGS.md) — the entry point to every keymap, subcommand and autocommand, and which detail page holds what.
- [Workflow](docs/WORKFLOW.md) — how the features combine once several are on at the same time.
- [Troubleshooting](docs/troubleshooting.md) — health check, debug mode, and the known adapter caveats.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add an adapter or a feature.

`:help filetree` is the same reference inside the editor.

---

## What it does

Tree plugins disagree about almost everything except what a tree is for. Every
feature you build on top of one — reveal, preview, a rename that fixes the
imports pointing at the file — is written against that plugin's internals and
dies with it.

filetree.nvim puts those features behind an adapter interface instead. Five
backends implement it; the features never learn which one answered.

It ships **batteries included, opt-out by design**: every feature is enabled by
default, so `setup()` gives you the full keymap set and you turn off what you do
not want with `{ enabled = false }`. A short, deliberately argued list stays off
until you ask — see [Features](docs/FEATURES/README.md).

| Category | Covers | Docs |
| --- | --- | --- |
| Core | Adapter abstraction, cwd mode and sync, project root, ignore list, hooks API, safety backups | [CORE.md](docs/FEATURES/CORE.md) |
| Backends | neo-tree, nvim-tree, netrw, oil.nvim, mini.files adapters; file watcher, watcher quarantine, handle guard | [BACKENDS.md](docs/FEATURES/BACKENDS.md) |
| Navigation | cwd lock and scope, auto-reveal, auto-resize, tree traversal, buffer cycling | [NAVIGATION.md](docs/FEATURES/NAVIGATION.md) |
| UI | Preview, node info, breadcrumbs, size info, cheatsheet, context menu, window styling | [UI.md](docs/FEATURES/UI.md) |
| Fileops | Smart create, templates, batch rename, smart rename, copy/move staging, move-to-destination, trash with undo, [reference updates](docs/FEATURES/FILEOPS.md#references) | [FILEOPS.md](docs/FEATURES/FILEOPS.md) |
| Search and paths | Filter, find files, grep-in-dir, live search, path/URI/require copying, markdown links, file-list copying | [SEARCH_AND_PATHS.md](docs/FEATURES/SEARCH_AND_PATHS.md) |
| Integrations | Git status, LSP diagnostics, diff, marks, session, shell run, open-with and file manager, PDF bridge | [INTEGRATIONS.md](docs/FEATURES/INTEGRATIONS.md) |

The reference engine is the part that is hard to get elsewhere: rename or move a
file and the markdown links, `require()` calls and `import` statements pointing
at it are rewritten to match — for markdown, Lua, Python and TypeScript/JavaScript.

---

## Around it

> **[fileops.nvim](https://github.com/StefanBartl/fileops.nvim)** — the same file
> operations without a tree in front of them, from any buffer. It fires
> `User FileopsChanged`, which this plugin's watcher picks up, so the two stay in
> agreement without depending on each other.
>
> **[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)** — the PDF bridge:
> a `.pdf` node opens rendered in a buffer instead of shelling out to a system
> reader.
>
> **[images.nvim](https://github.com/StefanBartl/images.nvim)** — the same idea
> for image nodes in the preview pane.
>
> **[reposcope.nvim](https://github.com/StefanBartl/reposcope.nvim)** — clones a
> repository; this is how you read it afterwards without leaving Neovim.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) and one tree plugin are the
> real dependencies — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** — `vim.system()` and `vim.uv` are used unguarded, and lib.nvim itself requires 0.10 |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — the `:Filetree`/`:Ft` command layer is built on `usercmd.composer`. Most other uses (notify, `find_root`) have local fallbacks, but the commands do not register without it |
| One of [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) or [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua) | required — netrw, oil.nvim and mini.files are supported as additional adapters, not as the primary one |

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| `trash-put` / `gio` | The trash feature; without one, delete is a real delete |
| `rg` (ripgrep) | Grep-in-dir and the reference scan |
| [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) | `.pdf` nodes rendered into a buffer |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | Labels for the keymap set |
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries — see [Integrations](#integrations) |

The CLI tools are declared in [docs/install.json](docs/install.json) and read by
lib.nvim's
[deps module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
A popup explains what is missing the first time `setup()` runs after installing;
`:Lib deps show filetree.nvim` repeats it any time, and it is folded into
`:checkhealth filetree`. Turn the popup off in this plugin's own spec with
`deps_popup = false`, or globally with
`vim.g.lib_nvim_deps_disable_first_run = true`.

---

## Installation

```lua
-- lazy.nvim — load AFTER the tree plugin's own config runs.
{
  "StefanBartl/filetree.nvim",
  event = "VeryLazy",
  dependencies = {
    "StefanBartl/lib.nvim",
    "nvim-neo-tree/neo-tree.nvim", -- or: "nvim-tree/nvim-tree.lua"
  },
  opts = { adapter = "neotree" },  -- or omit it: "auto" detects the tree
}
```

`event = "VeryLazy"` matters here: the adapter attaches to the tree plugin, so
this has to load after that plugin has configured itself. No feature wiring is
needed — everything is on by default.

packer.nvim, vim-plug and mini.deps are in
[docs/installation.md](docs/installation.md).

---

## Quickstart

Install it, open your tree, and the full keymap set is already bound — that is
the whole point of opt-out defaults. `?` in the tree shows what is available in
the buffer you are in.

Then turn off what you do not want, and turn on what stays off by default:

```lua
require("filetree").setup({
  adapter = "neotree",
  features = {
    shell_run   = { enabled = false }, -- disable a default-on feature
    auto_resize = { enabled = true },  -- enable a default-off feature
    marks       = { keymap = "M" },    -- keep it on, remap its key
  },
})
```

Verify your setup any time with:

```vim
:checkhealth filetree
```

---

## What you get with the defaults

Every feature is on unless [FEATURES/README.md](docs/FEATURES/README.md) lists it
as default-off. The ones worth knowing on day one:

| In the tree | Does |
| --- | --- |
| `?` | The cheatsheet for the buffer you are in |
| Auto-reveal | The tree follows the buffer you switch to |
| Preview | The node under the cursor, without opening it |
| Smart rename | Rename, and rewrite the markdown links, `require()`s and `import`s pointing at it |
| Batch rename | The same, over a whole directory, with a preview |
| Trash | Delete through `trash-put`/`gio`, with undo |
| Copy path | The path, URI, or `require` string for the node |
| Grep in dir | ripgrep, scoped to the node under the cursor |

The full set is [docs/BINDINGS.md](docs/BINDINGS.md); the `:Filetree` command
tree is [docs/commands.md](docs/commands.md).

---

## Integrations

### Other file plugins

[fileops.nvim](https://github.com/StefanBartl/fileops.nvim)'s
`User FileopsChanged` event is picked up by the watcher, so a rename made outside
the tree refreshes it. `.pdf` nodes open through
[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) when it is installed.
Git status decoration and LSP diagnostic rollup attach to whatever is already
providing them. See
[docs/FEATURES/INTEGRATIONS.md](docs/FEATURES/INTEGRATIONS.md).

### Context menu

filetree.nvim contributes context-aware entries in the shape
[nvzone/menu](https://github.com/nvzone/menu) expects, acting on the node under
the cursor. filetree.nvim has **no** dependency on `menu` and never opens a
context menu itself; a host — typically your own `<RightMouse>` dispatcher —
composes them into its own menu. The wiring is
[docs/menu.md](docs/menu.md).

---

## Health check

```vim
:checkhealth filetree
```

Reports which adapter resolved and why, whether `lib.nvim` is present, which
optional CLI tools are reachable, and which features are enabled or gated off.
Debug mode and the known adapter caveats are in
[docs/troubleshooting.md](docs/troubleshooting.md).

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the project
layout; [docs/api.md](docs/api.md) is the adapter interface a sixth backend has
to implement.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/filetree.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/filetree.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
