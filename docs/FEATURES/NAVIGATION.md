# Navigation

Moving the tree root, revealing files, cycling adjacent buffers, and
keeping the editor window layout sane. See [CORE.md](CORE.md) for the
root/cwd *policy* stack (`cwd_mode`, `cwd_sync`, `project_root`) that some
of these interact with.

## Tree Traverse

`-` navigates up to the parent directory, `+` sets the directory under the
cursor as the new tree root — via `adapter.set_root()` where supported,
falling back to `:cd` + `adapter.open_cwd()` otherwise. A manual re-root
here is reported to `cwd_mode.notify_manual_root()` when that feature is
active, so a `lock`/`project`/`tree_leads` policy moves its pin instead of
fighting the user's own `+`/`-` press.

- **Module:** [`features/nav/tree_traverse/init.lua`](../../lua/filetree/features/nav/tree_traverse/init.lua)
- **Keymaps:** `-` up, `+` down (config fields `keymap_up`/`keymap_down`)
- **Usercmds:** `:Filetree traverse up`, `:Filetree traverse down`

## Auto Reveal

Scrolls to (or expands+reveals) the current file in the tree on every
buffer switch, **without ever changing the cwd or the tree's root** — it
only acts within the root the tree already has. Debounced (`debounce_ms`,
default 150ms), auto-pauses while the cursor is inside the tree window to
avoid feedback loops, and does nothing for a file outside the current root
(that's `cwd_sync`'s job, or the tree plugin's own native follow).

Entering the tree window (`<C-w>w`, `<C-h>`, a mouse click) also puts the
tree cursor on the current file's node (`sync_on_enter`, default `true`).
That reveal skips the debounce deliberately: without it, whether you landed
on the right node depended on whether the debounced `BufEnter` reveal had
already fired — switch buffers and step into the tree quickly enough and the
reveal found the cursor already in the tree, dropped itself, and left you
wherever you last were.

- **Module:** [`features/nav/auto_reveal/init.lua`](../../lua/filetree/features/nav/auto_reveal/init.lua)
- **Config:** `enabled` (default `true`), `debounce_ms` (150), `ignore_ft`, `only_if_open` (default `true`), `sync_on_enter` (default `true`)
- **Usercmds:** `:Filetree reveal`, `:Filetree reveal pause [ms]`, `:Filetree reveal resume`

## Reveal Alt

`B` resolves the alternate buffer (`#`) and calls `adapter.open_reveal()`
on it, adjusting the tree root if the file lives outside the current one —
the tree-buffer analogue of `:e #`.

- **Module:** [`features/nav/reveal_alt/init.lua`](../../lua/filetree/features/nav/reveal_alt/init.lua)
- **Keymaps:** `B` (config field `keymap`)

## Source Switcher (neo-tree)

neo-tree renders its filesystem, buffer list, git status, symbol outline,
diagnostics and (with neo-tree-tests-source) tests through one window.
Its own `<`/`>` re-open the tree at the *configured* position — not where
it is when you press the key in a float. This feature keeps the position:
`"`/`!` cycle to the next/previous source in place, `:Filetree source`
(or a global key) opens a floating list with each source's icon and name,
the current one marked and a `[!]` on one that cannot load right now
(`document_symbols` without an LSP client, an uninstalled optional source).

The pure half needs no `setup()`: `display_name(source, opts)` returns the
` <icon> <Name>` string neo-tree's `source_selector` wants, in three icon
families (`nerd`, `codicons`, `common` for a font without glyphs) and two
name lengths — so a host builds neo-tree's own opts from it:

```lua
local sw = require("filetree.features.nav.source_switcher")
source_selector = {
  winbar = true,
  sources = sw.display_names({ "filesystem", "buffers", "git_status" }, { family = "nerd" }),
}
```

A silent no-op on every other adapter: one tree, nothing to switch.

- **Module:** [`features/nav/source_switcher/init.lua`](../../lua/filetree/features/nav/source_switcher/init.lua)
- **Keymaps:** `"` next, `!` previous (config fields `keymap_next`/`keymap_prev`, tree-local); `keymap_pick` (global, default unset)
- **Usercmds:** `:Filetree source [name|pick|next|prev|debug]`
- **Config:** `opts.features.source_switcher.sources` (override the list), `.icons = { family, variant, length }`

## Tree Toggle (opt-in)

Four global keys that open (or close) the tree at a chosen position and
reveal the current file on the way in, re-rooting to the cwd when the file
lies outside the tree: `<M-l>` left, `<M-r>` right, `<M-f>` float, `<M-c>`
in the current window. The `:Neotree toggle position=… reveal
reveal_force_cwd` most configs write four times, through
`adapter.toggle_at()` instead — so it works on every backend that can place
its tree, and refuses with a reason on one that cannot.

On neo-tree the adapter also heals one race: toggling again before the
previous toggle's debounced scan has settled makes `nvim_buf_set_name`
collide (E95) and leaves a blank, unfocusable tree window that re-errors on
every redraw. The adapter closes any never-rendered neo-tree window and
retries once, which is what pressing the key again used to do by hand.

Off by default: four global Alt keys are a claim on the keyboard the user
makes, not the plugin.

- **Module:** [`features/nav/tree_toggle/init.lua`](../../lua/filetree/features/nav/tree_toggle/init.lua)
- **Keymaps:** `<M-c>`, `<M-f>`, `<M-l>`, `<M-r>` (global; config fields `keymap_current`, `keymap_float`, `keymap_left`, `keymap_right`)
- **Usercmds:** `:Filetree toggle [left|right|float|current]`
- **Config:** `opts.features.tree_toggle.enabled` (default **false**), `reveal` (true), `reveal_force_cwd` (true)

## Auto Resize (opt-in)

Responsive tree sidebar width driven by `VimResized`: breakpoints map
editor column count to a tree width, defaulting to `<100 cols → 25`,
`<140 → 30`, `≥140 → 35` (the largest breakpoint ≤ current columns wins).
Off by default because it fights the manually-driven `window_size_cycler`
(on by default) — enabling both means every manual resize gets silently
reverted on the next `VimResized`.

- **Module:** [`features/nav/auto_resize/init.lua`](../../lua/filetree/features/nav/auto_resize/init.lua) (`M.set_width`)
- **Config:** `opts.features.auto_resize.enabled` (default **false**), `breakpoints`, `min_width` (20), `max_width` (60)
- **Usercmds:** `:Filetree resize [width]`

## Buffer Cycle

`<C-n>`/`<C-p>` cycle the buffer shown in the *adjacent* editor window
(like `:bnext`/`:bprevious`) while focus stays in the tree — verified
against a live neo-tree buffer to not collide with neo-tree's own default
`window.mappings` (unlike `<C-f>`/`<C-b>`, which neo-tree claims natively
for `scroll_preview`).

- **Module:** [`features/nav/buffer_cycle/init.lua`](../../lua/filetree/features/nav/buffer_cycle/init.lua)
- **Keymaps:** `<C-n>` next, `<C-p>` previous (config fields `keymap_next`/`keymap_prev`)

## Layout Guard

When the user closes every editor window but leaves the tree open, this
opens a new empty editor window automatically — fires on `BufDelete`,
`BufWipeout`, `WinClosed` — so the user is never trapped inside the tree
with nowhere to edit.

The new window is pinned to the screen edge **away from the tree**
(`:botright vsplit` for a left sidebar, `:topleft vsplit` for a right one),
via `util.window.open_editor_window()`. A bare `:vsplit` would instead
follow `'splitright'` relative to the tree window — which, at the moment the
guard fires, is the only window and therefore spans the full width — so with
the default `splitright = false` the new window appeared on the tree's left
and the sidebar was left sitting at the right edge of the screen. Because
the guard fires on `BufDelete`/`WinClosed`, that typically happened while a
picker float was up, which made it look like the tree randomly swapped sides
after using a picker. The side comes from `adapter.get_position()` (neo-tree
keeps it in its own state, so it is still known while the tree window is
closed), falling back to the tree window's actual column, and finally to a
plain `:vsplit` when the tree has no side at all (float / `current`). When
the guard fires while a floating window has focus, the split is made through
`nvim_win_call` so the float keeps focus.

The same helper backs the "no editor window exists yet" branch of
`open_variants`, `smart_create` and `create_from_template`, which had the
identical flip.

- **Module:** [`features/nav/layout_guard/init.lua`](../../lua/filetree/features/nav/layout_guard/init.lua)
- **Config:** `enabled` (default `true`), `delay_ms` (50)

## No Name Guard

Redirects a stray `[No Name]` editor window to a real open buffer (and
wipes the scratch one) rather than leaving it sitting alongside real
buffers. Two passes: `handle()` reacts to that window's own `BufWinEnter`
directly; `sweep()` additionally scans every window on `BufAdd`/
`BufDelete`/`BufWipeout` to catch a stray buffer that never itself refires
`BufWinEnter`. Both defer one tick and re-validate before acting, since
these events can fire mid-transition before Neovim settles the window's
replacement buffer. The tree's own window is always excluded, by
construction, so this can never race the tree plugin's own buffer
bookkeeping during open/close.

- **Module:** [`features/nav/no_name_guard/init.lua`](../../lua/filetree/features/nav/no_name_guard/init.lua)
- **Config:** `opts.features.no_name_guard.enabled` (default `true`)

## Sidebar Guard

Keeps the tree in its sidebar. A buffer that lands in the tree window — a
stray `:buffer N`, a mouse click on a tabline buffer (NvChad's tabufline,
bufferline, …) while the cursor is *inside* the tree, or another plugin's
`:edit` — is moved to a real editor window, and the tree is put back where
it was.

Without that, the swap displaces the tree, and neo-tree's own recovery
(`buffer_enter_event`) reopens the sidebar through a bare `:vsplit`: with
the default `splitright = false` the new file window lands to the *left* of
the tree and shoves the sidebar to the right. The repro is exactly "tree
open on the left, click a tabline buffer, tree jumps to the right".

The redirect serves both cases at once, because they are the same thing at
the API level: the only difference is what the caller meant, and nobody ever
means "put this file in the sidebar".

**`winfixbuf = true`** (off by default) swaps the redirect for the older
strategy: pin the window so the switch is *refused*. Callers that check the
flag (NvChad's `goto_buf`, neo-tree's own `open_file`) then route around it
by themselves, with no window shuffling at all. Callers that do not get

```
E1513: Cannot switch buffer. 'winfixbuf' is enabled
```

— and the file does not open. A plugin opening a README from its own picker
has no way to know a tree is focused, so that refusal broke reposcope,
lazygit and anything else driving `:edit` from a callback. It is kept as an
option for anyone who prefers a refusal to a redirect; the two do not
combine, since a refused switch never reaches the redirect.

Both strategies stand down for the one legitimate in-window buffer swap —
switching source via the `source_selector` winbar — which neo-tree brackets
with its `NEO_TREE_WINDOW_BEFORE_OPEN` / `_AFTER_OPEN` events.

neo-tree only. The redirect works on any Neovim; `winfixbuf = true`
additionally needs 0.10+ (`&winfixbuf`) and is a no-op below it.

- **Module:** [`features/nav/sidebar_guard/init.lua`](../../lua/filetree/features/nav/sidebar_guard/init.lua)
- **Config:** `opts.features.sidebar_guard.enabled` (default `true`), `opts.features.sidebar_guard.winfixbuf` (default **`false`** — the redirect; set `true` to pin with `winfixbuf` and refuse the switch instead)
