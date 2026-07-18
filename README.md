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

**Adapter-agnostic filetree features for Neovim.** filetree.nvim works with neo-tree.nvim and nvim-tree.lua (plus netrw, oil.nvim, and mini.files) via a clean adapter interface, so you can swap your tree plugin without losing your features. It ships **batteries included, opt-out by design**: every feature is enabled by default, so you just `setup()` and get the full keymap set, turning off what you don't want with `{ enabled = false }`. A short, deliberately-argued list of features stays off until you ask for them — see [Default-disabled features](docs/features.md#default-disabled-features).

## Requirements

- Neovim >= 0.8
- [lib.nvim](https://github.com/StefanBartl/lib.nvim) — shared helper library (declared dependency; filetree degrades gracefully with local fallbacks if it is missing)
- **One** of [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) or [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)

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
  config = function()
    require("filetree").setup({ adapter = "neotree" })
  end,
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
- [Features](docs/features.md) — every feature by category, default-disabled features, and deep-dives into the core ones.
- [Keymaps](docs/keymaps.md) — remapping, disabling, which-key integration, and the neo-tree cheatsheet.
- [Commands](docs/commands.md) — the `:Filetree` command tree and its autocmds.
- [API](docs/api.md) — the public Lua API and how to register a custom adapter.
- [Menu integration](docs/menu.md) — using filetree.nvim's actions with nvzone/menu.
- [Troubleshooting](docs/troubleshooting.md) — health check, debug mode, and known adapter caveats.

**Roadmap:** planned work includes trash/undo polish, more marks features, diff improvements, and deeper Telescope/fzf integration; see `docs/ROADMAP/` for internal design notes.
