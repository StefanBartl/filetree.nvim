# What you get with the defaults

Every feature is on unless [FEATURES/README.md](FEATURES/README.md) lists it
as default-off. The ones worth knowing on day one:

| In the tree | Does |
| --- | --- |
| `?` | The cheatsheet for the buffer you are in |
| Auto-reveal | The tree follows the buffer you switch to |
| Marks | `m` marks a node; copy, move, trash, diff and more act on the whole set |
| Preview | The node under the cursor, without opening it |
| Smart rename | Rename, and rewrite the markdown links, `require()`s and `import`s pointing at it |
| Batch rename | The same, over a whole directory, with a preview |
| Trash | Delete through `trash-put`/`gio`, with undo |
| Copy path | The path, URI, or `require` string for the node |
| Grep in dir | ripgrep, scoped to the node under the cursor |

The full set is [BINDINGS.md](BINDINGS.md); the `:Filetree` command tree is
[commands.md](commands.md).
