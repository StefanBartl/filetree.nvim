# What you get with the defaults

Every feature is on unless [FEATURES/README.md](FEATURES/README.md) lists it
as default-off. The ones worth knowing on day one:

| In the tree | Does |
| --- | --- |
| `?` | The cheatsheet for the buffer you are in: filetree's keys, the adapter's and other plugins' keys, the commands — and any key two actions claim (`:Filetree keys` moves one) |
| Auto-reveal | The tree follows the buffer you switch to |
| Marks | `m` marks a node; copy, move, trash, diff and more act on the whole set |
| Preview | The node under the cursor, without opening it |
| Link marker | A `⇢` sign on a symlinked node, `⇢!` when it dangles |
| Smart rename | Rename, and rewrite the markdown links, `require()`s and `import`s pointing at it |
| Batch rename | The same, over a whole directory, with a preview |
| Trash | Delete through `trash-put`/`gio`, with undo |
| Copy path | The path, URI, or `require` string for the node |
| Find / grep in dir | `f` / `gr` on the node under the cursor, through pickers.nvim when it is installed (else telescope, fzf-lua, ripgrep) |

The full set is [BINDINGS.md](BINDINGS.md); the `:Filetree` command tree is
[commands.md](commands.md).
