# Menu

filetree.nvim ships a context menu, drawn through
[`lib.nvim.contextmenu`](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/contextmenu/README.md) —
[nvzone/menu](https://github.com/nvzone/menu) if it's installed, or
`lib.nvim.ui.kit.menu` (no third-party plugin, themed by whatever colorscheme
kit is already using) otherwise. Either way filetree.nvim itself does **not**
depend on nvzone/menu directly — the plugin *owns* its entries (create,
rename, copy/cut/paste, trash, open variants, path/markdown-link copy,
find/grep, node info, marks, open/close the tree itself); only `lib.nvim`
decides how they get drawn.

Entries are self-gating in a way that's worth trusting: `filetree.integrations.menu`
never lists an action whose feature function doesn't actually exist (disabled
feature, or an unknown name) — the entry is silently omitted rather than
wired to something that would error when clicked. `TESTS/smoke.lua` checks
every `(feature, function)` pair `items()` uses against the real feature
modules (not stubs), so a renamed/removed function fails CI instead of just
quietly dropping a menu entry; `TESTS/menu.lua` covers the gating/opt-out
logic itself against stubs.

## Right-click, out of the box

The `context_menu` feature binds `<RightMouse>` in the tree buffer and opens
the menu at the mouse — **on by default (opt-out)**, no wiring needed:

```lua
require("filetree").setup({
  -- omit entirely to just get it; here only to show the knobs:
  features = {
    context_menu = {
      enabled = true,          -- default true
      keymap  = "<RightMouse>", -- default; false disables the trigger without
                                 -- disabling the feature (e.g. if you'd rather
                                 -- wire your own trigger via items()/submenu()
                                 -- below — nothing else needs to change)
    },
  },
})
```

Right-click a node — that's the whole setup, with or without
[nvzone/menu](https://github.com/nvzone/menu) installed. `context_menu`
degrades to a single notify (not repeated, and not an error) only if
`lib.nvim` itself predates `lib.nvim.contextmenu`.

## Building your own trigger

The entries themselves live in `filetree.integrations.menu`, independent of
`context_menu`'s binding — useful if you want a different trigger (a keymap
instead of a click), or to merge filetree's entries into a combined menu
alongside other plugins':

```lua
local ft = require("filetree.integrations.menu")

-- inline entries for the current node (empty when disabled):
local items = ft.items()            -- { { name, cmd, rtxt }, … }

-- or a single fly-out entry:
local sub = ft.submenu()            -- { name = "  Filetree", items = {…} } | nil

-- e.g. your own trigger for the tree window:
--   require("lib.nvim.contextmenu").open(ft.items(), { mouse = true })
```

Entries are self-gating: an action whose feature is disabled is omitted, and
whole groups can be turned off. The menu closes before running an entry (both
renderers), so the tree node under the cursor is the active context — exactly
as if the keymap had been pressed. Opt-out per group via `config.menu` (this controls
WHICH entries appear, for both the built-in trigger and any of your own):

```lua
require("filetree").setup({
  menu = {
    enable    = true,
    fileops   = true, -- create / rename / batch rename / move / template
    clipboard = true, -- copy / cut / paste
    delete    = true, -- trash
    open      = true, -- vsplit / split / tab / system app / file manager
    paths     = true, -- copy path / markdown link
    search    = true, -- find files / grep in dir
    info      = true, -- node info
  },
})
```
