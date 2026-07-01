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

**Batteries included, opt-out by design.** Every feature is enabled by default — you don't wire anything up, you just `setup()` and get the full keymap set. Turn off what you don't want with `{ enabled = false }`. A short, deliberately-argued list of features stays off until you ask for them (see [Default-disabled features](#default-disabled-features)).

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

All features below are **on by default** unless marked _(opt-in)_ — those few are
listed under [Default-disabled features](#default-disabled-features). Every
tree-buffer key is remappable; see [docs/BINDINGS/KEYMAPS.md](docs/BINDINGS/KEYMAPS.md).

**Navigation & reveal**
| Feature | What it does |
|---|---|
| `picker` | Two-digit overlay to jump to any visible tree node instantly |
| `tree_traverse` | `-` go to parent dir, `+` set dir under cursor as tree root |
| `jump_list` | Back/forward through visited tree nodes (`<C-o>`/`<C-i>`) |
| `quick_open` | Frecency-sorted quick-open picker (`<C-p>`) |
| `reveal_alt` | Reveal the alternate buffer `#` in the tree (`B`) |
| `auto_reveal` | Scroll/highlight the current file in the tree on buffer switch |
| `layout_guard` | Opens an editor window when the tree would be the only window |

**Create / edit / move**
| Feature | What it does |
|---|---|
| `smart_create` | Smart create file or directory with templates (`a`) |
| `copy_move` | Stage copy/cut (`yy`/`xx`) and paste (`p`) nodes |
| `duplicate_node` | Duplicate the node under the cursor (`<C-d>`) |
| `rename_batch` | Edit-buffer batch rename (`R`) |
| `smart_rename` | Rename with LSP reference updates (`<F2>`) |
| `symlink` | Follow / create symlinks (`sl`/`sL`) |
| `create_from_template` | Create a file from a template (`t`) |
| `archive` | Zip / tar.gz the current node (`az`/`at`) |
| `trash` | Cross-platform trash + undo |
| `open_replace` | Open a file replacing the current editor buffer (`O`) |
| `buffer_save` | Force-save adjacent / node buffer (`<C-s>`/`<M-s>`) |

**Search & filter**
| Feature | What it does |
|---|---|
| `filter` | Live tree filter (`/`) |
| `live_search` | Incremental search inside the tree (`gs`) |
| `find_files` | Find files via telescope / fzf-lua / mini.pick / builtin (`f`) |
| `find_or_grep_menu` | Unified find/grep picker menu (`<M-p>`) |
| `grep_in_dir` | Grep in the node's directory (`gr` / `gR` for `<cword>`) |
| `recent_files` | Recent-files picker (`r`) |
| `diagnostics_filter` | Toggle a diagnostics-only filter (`df`) |
| `ignore_patterns` | Toggle ignore-pattern highlighting (`gi`) |

**Info, preview & git**
| Feature | What it does |
|---|---|
| `preview` | Toggle floating preview; dispatch images / PDFs (`<Tab>`/`<CR>`) |
| `node_info` | Node info float (`I`) |
| `size_info` | Show file / directory sizes |
| `breadcrumbs` | Path breadcrumbs for the current node |
| `git_status` | Git status decorations in the tree |
| `git_blame` | Toggle git blame float (`gB`) |
| `lsp_diagnostics` | LSP diagnostic decorations |
| `outline` | LSP symbol outline for the current file (`go`) |

**Marks & organization**
| Feature | What it does |
|---|---|
| `marks` | Toggle marks, batch mark/unmark, show list (`m` `]m` `[m` `<C-m>` `<leader>ms`) |
| `bookmarks` | Toggle bookmarks on nodes (`b`) |
| `pin_node` | Pin the current node (`gp`) |
| `tag_system` | Edit tags for a node (`gt`) |
| `color_labels` | Assign color labels (`cl`) |
| `notes` | Attach notes to nodes (`gn`) |
| `workspace` | Switch workspace root (`gw`) |
| `session` | Persist / restore tree state |

**Paths & clipboard**
| Feature | What it does |
|---|---|
| `path_copy` | Copy absolute/relative path, filename, or pick a format (`[a` `]a` `<leader>yp` `<leader>yn`) |
| `lua_require_copy` | Copy the node as a `require("…")` string (`rq`) |
| `copy_file_list` | Copy recursive file/dir lists (`[f` `]f` `[F` `]F`) |

**System & window**
| Feature | What it does |
|---|---|
| `open_in_fm` | Open the node's directory in the system file manager (`<leader>fm`) |
| `open_with` | Open with a configured external app (`ox`) |
| `open_terminal` | Open a terminal in the node's directory (`T`) |
| `shell_run` | Prompt + run a shell command in the node's directory (`i`) |
| `file_permissions` | Toggle exec bit / chmod / stat (`gx` `gX` `gP`) |
| `window_size_cycler` | Cycle the tree width through presets (`w`) |
| `window_style` | Opt-in blank statusline + isolated tree highlights (both off until configured) |
| `tree_open_keymaps` | Global keys to toggle the tree left/right/float/current _(opt-in)_ |
| `cursor_hide` | Hide the block cursor inside the tree |
| `tree_reset` | `<Esc>` clears preview + filter + live search |
| `diff` / `compare_dirs` | Diff a node (`D`) / compare two directories (`cd`) |

**Infrastructure**
| Feature | What it does |
|---|---|
| `ignore_list` | Hide `.git`, `node_modules`, build artefacts, … (on by default) |
| `project_root` | Shared project-root detection used by other features |
| `file_watcher` / `watcher_quarantine` | Refresh on external FS changes; quarantine noisy watchers |
| `hooks_api` | Programmatic hooks for other code to react to tree events |

### Default-disabled features

These stay **off** until you set `{ enabled = true }`, each for a concrete reason:

| Feature | Why it's opt-in |
|---|---|
| `cwd_sync` | Changes the global cwd automatically on buffer switch — aggressive, and overlaps `auto_reveal` / `tree_traverse` |
| `current_hl` | Purely cosmetic; ships hardcoded colours that only fit some colorschemes |
| `safety` | A backup **API** with no keymaps — enabling it has no visible effect unless other code calls in |
| `auto_resize` | Automatic width management fights the manual `window_size_cycler` (on by default) |
| `git_actions` | Default `gs` collides with `live_search`, and it mutates the git index (stage/unstage) |
| `path_utils` | Redundant with `path_copy` (on by default) — two overlapping path-copy keymap families |
| `harpoon_integration` | Hard-requires the external [harpoon](https://github.com/ThePrimeagen/harpoon) plugin |
| `telescope_integration` | Hard-requires telescope; redundant with the builtin-fallback `find_or_grep_menu` / `find_files` |
| `tree_open_keymaps` | Binds global (not tree-local) normal-mode keys — too opinionated to enable unasked |

---

## Requirements

- Neovim >= 0.8
- [lib.nvim](https://github.com/StefanBartl/lib.nvim) — shared helper library (declared
  dependency; filetree degrades gracefully with local fallbacks if it is missing)
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
    "StefanBartl/lib.nvim",   -- shared helpers (neo-tree node utils, etc.)
    -- only ONE tree plugin is needed:
    "nvim-neo-tree/neo-tree.nvim",
    -- or: "nvim-tree/nvim-tree.lua",
  },
  config = function()
    -- That's it — every feature is on by default.
    require("filetree").setup({ adapter = "neotree" })
  end,
}
```

---

## Quick start

```lua
-- Use event = "VeryLazy" so filetree loads after the tree plugin's config runs.
-- Zero feature wiring needed: everything is enabled by default.
require("filetree").setup({ adapter = "neotree" })
```

Turn things off (or override defaults) only where you want to:

```lua
require("filetree").setup({
  adapter = "neotree",
  features = {
    shell_run  = { enabled = false },          -- disable a default-on feature
    git_actions = { enabled = true },          -- enable a default-off feature
    marks       = { keymap = "M" },            -- keep on, remap its key
  },
})
```

---

## Configuration

**How defaults work:** every feature is enabled unless it appears in
[Default-disabled features](#default-disabled-features). You never write
`enabled = true` to *get* a feature — you only ever write `enabled = false` to
turn one off, or `enabled = true` to switch on one of the opt-in few. Omitting a
feature entirely leaves it at its default (on) with its default options.

```lua
-- Minimal — the full feature set, default keymaps, nothing to wire up:
require("filetree").setup({ adapter = "neotree" })
```

The block below shows the tunable options of a representative selection with
their defaults. `enabled` is shown only to make each feature's default state
explicit — you can drop the line in your own config.

```lua
require("filetree").setup({
  adapter = "auto",   -- "neotree" | "nvimtree" | "auto"

  -- Ignore list: hide common dirs/files from the tree by default.
  -- true (default) → built-in list (.git, node_modules, …)
  -- false          → show everything
  -- string[]       → custom list, overrides the built-in defaults
  ignore_list = true,

  features = {
    -- ── On by default ──────────────────────────────────────────────────────
    picker = {
      enabled     = true,     -- default: on
      index_width = 2,        -- digits per label  (2 → 01..99)
      timeout_ms  = 3000,     -- auto-exit after ms of inactivity
      keymaps = {
        trigger_reveal = "<leader>fp",
        trigger_cwd    = "<leader>fc",
      },
    },

    layout_guard = {
      enabled  = true,        -- default: on
      delay_ms = 50,
    },

    preview = {
      enabled     = true,      -- default: on
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
      enabled = true,   -- default: on — hide block cursor in tree window
    },

    tree_reset = {
      enabled = true,   -- default: on — <Esc> clears preview + filter + live_search
      keymap  = "<Esc>",
    },

    buffer_save = {
      enabled        = true,      -- default: on
      keymap_adjacent = "<C-s>",  -- save last adjacent editor buffer
      keymap_node    = "<M-s>",   -- save buffer matching node under cursor
      force          = true,      -- use write! (vs update)
    },

    window_size_cycler = {
      enabled = true,            -- default: on
      keymap  = "w",
      sizes   = { 30, 50, 15 },  -- normal → large → small → normal
    },

    open_in_fm = {
      enabled = true,            -- default: on
      keymap  = "<leader>fm",    -- open node directory in system file manager
    },

    shell_run = {
      enabled     = true,        -- default: on
      keymap      = "i",         -- prompt + run shell command in node directory
      close_on_ok = true,        -- auto-close terminal when command exits 0
      split       = "split",     -- "split" | "vsplit"
      height      = 12,
    },

    open_replace = {
      enabled = true,  -- default: on
      keymap  = "O",   -- open file replacing current editor buffer
    },

    reveal_alt = {
      enabled = true,  -- default: on
      keymap  = "B",   -- reveal alternate buffer (#) in tree
    },

    window_style = {
      enabled            = true,   -- default: on, but both effects below default off
      statusline         = false,  -- true → blank statusline in tree windows
      highlights_isolate = false,  -- true → link tree HL groups to editor's Normal/NormalNC
    },

    -- ── Off by default (opt-in) ───────────────────────────────────────────
    cwd_sync = {
      enabled       = false,  -- default: off
      debounce_ms   = 150,
      parent_levels = 0,
      keep_focus    = true,
    },

    current_hl = {
      enabled     = false,    -- default: off
      file_hl     = { fg = "#7aa2f7", bold = true },
      parent_hl   = { fg = "#565f89" },
      debounce_ms = 100,
    },

    safety = {
      enabled     = false,    -- default: off (backup API, no keymaps)
      backup_dir  = nil,      -- default: stdpath("data")/filetree/backups
      max_backups = 5,
      dry_run     = false,
    },

    git_actions = {
      enabled = false,        -- default: off (gs collides with live_search)
    },

    tree_open_keymaps = {
      enabled          = false,   -- default: off (binds global keys)
      reveal_force_cwd = false,   -- set tree root to cwd when toggling
      keymaps = {
        left    = "<leader>el",
        right   = "<leader>er",
        float   = "<leader>ef",
        current = "<leader>ec",
      },
    },

    -- auto_resize, path_utils, harpoon_integration, telescope_integration are
    -- also off by default — see "Default-disabled features".
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

> The deep-dives below cover a few core features. For the complete list of
> features and their keys see [Features](#features) above and
> [docs/BINDINGS/KEYMAPS.md](docs/BINDINGS/KEYMAPS.md).

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

> **neo-tree `?` cheatsheet:** filetree keymaps appear there automatically —
> `setup()` injects them into neo-tree's mapping registry, no extra wiring needed.
> For **nvim-tree** (`g?`) and other adapters the keymaps are registered via
> `vim.keymap.set()` in a FileType autocmd (outside their help registry), so their
> built-in help won't list them — they still work; check `:nmap` in the tree
> buffer. See
> [neo-tree `?` cheatsheet integration](docs/BINDINGS/KEYMAPS.md#neo-tree--cheatsheet-integration).

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
