# Installation

## Requirements

- Neovim >= 0.8
- [lib.nvim](https://github.com/StefanBartl/lib.nvim) — shared helper library (declared
  dependency; filetree degrades gracefully with local fallbacks if it is missing)
- **One** of:
  - [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim)
  - [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)

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
