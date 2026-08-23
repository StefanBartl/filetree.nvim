# Menu (nvzone/menu)

filetree.nvim ships a context menu for [nvzone/menu](https://github.com/nvzone/menu)
but does **not** depend on it — the plugin *owns* its entries (create, rename,
copy/cut/paste, trash, open variants, path/markdown-link copy, find/grep, node
info) and degrades to a single notify, not an error, if nvzone/menu isn't
installed.

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

Install [nvzone/menu](https://github.com/nvzone/menu) and right-click a node —
that's the whole setup. Without it installed, `context_menu` is harmlessly
inert (one notify on first click, not repeated).

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
--   require("menu").open(ft.items(), { mouse = true })
```

Entries are self-gating: an action whose feature is disabled is omitted, and
whole groups can be turned off. nvzone closes the menu before running an entry,
so the tree node under the cursor is the active context — exactly as if the
keymap had been pressed. Opt-out per group via `config.menu` (this controls
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
