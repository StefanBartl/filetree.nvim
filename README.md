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

Features live in category subfolders under `lua/filetree/features/<category>/` and
the tables below mirror those categories exactly (same order as
`filetree.features.CATEGORY_ORDER`, which also drives `:checkhealth filetree`).
All features are **on by default** unless marked _(opt-in)_ — those are collected
under [Default-disabled features](#default-disabled-features). Every tree-buffer
key is remappable; see [docs/BINDINGS/KEYMAPS.md](docs/BINDINGS/KEYMAPS.md).

**`nav` — navigation & reveal**
| Feature | What it does |
|---|---|
| `tree_traverse` | `-` go to parent dir, `+` set dir under cursor as tree root |
| `reveal_alt` | Reveal the alternate buffer `#` in the tree (`B`) |
| `auto_reveal` | Scroll to (or expand+reveal) the current file in the tree on buffer switch, never changing cwd/root |
| `layout_guard` | Opens an editor window when the tree would be the only window |
| `auto_resize` | Responsive tree width on `VimResized` _(opt-in)_ |
| `cwd_sync` | Silently `chdir` to the current file's project root (nearest `.git` ancestor by default) and root the tree there, then reveal the file _(opt-in)_ |

**`ui` — display**
| Feature | What it does |
|---|---|
| `preview` | Toggle preview in the editor window (live-updates on cursor move) or a float; dispatch images / PDFs (`<Tab>`/`<CR>`); `<PageUp>`/`<PageDown>` page the preview |
| `node_info` | Node info float (`I`): path, type, size, mode, mtime; line count for files, recursive item count + aggregate size for folders |
| `breadcrumbs` | Path breadcrumbs for the current node |
| `size_info` | Show file / directory sizes |
| `window_size_cycler` | Cycle the tree width through presets (`w`) |
| `window_style` | Blank statusline + isolated tree highlights (adapter-agnostic; both effects off until configured) |
| `cursor_hide` | Hide the block cursor inside the tree |
| `tree_reset` | `<Esc>` clears preview + filter + live search |
| `opened_sync` | Re-render the tree on buffer open/close so the tree plugin's opened-file highlights stay in sync |
| `current_hl` | Highlight the current file + parent dir, optional sign-column icon on the focused file _(opt-in)_ |

**`fileops` — create / edit / move**
| Feature | What it does |
|---|---|
| `smart_create` | Smart create file or directory with templates (`a`) |
| `copy_move` | Stage copy/cut (`c`/`x`) and paste (`p`) nodes |
| `rename_batch` | Edit-buffer batch rename (`<leader>rb`) |
| `smart_rename` | Rename with LSP reference updates (`r`) |
| `create_from_template` | Create a file from a template (`t`) |
| `trash` | Cross-platform trash + undo (`d` `U` `<leader>th`); one batch chooser for multi-mark deletes, force-closes the deleted file's buffers |
| `open_replace` | Open a file replacing the current editor buffer (`O`) |
| `open_variants` | Open in split/vsplit/tab, or badd without switching focus (`sg` `sv` `st` `gb`/`<S-CR>`) |
| `buffer_save` | Force-save adjacent / node buffer (`<C-s>`/`<M-s>`) |

**`search` — search & filter**
| Feature | What it does |
|---|---|
| `filter` | Live tree filter (`/`) |
| `live_search` | Incremental search inside the tree (`gs`) |
| `find_files` | Find files via telescope / fzf-lua / mini.pick / builtin (`f`); force telescope specifically with `tf` |
| `grep_in_dir` | Grep in the node's directory (`gr`); force telescope specifically with `tg` |

**`paths` — paths & clipboard**
| Feature | What it does |
|---|---|
| `path_copy` | Copy absolute path / parent dir (`[a` `]a`), or project root / path relative to it (`[R` `]R`) |
| `lua_require_copy` | Copy the node as a `require("…")` string (`rq`) |
| `copy_file_list` | Copy recursive file/dir lists (`[f` `]f` `[F` `]F`) |
| `markdown_links` | Copy current/recursive/marked nodes as Markdown links (`ML` `MR` `MM`) |

**`git`**
| Feature | What it does |
|---|---|
| `git_status` | Git status decorations in the tree |

**`org` — marks & organization**
| Feature | What it does |
|---|---|
| `marks` | Toggle marks, batch mark/unmark, show list (`m` `]m` `[m` `<C-m>` `<leader>ms`) |
| `session` | Persist / restore tree state |

**`system` — external programs**
| Feature | What it does |
|---|---|
| `open_in_fm` | Open the node's directory in the system file manager (`<leader>fm`) |
| `open_with` | Open with a configured external app (`<leader>sm`) |
| `shell_run` | Prompt + run a shell command in the node's directory (`i`) |

**`lsp` — diagnostics & symbols**
| Feature | What it does |
|---|---|
| `lsp_diagnostics` | LSP diagnostic decorations |

**`compare` — diff**
| Feature | What it does |
|---|---|
| `diff` | Diff the current node (`D`) |

**`infra` — plumbing**
| Feature | What it does |
|---|---|
| `ignore_list` | Hide `.git`, `node_modules`, build artefacts, … |
| `project_root` | Shared, cached project-root detection used by cwd_sync and other features |
| `file_watcher` | Refresh the tree on external filesystem changes |
| `watcher_quarantine` | Suppress watcher EPERM noise around file ops (Windows/WSL) |
| `hooks_api` | Programmatic hooks for other code to react to tree events |
| `safety` | Backup API used before destructive ops _(opt-in)_ |

### Default-disabled features

These stay **off** until you set `{ enabled = true }`, each for a concrete reason:

| Feature | Why it's opt-in |
|---|---|
| `cwd_sync` | Changes the global cwd automatically on buffer switch — aggressive. Coexists with `auto_reveal` (both on by default) via `cwd_sync.reveal`; see [docs/filetree.txt](doc/filetree.txt) §5.3 |
| `current_hl` | Purely cosmetic; ships hardcoded colours that only fit some colorschemes |
| `safety` | A backup **API** with no keymaps — enabling it has no visible effect unless other code calls in |
| `auto_resize` | Automatic width management fights the manual `window_size_cycler` (on by default) |

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

filetree.nvim must load **after** your tree plugin's own config runs, so pick a
load point like `event = "VeryLazy"` (lazy.nvim) or place the `setup()` call after
the tree plugin is configured. Only **one** tree plugin is needed; `lib.nvim` is a
declared dependency.

<details open>
<summary><b>lazy.nvim</b></summary>

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
</details>

<details>
<summary><b>packer.nvim</b></summary>

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
</details>

<details>
<summary><b>vim-plug</b></summary>

```vim
Plug 'StefanBartl/lib.nvim'
Plug 'nvim-neo-tree/neo-tree.nvim'   " or: Plug 'nvim-tree/nvim-tree.lua'
Plug 'StefanBartl/filetree.nvim'
```

Then, after neo-tree/nvim-tree is set up (e.g. in an `init.lua` sourced later):

```lua
require("filetree").setup({ adapter = "neotree" })
```
</details>

<details>
<summary><b>mini.deps</b></summary>

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
</details>

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
    auto_resize = { enabled = true },          -- enable a default-off feature
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
  debug   = false,    -- true → show internal debug notifications (troubleshooting)

  -- Ignore list: hide common dirs/files from the tree by default.
  -- true (default) → built-in list (.git, node_modules, …)
  -- false          → show everything
  -- string[]       → custom list, overrides the built-in defaults
  ignore_list = true,

  -- Confirmation prompts for destructive/bulk actions (paste, delete,
  -- rename_batch). Shipped defaults: paste/rename_batch = no prompt,
  -- delete = PROMPTS (trashing is harder to notice/undo than a move or
  -- rename, e.g. from a mis-click or an accidental multi-mark delete).
  -- nil (default) leaves each feature's own default alone. true/false
  -- applies to all three at once; a table applies per action. A feature's
  -- own `features.<name>.confirm`, if you set it explicitly, always wins
  -- over this switch.
  --   confirmations = false                            -- no prompts at all
  --   confirmations = { delete = false }                -- opt out of the delete prompt only
  confirmations = nil,

  features = {
    -- ── On by default ──────────────────────────────────────────────────────
    layout_guard = {
      enabled  = true,        -- default: on
      delay_ms = 50,
    },

    preview = {
      enabled     = true,      -- default: on
      mode        = "buffer",  -- "buffer": show file in the editor window (default)
                               -- "float":  floating window next to the tree
      highlight   = true,      -- syntax/treesitter highlighting in the preview
      keymap      = "<Tab>",   -- text/dir: toggle preview; image/PDF: dispatch
      keymap_open = "<CR>",    -- image/PDF: dispatch; other: adapter default
      max_lines   = 40,        -- float mode: lines to read
      max_width   = 80,        -- float mode
      max_height  = 25,        -- float mode
      wrap        = false,     -- float mode: line wrapping
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
      enabled          = false,  -- default: off
      debounce_ms      = 150,
      parent_levels    = 0,     -- how far the tree-reveal call itself ascends
      keep_focus       = true,  -- keep focus in the editor window after reveal
      change_dir       = true,  -- actually chdir to the target dir — never prompts
      reveal           = true,  -- also reveal/root the tree ourselves. Set to FALSE only if
                                -- your adapter's underlying plugin already follows the cwd on
                                -- its own (neo-tree bind_to_cwd+follow_current_file, nvim-tree
                                -- update_focused_file) — otherwise the two reveals fight and
                                -- the tree lands on the file's parent. netrw/oil/mini_files have
                                -- no such native feature — leave this true for them. See the
                                -- per-adapter table below.
      use_project_root = true,  -- target the detected project root, not just the file's dir
      root_markers     = { ".git" },  -- anchor the cwd to the nearest ancestor holding one
                                      -- of these (cached per-dir); avoids frequent cwd jumps.
                                      -- Pass a bigger list to widen it, or false to disable
                                      -- (then falls back to use_project_root / parent dir).
    },

    project_root = {
      enabled  = true,   -- default: on
      markers  = { ".git", "package.json", "Cargo.toml", "go.mod", "*.rockspec", --[[ … ]] },
      fallback = "parent",  -- "parent" (the file's own dir) | "cwd", used when no marker is found
      cache    = true,      -- cache resolved roots per directory for the session (see below)
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

    -- auto_resize is also off by default — see "Default-disabled features".
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
| `"netrw"` | Built-in | Supported |
| `"oil"` | oil.nvim | Supported |
| `"mini_files"` | mini.files | Supported |
| `"auto"` | First available, tried in the order above | Default |

### cwd_sync `reveal` per adapter

Whether `cwd_sync.reveal` should be `true` or `false` depends on whether the
underlying tree **plugin** (not filetree.nvim) has its own built-in feature
that follows the current buffer independently of filetree — when it does, that
feature and cwd_sync's own reveal race each other on every buffer switch:

| Adapter | Native "follow cwd" feature | `reveal` |
|---|---|---|
| `neotree` | `filesystem.follow_current_file.enabled` + `filesystem.bind_to_cwd = true` | `false` |
| `nvimtree` | `update_focused_file.enable = true` (leave `update_root` at its default `false` — see caveat) | `false` |
| `netrw` | none | `true` (default) |
| `oil` | none | `true` (default) |
| `mini_files` | none | `true` (default) |

For `netrw`/`oil`/`mini_files` cwd_sync's own reveal is the only thing that
does this job — leaving `reveal = false` there means switching to a file in a
different project never gets revealed at all.

> **Caveat (tested):** nvim-tree's `update_focused_file.update_root.enable` is
> *not* a drop-in equivalent of neo-tree's `bind_to_cwd`. neo-tree's
> `bind_to_cwd` is reactive — it just follows whatever cwd cwd_sync already set.
> nvim-tree's `update_root` actively drives the cwd itself, falling back to
> **the file's own directory** (not a project root) when nothing else matches —
> so with it enabled, nvim-tree overwrites cwd_sync's git-root-anchored cwd on
> every switch, regardless of `reveal`. Leave `update_root` at its default
> `false` if you want `root_markers` to win.

See [docs/filetree.txt §5.3](doc/filetree.txt) for the full explanation and a
worked neo-tree example.

---

## Feature reference

> The deep-dives below cover a few core features. For the complete list of
> features and their keys see [Features](#features) above and
> [docs/BINDINGS/KEYMAPS.md](docs/BINDINGS/KEYMAPS.md).

### Layout Guard

When all editor windows close, opens a new one automatically. Fires on `BufDelete`, `BufWipeout`, `WinClosed`.

### CWD Sync

On `BufEnter` / `WinEnter`: silently `chdir` to the current file's project
root — resolved via `root_markers` (default `{ ".git" }`, cached), falling
back to `use_project_root` (the broader [project_root](#infra--plumbing)
marker set) and then the file's own parent directory. Never prompts.
Auto-pauses 2 seconds when the cursor enters the tree window (manual
navigation).

With `reveal = true` (the default) the tree is also rooted at that same
directory and the file revealed there. See
[cwd_sync `reveal` per adapter](#cwd_sync-reveal-per-adapter) above for when to
set `reveal = false` instead.

```lua
require("filetree").feature("cwd_sync").pause(5000)
```

**neo-tree's own "File not in cwd?" prompt is suppressed automatically.**
neo-tree has a native confirm prompt that fires whenever a reveal is
requested (explicitly, or implicitly via `filesystem.follow_current_file`)
without an explicit `dir` and the target file isn't under the tree's current
root — and this can be triggered by *any* code calling neo-tree's command API,
not just filetree.nvim, including your own custom keymaps. As soon as
`require("filetree").setup({ adapter = "neotree" })` runs, filetree.nvim wraps
neo-tree's `command.execute` once so this prompt can never fire — every
at-risk call gets `reveal_force_cwd = true` applied automatically, while a
call that already sets `dir`, `reveal_force_cwd`, or an explicit
`reveal = false` is left untouched. No configuration needed.

### Project Root

Walks up from a file/directory looking for any of `markers` (`.git`,
`package.json`, `Cargo.toml`, `go.mod`, … — a broad default list covering most
ecosystems), returning the deepest directory that has one. Falls back to the
file's own parent directory (or cwd, if `fallback = "cwd"`) when nothing is
found.

Every directory resolved is cached for the session (not just the query
directory — every intermediate directory walked past en route to a found
root is cached too), so repeated lookups for files in the same project don't
re-walk the filesystem. Disable with `cache = false`, or clear it manually if
a `.git` gets added/removed under an already-visited directory:

```lua
require("filetree").feature("project_root").clear_cache()
require("filetree").feature("project_root").add_markers({ ".myproject" })  -- also clears the cache
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
ft.feature("marks")     -- → feature module | nil
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

**Machine-readable catalog:** [docs/BINDINGS.lua](docs/BINDINGS.lua) returns every
keymap, `:Filetree` sub-command and autocmd as data
(`require("filetree.bindings").catalog()`), sourced from `lua/filetree/bindings/`
and the command dispatcher so it never drifts.

**which-key:** if [which-key.nvim](https://github.com/folke/which-key.nvim) is
installed, `setup()` registers leader-group labels automatically (v2 and v3 APIs);
individual tree keys carry a `desc` so which-key shows them out of the box.

> **neo-tree `?` cheatsheet:** filetree keymaps appear there automatically —
> `setup()` injects them into neo-tree's mapping registry, no extra wiring needed.
> For **nvim-tree** (`g?`) and other adapters the keymaps are registered via
> `vim.keymap.set()` in a FileType autocmd (outside their help registry), so their
> built-in help won't list them — they still work; check `:nmap` in the tree
> buffer. See
> [neo-tree `?` cheatsheet integration](docs/BINDINGS/KEYMAPS.md#neo-tree--cheatsheet-integration).
>
> Inside the neo-tree `?` help popup, filetree restores `/` to Neovim's **native
> search** (neo-tree otherwise maps `/` to run the tree filter), so you can search
> the cheatsheet text and page matches with `n`/`N`.

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

## Menu (nvzone/menu)

filetree.nvim ships a context menu for [nvzone/menu](https://github.com/nvzone/menu)
but does **not** depend on it. The plugin *owns* its entries — create, rename,
copy/cut/paste, trash, open variants, path/markdown-link copy, find/grep, node
info — and a host composes them for the tree window:

```lua
local ft = require("filetree.integrations.menu")

-- inline entries for the current node (empty when disabled):
local items = ft.items()            -- { { name, cmd, rtxt }, … }

-- or a single fly-out entry:
local sub = ft.submenu()            -- { name = "  Filetree", items = {…} } | nil

-- e.g. a RightMouse handler for the tree window:
--   require("menu").open(ft.items(), { mouse = true })
```

Entries are self-gating: an action whose feature is disabled is omitted, and
whole groups can be turned off. nvzone closes the menu before running an entry,
so the tree node under the cursor is the active context — exactly as if the
keymap had been pressed. Opt-out per group via `config.menu`:

```lua
require("filetree").setup({
  menu = {
    enable    = true,
    fileops   = true, -- create / rename / batch rename / template
    clipboard = true, -- copy / cut / paste
    delete    = true, -- trash
    open      = true, -- vsplit / split / tab / system app / file manager
    paths     = true, -- copy path / markdown link
    search    = true, -- find files / grep in dir
    info      = true, -- node info
  },
})
```

---

## Health check

```vim
:checkhealth filetree
```

---

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) — planned: netrw/oil adapters, trash/undo, marks, diff, Telescope/fzf integration.
