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

A symlink's Type line says so (`file (symlink)`) and gets its own `Link to:`
line naming the target — flagged `(broken — target missing)` when the
target does not resolve, rather than the whole window falling back to "No
stat info" the way it used to (a plain `stat` alone sees nothing at all
through a dangling link). A file with more than one hard-linked name gets a
`(hardlink, N names)` note on its Type line instead: every one of its names
is an equal hard link, so this reads as "shares its data with N-1 other
name(s)", not "this one IS the hard link" — there is no single dirent to
single out that way.

- **Module:** `lua/filetree/features/ui/node_info/`
- **Keymaps:** `I`

## Link Marker

Marks a symlinked node in the tree listing so it reads differently from an
ordinary file/directory at a glance: a small `⇢` sign right before the
node's own name (`⇢!` for a symlink whose target could not be resolved),
optionally followed by its target at the end of the line when
`show_target = true`. The sign's position is found fresh per render, as the
byte offset of the node's own name on the line — past whatever indent,
tree-guide characters and icon the backend drew, not a fixed offset — so it
lines up correctly regardless of nesting depth or indent width, and never
splices into the middle of a guide line.

**On by default**, unlike most decorators here — it costs nothing extra per
render: it reads `is_link`/`link_to`/`link_broken` straight off data the
neo-tree and nvim-tree adapters already hold (neo-tree's own scan already
calls `uv.fs_readlink()` for every link it finds), not a filesystem `stat`
per node.

**Hard links are not decorated here.** Telling a file with more than one
name apart from an ordinary one needs an actual `stat`, and every one of
its names is an equal hard link — there is no single dirent to flag as *the*
hard link. See Node Info's `I` window for that instead, on demand rather
than on every rendered line.

**Backend support.** Same line-resolved-decoration contract as `size_info`
below: neo-tree and nvim-tree draw it, netrw/oil.nvim/mini.files don't.
Whether a dangling symlink gets its own `broken` sign also depends on the
backend: neo-tree already knows (it tried to resolve the link during its
own scan); nvim-tree does not expose that, so there a symlink always gets
the plain sign, working or not.

- **Module:** `lua/filetree/features/ui/link_marker/`
- **Config:** `opts.features.link_marker` — `show_target` (default **false**), `target_hl` (`"Comment"`), `signs.symlink` (`{text="⇢", hl="Special"}`), `signs.broken` (`{text="⇢!", hl="DiagnosticError"}`)

## Breadcrumbs

Shows the path from the tree root down to the current node, so a deeply
nested file's location is legible without scrolling up through every
parent directory.

**Sharing the winbar.** In `"winbar"` mode (the default) the trail is
written to every non-tree, non-floating window — and `vim.wo.winbar` is a
surface with no notion of an owner. `my.nvim`'s breadcrumbs put a symbol
trail in the same place, and ui.nvim's `ui.winbar.set()` exists to arbitrate
exactly that. This feature always goes through it, so the two no longer
overwrite each other. Use `mode = "float"` or `mode = "statusline"` to stay
off the surface entirely.

- **Module:** `lua/filetree/features/ui/breadcrumbs/`

## Size Info

Shows file/directory sizes inline in the tree listing.

**Off by default, opt-in** — purely cosmetic, and `dir_async` runs
`du`/`Get-ChildItem` per directory node once it renders, which is not
something to spring on someone who just wanted a tree.

**Backend support.** Drawn as extmarks on the node's own line, which needs
the adapter to say which node a given line holds (`get_node_at_line`). The
neo-tree and nvim-tree adapters implement it; netrw, oil and mini.files do
not, so this renders nothing there rather than misplacing anything.

- **Module:** `lua/filetree/features/ui/size_info/`
- **Config:** `opts.features.size_info` — `enabled` (default **false**, opt-in), `show_files` (true), `show_dirs` (true), `dir_async` (true — async `du -sb`/`Get-ChildItem` for directories; `false` skips directory sizes entirely rather than blocking), `hl_group` (`"Comment"`)

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

Hiding the real cursor only makes sense as long as something else marks the
current line — normally `'cursorline'`. `force_cursorline` (default `true`)
force-enables it on the tree window for exactly as long as the cursor stays
hidden, and restores whatever it was on leave, so the tree can never end up
with **no** visible position indicator at all (a plugin's own
cursorline-management autocmd racing this one, a colorscheme reset, …) —
that combination looks exactly like a lost cursor: movement, opening nodes
and closing the window all keep working, there is just nothing on screen
marking where you are. Set `force_cursorline = false` to go back to leaving
`'cursorline'` alone.

- **Module:** `lua/filetree/features/ui/cursor_hide/`
- **Config:** `enabled` (default `true`), `force_cursorline` (default `true`)

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

Right-click (`<RightMouse>`) opens a context menu through
`ui.contextmenu`, which draws with
[nvzone/menu](https://github.com/nvzone/menu) if it is installed, or its own
themed `ui.kit.menu` (no third-party plugin needed) otherwise —
either way, right-click works out of the box. With the kit renderer, the
clicked node's line is highlighted for as long as the menu stays open, and
with the tree docked left/right the menu opens beside it rather than on top
of it. See [docs/menu.md](../menu.md) for the entries offered and the full
detail on both.

- **Module:** `lua/filetree/features/ui/context_menu/`
- **Keymaps:** `<RightMouse>`
- **Docs:** [menu.md](../menu.md)
