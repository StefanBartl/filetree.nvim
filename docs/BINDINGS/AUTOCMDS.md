# filetree.nvim — Autocmds

filetree.nvim creates autocmds in two categories:

1. **Keymap setup** — a single `FileType` autocmd (`util.tree_attach`, augroup
   `filetree_tree_attach`) that dispatches to every enabled feature's
   `on_attach(buf)` callback. Every feature with a `keymap*` config field
   registers one of these instead of creating its own `FileType` autocmd.
   Dispatch is deferred with `vim.schedule()` so callbacks fire after the
   adapter (e.g. neotree) finishes its own render-time keymap setup.

2. **Behavioral** — autocmds that drive feature logic (reveal, cwd sync, etc.).
   Listed in the table below.

---

## Behavioral autocmds per feature

| Feature | Event(s) | Trigger | Disable |
|---------|---------|---------|---------|
| `auto_reveal` | `BufEnter` | Reveal current file in tree on buffer switch | `enabled = false` or `autocmds = { auto_reveal = false }` |
| `cwd_sync` | `BufEnter`, `DirChanged` | Sync Vim cwd to current node's directory | `enabled = false` or `autocmds = { cwd_sync = false }` |
| `current_hl` | `BufEnter`, `CursorMoved` | Highlight current-file node in tree | `enabled = false` or `autocmds = { current_hl = false }` |
| `cursor_hide` | `BufEnter`, `WinEnter`, `BufLeave`, `WinLeave` | Hide block cursor in tree window; restore on leave | `enabled = false` |
| `window_style` | tree-attach, `BufWinEnter`, `WinEnter` (statusline); `ColorScheme` (highlights_isolate) | Blank statusline (on by default) / isolate tree highlights (opt-in) in tree windows | `enabled = false` or `statusline = false` / `highlights_isolate = false` |
| `preview` | `BufLeave`, `WinLeave`, `CursorMoved` | Auto-close preview float on leave; live-update on cursor move | `enabled = false` |
| `git_status` | `BufWritePost`, `FocusGained` | Refresh git decorations after write | `enabled = false` |
| `file_watcher` | `User FileWatcherEvent` | Refresh tree on filesystem change | `enabled = false` |
| `session` | `VimLeavePre`, `BufHidden` (tree) | Auto-save/restore project session | `auto_save = false` / `auto_restore = false` |
| `lsp_diagnostics` | `DiagnosticChanged` | Refresh diagnostic decorations | `enabled = false` |
| `breadcrumbs` | `BufEnter`, `CursorMoved` | Update winbar/statusline breadcrumb | `enabled = false` |
| `watcher_quarantine` | `User FileWatcherEvent` | Suppress watcher events during operations | `enabled = false` |

---

## Disabling autocmds

### Disable a specific feature's behavioral autocmds

Use the top-level `autocmds` table — this sets `autocmds_enabled = false` in
the feature config, which behavioral features check before creating their
autocmds:

```lua
require("filetree").setup({
  autocmds = {
    auto_reveal = false,   -- no auto-reveal on BufEnter
    cwd_sync    = false,   -- no cwd tracking
  },
  features = {
    auto_reveal = { enabled = true },  -- feature still active, just no autocmd
  },
})
```

### Disable an entire feature

Set `enabled = false` in the feature config. This skips setup entirely,
including all autocmds and keymaps:

```lua
require("filetree").setup({
  features = {
    auto_reveal = { enabled = false },
  },
})
```

### Delete autocmds after setup

If you need to remove filetree autocmds at runtime (e.g. in a toggle function),
use the Neovim API. The tree-attach keymap-setup autocmd fires once per tree
buffer and its per-feature callbacks are not persistent — only behavioral
autocmds stay active.

```lua
-- Example: disable auto_reveal at runtime
local ft = require("filetree").feature("auto_reveal")
if ft and ft.teardown then ft.teardown() end
```

---

## FileType patterns

The tree-attach dispatcher matches the active adapter's declared `filetypes`
(falling back to the full set below when an adapter doesn't declare any):

| Adapter | FileType |
|---------|---------|
| neotree | `neo-tree` |
| nvimtree | `NvimTree` |
| netrw | `netrw` |
| oil | `oil` |
| mini.files | `minifiles` |
