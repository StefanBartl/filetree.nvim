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

## Health check

```vim
:checkhealth filetree
```

---

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) — planned: netrw/oil adapters, trash/undo, marks, diff, Telescope/fzf integration.

---

MIT © Stefan Bartl
