# Configuration

**How defaults work:** every feature is enabled unless it's marked opt-in in
[docs/FEATURES/](FEATURES/README.md). You never write
`enabled = true` to *get* a feature — you only ever write `enabled = false` to
turn one off, or `enabled = true` to switch on one of the opt-in few. Omitting a
feature entirely leaves it at its default (on) with its default options.

```lua
-- Minimal — the full feature set, default keymaps, nothing to wire up:
require("filetree").setup({ adapter = "neotree" })
```

## Full option reference

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

  -- Style for batch-operation progress indicators (trash, paste, …) — see
  -- "Progress indicators" below. Needs lib.nvim.progress; a no-op without it.
  progress_style = "auto",  -- "auto" | "notify" | "statusline" | "fidget" | "float" | "kit"

  -- Cap on how many nodes one walk of the rendered tree collects. Only a
  -- guard against a single directory expanded with tens of thousands of
  -- entries; the walk is already bounded by what is expanded.
  max_visible_nodes = 5000,

  -- Reference engine: what happens to markdown links and require()/import
  -- statements when a file is renamed, moved or deleted. One block for every
  -- fileops feature — see FEATURES/FILEOPS.md#references for the full story.
  refs = {
    enabled   = true,
    providers = { markdown = true, lua = true, python = true, ts_js = false },
    on_rename = "ask",    -- "ask" (chooser) | "auto" (just do it) | "off"
    on_move   = "ask",
    on_delete = "ask",    -- trash: offer to blank dangling links to REF!
    copy      = false,    -- a copy leaves the original in place: nothing breaks
    picker    = "auto",   -- "auto" | "telescope" | "fzf-lua" | "quickfix"
    prefer_lsp = true,    -- skip the textual code providers when a language
                          -- server already applied a workspace edit
    wiki_links = false,   -- also scan [[wiki]]-style markdown links
    scan = {
      root              = "project",  -- "project" (nearest root) | "cwd"
      respect_gitignore = true,
      max_files         = 5000,       -- cap for the ripgrep-free fallback walk
      timeout_ms        = 3000,
    },
    undo = true,          -- `:Filetree refs undo` reverts the last rewrite
    undo_depth = 10,      -- how many rewrites stay undoable; the stack holds
                          -- only the replaced line content, so raising is cheap
  },

  features = {
    -- ── On by default ──────────────────────────────────────────────────────
    layout_guard = {
      enabled  = true,        -- default: on
      delay_ms = 50,
    },

    buffer_cycle = {
      enabled     = true,        -- default: on
      keymap_next = "<C-n>",     -- next buffer in the adjacent editor window
      keymap_prev = "<C-p>",     -- previous buffer in the adjacent editor window
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
      -- Tree filetypes come from the active adapter's `filetypes` capability
      -- when it declares one (neo-tree, nvim-tree ship it); otherwise a
      -- superset covering all known trees is used as a fallback.
    },

    tree_reset = {
      enabled = true,   -- default: on — <Esc> clears preview + filter + live_search
      keymap  = "<Esc>",
    },

    context_menu = {
      enabled = true,            -- default: on
      keymap  = "<RightMouse>",  -- false disables the trigger without disabling the
                                  -- feature (e.g. to wire your own via
                                  -- filetree.integrations.menu.items() instead)
      -- Soft dependency: opens https://github.com/nvzone/menu at the mouse.
      -- Without it installed, a click degrades to a single notify, not an
      -- error. WHICH entries appear is controlled by the top-level `menu`
      -- config below, not here.
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
      keymap  = "<leader>fm",    -- show node in the system file manager
      reveal  = true,            -- false: open the containing dir without selecting
      -- command = "thunar",     -- launcher override (auto-detected per OS)
      -- reuse_existing = false, -- Windows: navigate an open Explorer window instead
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
      enabled            = true,   -- default: on
      statusline         = true,   -- default: on — blank statusline in tree windows;
                                    -- re-applied on FileType, BufWinEnter, and WinEnter
                                    -- so a statusline plugin re-asserting itself on the
                                    -- same window doesn't win the race
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
      max_cache_entries = 1000,  -- directories held before the cache is cleared in one shot
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

    handle_guard = {
      enabled = false,  -- default: off — patches a neo-tree internal (fs_watch) +
                         -- closes libuv handles it owns, to fix a sporadic Windows
                         -- file-lock at the source (watcher_quarantine only hides
                         -- the error). neo-tree adapter + Windows/WSL only; a no-op
                         -- elsewhere. No keymaps — inspect with `:Filetree handles`.
    },

    tree_integrity = {
      enabled = true,   -- default: on — wraps nui's Tree:set_nodes so neo-tree's
                        -- node index cannot be corrupted by a subtree being
                        -- re-set with live nodes ("Error setting nodes: attempt
                        -- to index local 'node' (a nil value)", repeating on
                        -- every render until the tree is re-opened). No-op on a
                        -- healthy tree; neo-tree adapter only.
      silent  = true,   -- false → debug note whenever a corrupt subtree is healed
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

See [docs/filetree.txt §5.3](../doc/filetree.txt) for the full explanation and a
worked neo-tree example.

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
