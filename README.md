```
  ███████╗██╗██╗     ███████╗████████╗██████╗ ███████╗███████╗
  ██╔════╝██║██║     ██╔════╝╚══██╔══╝██╔══██╗██╔════╝██╔════╝
  █████╗  ██║██║     █████╗     ██║   ██████╔╝█████╗  █████╗
  ██╔══╝  ██║██║     ██╔══╝     ██║   ██╔══██╗██╔══╝  ██╔══╝
  ██║     ██║███████╗███████╗   ██║   ██║  ██║███████╗███████╗
  ╚═╝     ╚═╝╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝
                              .nvim
```

![Neovim](https://img.shields.io/badge/Neovim-0.8%2B-brightgreen?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-blue?logo=lua)
![Status](https://img.shields.io/badge/status-alpha-orange)

> **Pairs well with [fileops.nvim](https://github.com/StefanBartl/fileops.nvim)** — filetree.nvim gives you the in-tree actions, fileops.nvim handles the heavier file operations. Use them together for a complete file-management workflow.

**Adapter-agnostic filetree features for Neovim.** filetree.nvim works with neo-tree.nvim and nvim-tree.lua (plus netrw, oil.nvim, and mini.files) via a clean adapter interface, so you can swap your tree plugin without losing your features. It ships **batteries included, opt-out by design**: every feature is enabled by default, so you just `setup()` and get the full keymap set, turning off what you don't want with `{ enabled = false }`. A short, deliberately-argued list of features stays off until you ask for them — see [Features](docs/FEATURES/README.md).

Beyond navigation (cwd modes, auto-reveal, tree traversal) and tree UI (preview, node info, breadcrumbs, cheatsheet), it covers file operations (create from template, batch rename, copy/move staging, one-prompt move, trash with undo, and a reference engine that keeps markdown links and `require()`/`import` statements pointing at the right file after every rename or move), search & paths (live filter, find, grep-in-dir, path/require-string copying, markdown link insertion), and integrations (git status decoration, LSP diagnostic rollup, diffing, marks/session persistence, shell commands scoped to a node, opening with external apps or the system file manager, and a PDF bridge to [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)) — see the table below.

| Category | Covers | Docs |
| --- | --- | --- |
| Core | Adapter abstraction, cwd mode/sync, project root, ignore list, hooks API, safety backups | [CORE.md](docs/FEATURES/CORE.md) |
| Backends | neo-tree, nvim-tree, netrw, oil.nvim, mini.files adapters; file watcher, watcher quarantine, handle guard | [BACKENDS.md](docs/FEATURES/BACKENDS.md) |
| Navigation | cwd lock/scope, auto-reveal, auto-resize, tree traversal, buffer cycling | [NAVIGATION.md](docs/FEATURES/NAVIGATION.md) |
| UI | Preview, node info, breadcrumbs, size info, cheatsheet, context menu, window styling | [UI.md](docs/FEATURES/UI.md) |
| Fileops | Smart create, templates, batch rename, smart rename, copy/move staging, move-to-destination, trash + undo, [reference updates](docs/FEATURES/FILEOPS.md#references) (markdown / lua / python / ts-js) | [FILEOPS.md](docs/FEATURES/FILEOPS.md) |
| Search & paths | Filter, find files, grep-in-dir, live search, path/URI/require copying, markdown links, file-list copying | [SEARCH_AND_PATHS.md](docs/FEATURES/SEARCH_AND_PATHS.md) |
| Integrations | Git status, LSP diagnostics, diff, marks, session, shell run, open-with/file-manager, PDF bridge | [INTEGRATIONS.md](docs/FEATURES/INTEGRATIONS.md) |

## Requirements

- Neovim >= 0.8
- [lib.nvim](https://github.com/StefanBartl/lib.nvim) — shared helper library. **Required** for the `:Filetree`/`:Ft` command layer (`lib.nvim.bindings.usercmd.composer`); most other integrations (notify, `find_root`, ...) still degrade gracefully with local fallbacks if it's missing, but the commands themselves won't register without it.
- **One** of [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) or [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)
- Optional CLI tools (`trash-put`/`gio` for the trash feature, `rg` for
  grep-in-dir and the reference scan) — declared in
  [`docs/install.json`](docs/install.json), parsed by lib.nvim's
  [`deps` module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
  A popup explains what's missing the first time `setup()` runs after
  installing filetree.nvim; `:Lib deps show filetree.nvim` repeats it any
  time, also folded into `:checkhealth filetree`. Disable it **right in
  this plugin's own spec**: `require("filetree").setup({ deps_popup = false })`.
  `vim.g.lib_nvim_deps_disable_first_run = true` (every plugin) /
  `vim.g.lib_nvim_deps_disabled_plugins = { "filetree.nvim" }` also still
  work, for turning it off without touching any plugin's config.

## Quick start

```lua
-- lazy.nvim — load AFTER the tree plugin's config runs, e.g. event = "VeryLazy".
-- Zero feature wiring needed: everything is enabled by default.
{
  "StefanBartl/filetree.nvim",
  event = "VeryLazy",
  dependencies = {
    "StefanBartl/lib.nvim",
    "nvim-neo-tree/neo-tree.nvim", -- or: "nvim-tree/nvim-tree.lua"
  },
  opts = { adapter = "neotree" }, -- or leave it out: "auto" detects the tree
}
```

Turn things off (or override defaults) only where you want to:

```lua
require("filetree").setup({
  adapter = "neotree",
  features = {
    shell_run  = { enabled = false },          -- disable a default-on feature
    auto_resize = { enabled = true },          -- enable a default-off feature
    marks       = { keymap = "M" },            -- keep on, remap its key
  },
})
```

For packer.nvim, vim-plug, and mini.deps, see [Installation](docs/installation.md).

## Documentation

- [Installation](docs/installation.md) — requirements and setup for lazy.nvim, packer.nvim, vim-plug, and mini.deps.
- [Configuration](docs/configuration.md) — full option reference, adapter selection, cwd_sync per-adapter behavior, and the ignore list.
- [Features](docs/FEATURES/README.md) — every feature by category, default-disabled features, and deep-dives into the core ones.
- [Keymaps](docs/keymaps.md) — remapping, disabling, which-key integration, and the neo-tree cheatsheet.
- [Commands](docs/commands.md) — the `:Filetree` command tree and its autocmds.
- [API](docs/api.md) — the public Lua API and how to register a custom adapter.
- [Menu integration](docs/menu.md) — using filetree.nvim's actions with nvzone/menu.
- [Troubleshooting](docs/troubleshooting.md) — health check, debug mode, and known adapter caveats.

