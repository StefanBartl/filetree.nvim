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
![License](https://img.shields.io/badge/license-MIT-blue)
![Status](https://img.shields.io/badge/status-alpha-orange)

**Adapter-agnostic filetree features for Neovim.** Works with neo-tree.nvim and nvim-tree.lua via a clean adapter interface — swap your tree plugin without losing your features.

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Adapters](#adapters)
- [Feature reference](#feature-reference)
- [Ignore list](#ignore-list)
- [Keymaps](#keymaps)
- [Commands](#commands)
- [Autocmds](#autocmds)
- [Public API](#public-api)
- [Custom adapters](#custom-adapters)
- [Health check](#health-check)
- [Roadmap](#roadmap)

---

## Features

| Feature | What it does |
|---|---|
| **Picker** | Two-digit overlay to jump to any visible tree node instantly |
| **Layout Guard** | Opens an editor window when the tree would be the only window |
| **CWD Sync** | Auto-reveals the current buffer's file in the tree |
| **Current Highlight** | Highlights the active file and its parent directory in the tree |
| **Safety** | Backup API — call before delete/move to keep a copy |

---

## Requirements

- Neovim >= 0.8
- **One** of:
  - [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim)
  - [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)

---

## Installation

**lazy.nvim**

```lua
{
  "StefanBartl/filetree.nvim",
  event = "VeryLazy",   -- must load AFTER the tree plugin's config function runs
  dependencies = {
    -- only ONE of these is needed
    "nvim-neo-tree/neo-tree.nvim",
    -- or: "nvim-tree/nvim-tree.lua",
  },
  config = function()
    require("filetree").setup({
      adapter = "neotree",
      features = {
        picker       = { enabled = true },
        layout_guard = { enabled = true },
      },
    })
  end,
}
```

---

## Quick start

```lua
-- Use event = "VeryLazy" so filetree loads after the tree plugin's config runs.
require("filetree").setup({
  adapter = "neotree",
  features = {
    picker       = { enabled = true },
    layout_guard = { enabled = true },
  },
})
```

---

## Configuration

All options with their defaults:

```lua
require("filetree").setup({
  adapter = "auto",   -- "neotree" | "nvimtree" | "auto"

  -- Ignore list: hide common dirs/files from the tree by default.
  -- true (default) → built-in list (.git, node_modules, …)
  -- false          → show everything
  -- string[]       → custom list, overrides the built-in defaults
  ignore_list = true,

  features = {
    picker = {
      enabled     = true,
      index_width = 2,        -- digits per label  (2 → 01..99)
      timeout_ms  = 3000,     -- auto-exit after ms of inactivity
      keymaps = {
        trigger_reveal = "<leader>fp",
        trigger_cwd    = "<leader>fc",
      },
    },

    layout_guard = {
      enabled  = true,
      delay_ms = 50,
    },

    cwd_sync = {
      enabled       = false,
      debounce_ms   = 150,
      parent_levels = 0,
      keep_focus    = true,
    },

    current_hl = {
      enabled     = false,
      file_hl     = { fg = "#7aa2f7", bold = true },
      parent_hl   = { fg = "#565f89" },
      debounce_ms = 100,
    },

    safety = {
      enabled     = false,
      backup_dir  = nil,      -- default: stdpath("data")/filetree/backups
      max_backups = 5,
      dry_run     = false,
    },

    preview = {
      enabled     = false,
      keymap      = "<Tab>",   -- text/dir: toggle float; image/PDF: dispatch
      keymap_open = "<CR>",    -- image/PDF: dispatch; other: adapter default
      max_lines   = 40,
      image = {
        backend = "auto",     -- "snacks" | "image.nvim" | "system" | false
      },
      pdf = {
        backend = "pdfport",  -- "pdfport" | "system" | false
      },
    },

    cursor_hide = {
      enabled = false,   -- hide block cursor in tree window
    },

    tree_reset = {
      enabled = false,   -- <Esc> clears preview + filter + live_search
      keymap  = "<Esc>",
    },

    buffer_save = {
      enabled        = false,
      keymap_adjacent = "<C-s>",  -- save last adjacent editor buffer
      keymap_node    = "<M-s>",   -- save buffer matching node under cursor
      force          = true,      -- use write! (vs update)
    },

    window_size_cycler = {
      enabled = false,
      keymap  = "w",
      sizes   = { 30, 50, 15 },  -- normal → large → small → normal
    },

    open_in_fm = {
      enabled = false,
      keymap  = "<leader>fm",    -- open node directory in system file manager
    },

    shell_run = {
      enabled     = false,
      keymap      = "i",         -- prompt + run shell command in node directory
      close_on_ok = true,        -- auto-close terminal when command exits 0
      split       = "split",     -- "split" | "vsplit"
      height      = 12,
    },

    open_replace = {
      enabled = false,
      keymap  = "O",   -- open file replacing current editor buffer
    },

    reveal_alt = {
      enabled = false,
      keymap  = "B",   -- reveal alternate buffer (#) in tree
    },
  },

  -- Override the adapter's (neotree/nvim-tree) own native keymaps.
  -- false → <Nop>   string → remap target
  -- Example: noop neotree's built-in `i` (toggle-info) so shell_run can use it
  adapter_keymaps = {
    -- ["i"] = false,
  },
})
```

---

## Adapters

| Name | Plugin | Status |
|---|---|---|
| `"neotree"` | neo-tree.nvim | Supported |
| `"nvimtree"` | nvim-tree.lua | Supported |
| `"auto"` | First available | Default |
| `"netrw"` | Built-in | Planned |
| `"oil"` | oil.nvim | Planned |

---

## Feature reference

### Picker

Overlay two-digit labels on all visible tree nodes.

**Global keymaps (normal mode):**

| Key | Action |
|---|---|
| `<leader>fp` | Picker — reveal current file |
| `<leader>fc` | Picker — open at cwd |

**Inside picker mode:**

| Key | Action |
|---|---|
| `0`–`9` | Build index; complete index opens/toggles node |
| `e` / `s` / `v` / `t` / `p` | Set open mode before digits |
| `<Tab>` | Cycle filter: all → files → folders |
| `<C-k>` / `<C-j>` | Scroll tree |
| `<Esc>` | Exit picker |

### Layout Guard

When all editor windows close, opens a new one automatically. Fires on `BufDelete`, `BufWipeout`, `WinClosed`.

### CWD Sync

Reveals the current buffer file on `BufEnter` / `WinEnter`. Auto-pauses 2 seconds when cursor enters the tree window.

```lua
require("filetree").feature("cwd_sync").pause(5000)
```

### Current Highlight

Creates `FiletreeCurrentFile` and `FiletreeCurrentParent` highlight groups and applies them as extmarks on the tree buffer.

### Safety / Backup

```lua
local safety = require("filetree").feature("safety")
local bak = safety.before_delete("/path/to/file.lua")
safety.before_move("/path/src.lua", "/path/dst.lua")
safety.list_backups()
safety.toggle_dry_run()
```

---

## Public API

```lua
local ft = require("filetree")
ft.setup(config)
ft.adapter()            -- → FiletreeAdapter?
ft.config()             -- → FiletreeConfig
ft.feature("picker")    -- → feature module | nil
ft.register_adapter(a)  -- register custom adapter (before setup)
ft.is_initialized()     -- → boolean
```

---

## Custom adapters

```lua
require("filetree").register_adapter({
  name             = "my_tree",
  is_available     = function() return true end,
  is_open          = function() return false, nil end,
  get_winid        = function() return nil end,
  get_root_path    = function() return nil end,
  get_current_node = function() return nil end,
  get_visible_nodes= function(_f) return {} end,
  get_node_line    = function(_p) return nil end,
  expand_node      = function(_n) return false end,
  collapse_node    = function(_n) return false end,
  open_file        = function(_p,_m) return false end,
  open_reveal      = function(_p,_l) return false end,
  open_cwd         = function() return false end,
  close            = function() return false end,
  refresh          = function() return false end,
  scroll_to_line   = function(_l) return false end,
  highlight_node   = function(_p,_h) return false end,
  unhighlight_node = function(_p) return false end,
})
require("filetree").setup({ adapter = "my_tree" })
```

See [`lua/filetree/@types/adapter.lua`](lua/filetree/@types/adapter.lua) for the full annotated interface.

---

## Ignore list

filetree.nvim hides common filesystem clutter from the tree by default — `.git`,
`node_modules`, build artefacts, caches, and similar. Toggle with the adapter's
native "show hidden" key (neotree: `H`).

```lua
require("filetree").setup({
  -- true (default) — use built-in list; also reads from lib.nvim if available
  ignore_list = true,

  -- false — disable hiding entirely, show all items
  ignore_list = false,

  -- string[] — custom list; overrides the built-in defaults completely
  ignore_list = { ".git", "node_modules", ".venv" },
})
```

**Built-in hidden names** (when `ignore_list = true`):
`.git`, `.github`, `.hg`, `.svn`, `node_modules`, `.pnpm-store`, `.yarn`,
`.venv`, `.direnv`, `__pycache__`, `.mypy_cache`, `.pytest_cache`, `.cache`,
`.sass-cache`, `build`, `dist`, `out`, `target`, `bin`, `obj`, `zig-cache`,
`zig-out`, `.DS_Store`, `thumbs.db`, `.vscode`, `.idea`

**Toggle at runtime** — use your adapter's built-in toggle:

| Adapter | Key | Action |
|---------|-----|--------|
| neo-tree | `H` | `toggle_hidden` — shows/hides all filtered items |
| nvim-tree | `H` | `toggle_dotfiles` |

---

## Keymaps

All tree-buffer keymaps, defaults, and how to remap or disable them:
→ [docs/BINDINGS/KEYMAPS.md](docs/BINDINGS/KEYMAPS.md)

> **filetree.nvim keymaps are not listed in the adapter's `?` cheatsheet.**
> They are registered via `vim.keymap.set()` after the adapter's own setup, so
> neo-tree's `?` / nvim-tree's `g?` will not show them. They do work correctly —
> check `:nmap` in the tree buffer to verify.

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

---

## Commands

Full sub-command reference for `:Filetree` (configurable name):
→ [docs/BINDINGS/USERCOMMANDS.md](docs/BINDINGS/USERCOMMANDS.md)

`:Ft` works out of the box as a short alias for `:Filetree`.

**Rename the command:**

```lua
require("filetree").setup({
  command = { name = "Ft", aliases = { "Filetree" } },
})
```

---

## Autocmds

Which features create behavioral autocmds and how to disable them:
→ [docs/BINDINGS/AUTOCMDS.md](docs/BINDINGS/AUTOCMDS.md)

---

## Health check

```vim
:checkhealth filetree
```

---

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) — planned: netrw/oil adapters, trash/undo, marks, diff, Telescope/fzf integration.

---

MIT © Stefan Bartl
