# filetree.nvim — Autocmds

filetree.nvim creates autocmds in two categories:

1. **Keymap setup** — `FileType` callbacks that install tree-buffer keymaps.
   Every enabled feature with a `keymap*` config field registers one of these.
   They are deferred with `vim.schedule()` so they fire after the adapter
   (e.g. neotree) finishes its own render-time keymap setup.

2. **Behavioral** — autocmds that drive feature logic (reveal, cwd sync, etc.).
   Listed in the table below.

---

## Behavioral autocmds per feature

| Feature | Event(s) | Trigger | Disable |
|---------|---------|---------|---------|
| `auto_reveal` | `BufEnter` | Reveal current file in tree on buffer switch | `enabled = false` or `autocmds = { auto_reveal = false }` |
| `cwd_sync` | `BufEnter`, `DirChanged` | Sync Vim cwd to current node's directory | `enabled = false` or `autocmds = { cwd_sync = false }` |
| `current_hl` | `BufEnter`, `CursorMoved` | Highlight current-file node in tree | `enabled = false` or `autocmds = { current_hl = false }` |
| `git_status` | `BufWritePost`, `FocusGained` | Refresh git decorations after write | `enabled = false` |
| `file_watcher` | `User FileWatcherEvent` | Refresh tree on filesystem change | `enabled = false` |
| `recent_files` | `BufReadPost` | Record opened file in recent list | `enabled = false` |
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
use the Neovim API. All filetree keymap-setup autocmds fire once per buffer and
are not persistent — only behavioral autocmds stay active.

```lua
-- Example: disable auto_reveal at runtime
local ft = require("filetree").feature("auto_reveal")
if ft and ft.teardown then ft.teardown() end
```

---

## FileType patterns

Keymap-setup autocmds match the following `FileType` patterns:

| Adapter | FileType |
|---------|---------|
| neotree | `neo-tree` |
| nvimtree | `NvimTree` |
| netrw | `netrw` |
| oil | `oil` |
| mini.files | `minifiles` |
