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

- **Module:** [`features/nav/auto_reveal/init.lua`](../../lua/filetree/features/nav/auto_reveal/init.lua)
- **Config:** `enabled` (default `true`), `debounce_ms` (150), `ignore_ft`, `only_if_open` (default `true`)
- **Usercmds:** `:Filetree reveal`, `:Filetree reveal pause [ms]`, `:Filetree reveal resume`

## Reveal Alt

`B` resolves the alternate buffer (`#`) and calls `adapter.open_reveal()`
on it, adjusting the tree root if the file lives outside the current one —
the tree-buffer analogue of `:e #`.

- **Module:** [`features/nav/reveal_alt/init.lua`](../../lua/filetree/features/nav/reveal_alt/init.lua)
- **Keymaps:** `B` (config field `keymap`)

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
