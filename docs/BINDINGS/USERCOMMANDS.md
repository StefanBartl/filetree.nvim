# filetree.nvim — User Commands

filetree.nvim registers a single unified command (default `:Filetree`),
built via [`lib.nvim.usercmd.composer`](https://github.com/StefanBartl/lib.nvim),
with sub-command dispatch and tab-completion at every level. Out of the box,
the short alias `:Ft` also works — `:Ft marks show` is identical to
`:Filetree marks show`.

---

## Command name

The command name and its aliases are configurable:

```lua
-- Simple rename (replaces both default names, :Ft alias dropped)
require("filetree").setup({ command = "Foo" })

-- Rename + explicit aliases
require("filetree").setup({
  command = { name = "Ft", aliases = { "Filetree" } },
})

-- Keep :Filetree, drop the default :Ft alias
require("filetree").setup({
  command = { name = "Filetree", aliases = {} },
})
```

Default: `Filetree`, with `Ft` registered automatically as an alias.

---

## Sub-commands

### Marks
| Command | Action |
|---------|--------|
| `:Filetree marks clear` | Clear all marks |
| `:Filetree marks show` | Show floating list |
| `:Filetree marks all` | Mark all visible nodes |

### Diff
| Command | Action |
|---------|--------|
| `:Filetree diff marked` | Diff marked nodes |
| `:Filetree diff close` | Close diff windows |

### Git
| Command | Action |
|---------|--------|
| `:Filetree git refresh` | Refresh git status |

### Find / Grep
| Command | Action |
|---------|--------|
| `:Filetree find [dir]` | Find files (telescope/fzf-lua/builtin) |
| `:Filetree grep [pattern]` | Live grep (telescope/fzf-lua/builtin) |

### Filter
| Command | Action |
|---------|--------|
| `:Filetree filter` | Open filter input |
| `:Filetree filter <query>` | Apply query directly |
| `:Filetree filter clear` | Clear current filter |

### Live search
| Command | Action |
|---------|--------|
| `:Filetree search` | Open live search |
| `:Filetree search clear` | Clear search highlighting |

### Session
| Command | Action |
|---------|--------|
| `:Filetree session save` | Save current session |
| `:Filetree session restore` | Restore session |
| `:Filetree session clear` | Clear saved session |

### Copy / Move
| Command | Action |
|---------|--------|
| `:Filetree clipboard show` | Show copy/cut clipboard |
| `:Filetree clipboard clear` | Clear clipboard |
| `:Filetree clipboard copy` | Stage current for copy |
| `:Filetree clipboard cut` | Stage current for cut |
| `:Filetree clipboard paste` | Paste staged nodes |

### Path copy
| Command | Action |
|---------|--------|
| `:Filetree copy absolute` | Copy absolute path |
| `:Filetree copy relative` | Copy relative path |
| `:Filetree copy name` | Copy filename |
| `:Filetree copy dirname` | Copy absolute parent directory |
| `:Filetree copy uri` | Copy as `file://` URI |
| `:Filetree copy line` | Copy path with line number |
| `:Filetree copy stem` | Copy stem (no extension) |
| `:Filetree copy pick` | Open format picker |

### Copy file list
| Command | Action |
|---------|--------|
| `:Filetree filelist files abs` | Copy recursive file list (absolute) |
| `:Filetree filelist files rel` | Copy recursive file list (relative) |
| `:Filetree filelist dirs abs` | Copy recursive dir list (absolute) |
| `:Filetree filelist dirs rel` | Copy recursive dir list (relative) |

### Lua require copy
| Command | Action |
|---------|--------|
| `:Filetree require` | Copy as `require("…")` string |
| `:Filetree require relative` | Copy as relative require |

### Node info
| Command | Action |
|---------|--------|
| `:Filetree info` | Show node info float |
| `:Filetree info close` | Close info float |

### Smart create
| Command | Action |
|---------|--------|
| `:Filetree create` | Smart create file or directory |

### Rename
| Command | Action |
|---------|--------|
| `:Filetree rename` | Open batch rename buffer |
| `:Filetree smartrename` | Rename with LSP reference update |

### Tree traverse
| Command | Action |
|---------|--------|
| `:Filetree traverse up` | Navigate to parent directory |
| `:Filetree traverse down` | Set current dir as root |

### Trash
| Command | Action |
|---------|--------|
| `:Filetree trash undo` | Undo last trash operation |
| `:Filetree trash history` | Show trash history |
| `:Filetree trash dry-run` | Toggle dry-run mode |

### Open variants
| Command | Action |
|---------|--------|
| `:Filetree openas vsplit` | Open current node in a vertical split |
| `:Filetree openas split` | Open current node in a horizontal split |
| `:Filetree openas tabnew` | Open current node in a new tab |
| `:Filetree openas badd` | Add current node to buffer list (no focus switch) |

### Markdown links
| Command | Action |
|---------|--------|
| `:Filetree mdlink` | Markdown link for current node |
| `:Filetree mdlink recursive` | Markdown links for every file under current node |
| `:Filetree mdlink marked` | Markdown links for all marked nodes |

### Misc
| Command | Action |
|---------|--------|
| `:Filetree template` | Create file from template |
| `:Filetree open system` | Open with system default |
| `:Filetree open pick` | Open with app picker |
| `:Filetree open app <name>` | Open with named app |
| `:Filetree reveal` | Reveal current buffer in tree |
| `:Filetree reveal pause [ms]` | Pause auto-reveal |
| `:Filetree reveal resume` | Resume auto-reveal |
| `:Filetree resize [width]` | Set tree window width |
| `:Filetree size refresh` | Refresh size annotations |
| `:Filetree breadcrumbs update` | Update breadcrumb display |
| `:Filetree safety list` | List safety backups |
| `:Filetree safety dry-run` | Toggle safety dry-run |
| `:Filetree watcher enter [ms]` | Enter watcher quarantine |
| `:Filetree watcher exit` | Exit watcher quarantine |
| `:Filetree hooks events` | List registered hook events |
| `:Filetree hooks clear [event]` | Clear hooks |
| `:Filetree health` | Run `:checkhealth filetree` |
