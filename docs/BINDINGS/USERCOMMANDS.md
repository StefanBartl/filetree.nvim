# filetree.nvim — User Commands

filetree.nvim registers a single unified command (default `:Filetree`) with
sub-command dispatch and tab-completion at every level.

---

## Command name

The command name is configurable:

```lua
-- Simple rename
require("filetree").setup({ command = "Ft" })

-- Rename + keep original as alias
require("filetree").setup({
  command = { name = "Ft", aliases = { "Filetree" } },
})
```

Default: `Filetree`.

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
| `:Filetree git stage` | Stage current node |
| `:Filetree git unstage` | Unstage current node |
| `:Filetree git stash` | Stash changes |
| `:Filetree git stash-pop` | Pop stash |
| `:Filetree git log` | Show git log for current file |

### Find / Grep
| Command | Action |
|---------|--------|
| `:Filetree find [dir]` | Find files (telescope/fzf-lua/builtin) |
| `:Filetree grep [pattern]` | Live grep (telescope/fzf-lua/builtin) |
| `:Filetree findgrep` | Open find-or-grep menu |
| `:Filetree findgrep find` | Run find directly |
| `:Filetree findgrep grep` | Run grep directly |

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

### Bookmarks
| Command | Action |
|---------|--------|
| `:Filetree bookmarks show` | Show bookmarks |
| `:Filetree bookmarks clear` | Clear all bookmarks |

### Notes
| Command | Action |
|---------|--------|
| `:Filetree notes show` | Toggle note for current node |
| `:Filetree notes clear` | Clear all notes |

### Session
| Command | Action |
|---------|--------|
| `:Filetree session save` | Save current session |
| `:Filetree session restore` | Restore session |
| `:Filetree session clear` | Clear saved session |

### Recent files
| Command | Action |
|---------|--------|
| `:Filetree recent` | Show recent files picker |
| `:Filetree recent clear` | Clear recent files list |

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
| `:Filetree copy dirname` | Copy parent directory |
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

### Jump list
| Command | Action |
|---------|--------|
| `:Filetree jump back` | Navigate back |
| `:Filetree jump forward` | Navigate forward |
| `:Filetree jump list` | Show jump history |
| `:Filetree jump clear` | Clear jump list |

### Compare dirs
| Command | Action |
|---------|--------|
| `:Filetree compare marked` | Compare marked directories |
| `:Filetree compare current` | Compare current directory |

### Pin node
| Command | Action |
|---------|--------|
| `:Filetree pin toggle` | Pin/unpin current node |
| `:Filetree pin show` | Show pinned nodes |
| `:Filetree pin clear` | Clear all pins |

### Workspace
| Command | Action |
|---------|--------|
| `:Filetree workspace switch` | Switch workspace root |
| `:Filetree workspace add [path]` | Add root |
| `:Filetree workspace remove [path]` | Remove root |
| `:Filetree workspace list` | List workspace roots |

### Ignore patterns
| Command | Action |
|---------|--------|
| `:Filetree ignore toggle` | Toggle ignore-pattern dim |
| `:Filetree ignore add <pattern>` | Add a pattern |
| `:Filetree ignore clear` | Clear all patterns |
| `:Filetree ignore list` | List active patterns |

### Color labels
| Command | Action |
|---------|--------|
| `:Filetree label set [name/idx]` | Set label for current node |
| `:Filetree label clear` | Clear label |
| `:Filetree label list` | List available labels |

### Outline
| Command | Action |
|---------|--------|
| `:Filetree outline` | Show LSP outline for current file |

### Diagnostics filter
| Command | Action |
|---------|--------|
| `:Filetree diag filter` | Toggle diagnostic filter |
| `:Filetree diag refresh` | Refresh diagnostic counts |
| `:Filetree diag severity <n>` | Set minimum severity |

### Tags
| Command | Action |
|---------|--------|
| `:Filetree tag add <tag>` | Add tag to current node |
| `:Filetree tag remove <tag>` | Remove tag |
| `:Filetree tag filter <tag>` | Filter tree by tag |
| `:Filetree tag clear` | Clear tags from current node |
| `:Filetree tag list` | List all tags |
| `:Filetree tag edit` | Edit tags interactively |

### Telescope integration
| Command | Action |
|---------|--------|
| `:Filetree telescope bookmarks` | Browse bookmarks with picker |
| `:Filetree telescope marks` | Browse marks |
| `:Filetree telescope recent` | Browse recent files |
| `:Filetree telescope notes` | Browse notes |
| `:Filetree telescope pins` | Browse pins |
| `:Filetree telescope workspace` | Browse workspace roots |
| `:Filetree telescope tags` | Browse tags |

### Trash
| Command | Action |
|---------|--------|
| `:Filetree trash undo` | Undo last trash operation |
| `:Filetree trash history` | Show trash history |
| `:Filetree trash dry-run` | Toggle dry-run mode |

### Archive
| Command | Action |
|---------|--------|
| `:Filetree archive zip` | Zip current node |
| `:Filetree archive tar` | Tar.gz current node |
| `:Filetree archive extract` | Extract archive |

### Misc
| Command | Action |
|---------|--------|
| `:Filetree terminal` | Open terminal in node directory |
| `:Filetree template` | Create file from template |
| `:Filetree open system` | Open with system default |
| `:Filetree open pick` | Open with app picker |
| `:Filetree open app <name>` | Open with named app |
| `:Filetree duplicate` | Duplicate current node |
| `:Filetree blame` | Show git blame float |
| `:Filetree chmod <mode>` | chmod current file |
| `:Filetree permissions show` | Show stat details |
| `:Filetree permissions exec` | Toggle execute bit |
| `:Filetree quickopen` | Open frecency quick-open picker |
| `:Filetree harpoon add` | Add to harpoon |
| `:Filetree harpoon remove` | Remove from harpoon |
| `:Filetree harpoon menu` | Open harpoon quick-menu |
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
