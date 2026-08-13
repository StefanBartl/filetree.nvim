# UI

Everything the tree window itself draws or decorates — preview, node info,
breadcrumbs, sizes, cursor/highlight styling, and the right-click context
menu. Backend-agnostic: every feature here works the same regardless of
which adapter (neo-tree/nvim-tree/netrw/oil.nvim/mini.files) is active,
since they operate on the tree buffer rather than a specific plugin's API.

## Preview

Toggles a live preview of the node under the cursor in the adjacent editor
window, or a floating window — updates as the cursor moves, no separate
open action needed. `<Tab>`/`<CR>` dispatch images/PDFs to their own
viewer instead of rendering raw bytes as text; `<PageUp>`/`<PageDown>` page
a long preview without leaving the tree.

- **Module:** `lua/filetree/features/ui/preview/`
- **Keymaps:** `<Tab>`/`<CR>` (open/dispatch), `<PageUp>`/`<PageDown>`
  (scroll) — see [BINDINGS/KEYMAPS.md](../BINDINGS/KEYMAPS.md)

## Node Info

A float (`I`) reporting path, type, size, permission mode, and mtime for
the node under the cursor. For a file: line count. For a directory:
recursive item count plus aggregate size — computed on demand, not kept
live, so it reflects the tree at the moment you press the key.

- **Module:** `lua/filetree/features/ui/node_info/`
- **Keymaps:** `I`

## Breadcrumbs

Shows the path from the tree root down to the current node, so a deeply
nested file's location is legible without scrolling up through every
parent directory.

- **Module:** `lua/filetree/features/ui/breadcrumbs/`

## Size Info

Shows file/directory sizes inline in the tree listing.

- **Module:** `lua/filetree/features/ui/size_info/`

## Window Size Cycler

Cycles the tree window's width through a configured set of presets
(`w`) — a fixed, deliberate step instead of manual `<C-w>` resizing.

- **Module:** `lua/filetree/features/ui/window_size_cycler/`
- **Keymaps:** `w`

## Window Style

A blank statusline for the tree window (adapter-agnostic, on by default)
plus optional isolated tree highlight groups (opt-in), so the tree reads
as a distinct UI region rather than another ordinary buffer.

- **Module:** `lua/filetree/features/ui/window_style/`
- **Config:** isolated highlights are opt-in — see
  [configuration.md](../configuration.md)

## Cursor Hide

Hides the block cursor inside the tree window, resolved adapter-agnostic
via each adapter's own `filetypes` list rather than a single hardcoded
filetype check.

- **Module:** `lua/filetree/features/ui/cursor_hide/`

## Tree Reset

`<Esc>` in one keystroke clears the active preview, any live filter, and
an in-progress live search — the "get back to a plain tree" key.

- **Module:** `lua/filetree/features/ui/tree_reset/`
- **Keymaps:** `<Esc>`

## Opened-buffer Sync

Re-renders the tree whenever a buffer opens or closes, so the tree
plugin's own "this file is open" highlight stays in sync with reality
instead of only updating on the tree's own redraw triggers.

- **Module:** `lua/filetree/features/ui/opened_sync/`

## Current Highlight (opt-in)

Creates two highlight groups — `FiletreeCurrentFile` and
`FiletreeCurrentParent` — and applies them as extmarks on the tree buffer,
so the file backing the active editor window (and its parent directory)
stand out from the rest of the listing. Off by default: the shipped
colours are hardcoded and only suit some colorschemes; enable and
override the highlight groups yourself once you know they fit.

- **Module:** `lua/filetree/features/ui/current_hl/`
- **Config:** `features.current_hl.enabled = true`

## Cheatsheet

A float listing every active tree-buffer keymap, generated from the same
binding table [BINDINGS/KEYMAPS.md](../BINDINGS/KEYMAPS.md) documents —
so a forgotten key is one press away without leaving the tree or opening
a doc file.

- **Module:** `lua/filetree/features/ui/cheatsheet/`

## Context Menu

Right-click (`<RightMouse>`) opens a context menu via
[nvzone/menu](https://github.com/nvzone/menu) — a soft dependency, inert
(no menu, no error) if it isn't installed. See
[docs/menu.md](../menu.md) for the entries offered.

- **Module:** `lua/filetree/features/ui/context_menu/`
- **Keymaps:** `<RightMouse>`
- **Docs:** [menu.md](../menu.md)
