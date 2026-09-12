# Installation

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
| [nvzone/menu](https://github.com/nvzone/menu) | Renders the context menu if installed; `lib.nvim.ui.kit.menu` draws it otherwise, so right-click works either way — see [Integrations](integrations.md) |

The CLI tools above are declared in [install.json](install.json) and read by
lib.nvim's
[deps module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
A popup explains what is missing the first time `setup()` runs after
installing; `:Lib deps show filetree.nvim` repeats it any time, and it is
folded into `:checkhealth filetree`. Turn the popup off in this plugin's own
spec with `deps_popup = false`, or globally with
`vim.g.lib_nvim_deps_disable_first_run = true`.

## Installation methods

filetree.nvim must load **after** your tree plugin's own config runs, so pick a
load point like `event = "VeryLazy"` (lazy.nvim) or place the `setup()` call after
the tree plugin is configured. Only **one** tree plugin is needed; `lib.nvim` is a
declared dependency.

### lazy.nvim

```lua
{
  "StefanBartl/filetree.nvim",
  event = "VeryLazy",   -- load AFTER the tree plugin's config function runs
  dependencies = {
    "StefanBartl/lib.nvim",        -- shared helpers
    "nvim-neo-tree/neo-tree.nvim", -- or: "nvim-tree/nvim-tree.lua"
  },
  config = function()
    require("filetree").setup({ adapter = "neotree" })
  end,
}
```

### packer.nvim

```lua
use {
  "StefanBartl/filetree.nvim",
  after    = "neo-tree.nvim",   -- ensure the tree plugin is configured first
  requires = {
    "StefanBartl/lib.nvim",
    "nvim-neo-tree/neo-tree.nvim", -- or: "nvim-tree/nvim-tree.lua"
  },
  config = function()
    require("filetree").setup({ adapter = "neotree" })
  end,
}
```

### vim-plug

```vim
Plug 'StefanBartl/lib.nvim'
Plug 'nvim-neo-tree/neo-tree.nvim'   " or: Plug 'nvim-tree/nvim-tree.lua'
Plug 'StefanBartl/filetree.nvim'
```

Then, after neo-tree/nvim-tree is set up (e.g. in an `init.lua` sourced later):

```lua
require("filetree").setup({ adapter = "neotree" })
```

### mini.deps

```lua
local add, now = MiniDeps.add, MiniDeps.now
add({
  source  = "StefanBartl/filetree.nvim",
  depends = { "StefanBartl/lib.nvim", "nvim-neo-tree/neo-tree.nvim" },
})
now(function()
  require("filetree").setup({ adapter = "neotree" })
end)
```

## See also

- [Configuration](configuration.md) — full option reference and adapter selection.
- [Quick start](../README.md#quick-start) — the shortest possible setup snippet.
