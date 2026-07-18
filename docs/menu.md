# Menu (nvzone/menu)

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
