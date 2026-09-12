# Integrations

`lua/filetree/integrations/` holds the bridges that expose filetree.nvim's
own actions to something outside the plugin's own trigger — right now, that
is the context menu. See [FEATURES/INTEGRATIONS.md](FEATURES/INTEGRATIONS.md)
for the other direction instead: the features that connect filetree.nvim
outward to git, LSP, sessions and pdfport.nvim.

## Context menu

`filetree.integrations.menu` contributes context-aware entries in the shape
[nvzone/menu](https://github.com/nvzone/menu) expects, acting on the node
under the cursor. On the tree's own buffer filetree.nvim opens them itself
through `lib.nvim.contextmenu`, which needs neither nvzone/menu nor any other
third-party menu plugin (its own kit renderer draws them otherwise). A host —
typically your own `<RightMouse>` dispatcher, for buffers filetree.nvim does
not own — can still compose the same entries into its own menu:

```lua
local ft = require("filetree.integrations.menu")

local items = ft.items()   -- entries for the node under the cursor
local sub = ft.submenu()   -- or a single fly-out entry
```

Entries are self-gating: an action whose feature is disabled is omitted
rather than wired to something that would error when clicked. Opt out per
group via `config.menu` (`fileops`, `clipboard`, `delete`, `open`, `paths`,
`search`, `info`).

The full wiring — right-click out of the box, the kit-renderer extras
(highlighted node, edge-anchored popup), and every entry offered — is
[menu.md](menu.md).
