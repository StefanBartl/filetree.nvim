# filetree.nvim — Roadmap

Features sorted roughly by priority and estimated complexity.

---

## Checklist audits & implementation plan

filetree.nvim was audited against the project checklists. Full per-rule status:
- [Zentral-Prinzipien.md](ROADMAP/Zentral-Prinzipien.md)
- [Arch&Coding.md](ROADMAP/Arch%26Coding.md)
- [Checklist.md](ROADMAP/Checklist.md)
- Feature port map: [NEOTREE_FEATURES.md](ROADMAP/NEOTREE_FEATURES.md)

**Prioritized action items surfaced by the audits:**
1. **lib.nvim adoption** — route keymaps/usercmds/autocmds/augroups through
   `lib.nvim.map` / `usercmd` / `autocmd` / `augroup`, and pickers through
   `lib.nvim.ui.hover_select`. Biggest item (touches every feature); do it
   incrementally with a local fallback so filetree still runs standalone.
   (`util.notify` already delegates to `lib.nvim.notify`.)
2. **Centralize FileType keymap binding** — one dispatcher binds all enabled
   features' tree-buffer keymaps instead of N per-feature `FileType` autocmds.
3. **Broaden automated tests** beyond `test/smoke.lua` (preview modes, copy_move,
   path helpers).
4. **Bound `get_visible_nodes`** on very large trees; audit `CursorMoved` handlers
   for per-event allocations.
5. **Verify persisted state** (recent_files / session / quick_open) lives under
   `stdpath("data")` / `stdpath("cache")`.
6. **Global debug switch** (`config.debug`) feeding `notify.debug`.

---

## Near-term

### UI folder reorganization
Move all UI-rendering features (floats, pickers, extmarks, prompt buffers) into
`lua/filetree/features/ui/` for discoverability. Affected modules: `preview`,
`node_info`, `filter`, `live_search`, `marks`, `git_status`, `bookmarks`,
`color_labels`. Purely internal — no public API change.

### Additional Adapters
- **netrw** — Neovim's built-in file explorer. Minimal public API; would require buffer-parsing heuristics.
- **oil.nvim** — Buffer-as-directory paradigm; node concept differs fundamentally. Needs dedicated abstraction.
- **mini.files** — mini.nvim's file manager; growing user base.

### Trash / Undo System
- `features/trash/` — Platform-aware "send to trash" replacing permanent delete.
  - Windows: PowerShell Recycle Bin (Shell.Application COM)
  - Linux: `gio trash` / `~/.local/share/Trash`
  - macOS: `trash` CLI or AppleScript
- History in-session (50 items), restore last deleted file.

### Watcher Quarantine
- `features/watcher_quarantine/` — Stop file watchers around destructive ops to prevent EPERM on Windows.
- Per-path granularity, health check, configurable duration.

### Picker Improvements
- Show total node count and current filter mode in a floating echo line.
- `<BS>` to correct last digit before committing.
- Configurable label position (left-align vs right-align).

---

## Medium-term

### CWD Sync — Project Root Mode
- Detect project root (`.git`, `package.json`, `Cargo.toml`, etc.) and use it as the reveal target instead of the buffer's parent directory.
- Optional integration with `project.nvim`.

### Marks System
- Toggle marks on nodes (visual indicator in the tree).
- Batch operations on marked nodes: copy, move, delete, generate lists.

### Diff Files
- Select two nodes and open a side-by-side diff (`:diffthis`).

### Markdown / Path Utilities
- Generate Markdown links for selected nodes (single, directory-recursive, marked).
- Copy relative path to clipboard, path-to-require conversion.

### Preview — granular per-type config ✓
`<Tab>` dispatches by file type:
- **Text / dirs**: floating preview window (implemented).
- **Images**: `image.backend = "auto"` → tries snacks.image → image.nvim → system app.
- **PDFs**: `pdf.backend = "pdfport"` → tries pdfport.nvim → system app.
- **`<CR>`**: image/PDF dispatch; calls adapter's original `<CR>` for other nodes.

```lua
features = {
  preview = {
    enabled    = true,
    keymap     = "<Tab>",
    keymap_open = "<CR>",
    image = { backend = "auto" },     -- "snacks" | "image.nvim" | "system" | false
    pdf   = { backend = "pdfport" },  -- "pdfport" | "system" | false
  },
}
```

---

## Long-term / Experimental

### Plugin API
- Public hook system: `filetree.on("before_delete", fn)`, `filetree.on("after_open", fn)`.
- Allows third-party plugins to react to filetree events adapter-agnostically.

### Session Persistence
- Save and restore expanded-directory state across Neovim sessions.

### Remote Adapters
- SSH / SFTP file tree via `sshfs` or native SSH (similar to remote.nvim).

### Telescope / fzf-lua Integration
- `:FT find` — fuzzy find within the current tree root.
- `:FT grep` — live grep scoped to the tree root.

### Auto-Resize
- Responsive sidebar width: narrow on small screens, wide on large ones.
- Configurable breakpoints.

---

## lib.nvim adoption (shared code)

filetree declares `lib.nvim` as a dependency. Shared code should live there so it
is reused across the author's plugins rather than duplicated.

- **Done:** `lib.nvim.neotree.node` (node path/collection helpers, used by the
  neo-tree adapter); `util.notify` now delegates to `lib.nvim.notify`.
- **Candidates** (overlap with existing lib modules; migrate when the APIs are
  reconciled, keeping a local fallback so filetree runs standalone):
  - `util.platform` → `lib.nvim.cross.platform`
  - `util.path` → `lib.nvim.fs.path` / `lib.nvim.normalize`
  - `util.buffer` → `lib.nvim.buf_win_tab.normal_buffer`
  - `util.fs` (recursive collect) → `lib.nvim.fs.*`
  - `util.line_count` → `lib.lua.*` (pure, editor-independent)

---

## Won't implement (out of scope)

- Direct LSP integration (belongs in LSP plugins).
- Terminal emulator inside the tree (scope creep).
- Git staging from the tree (belongs in gitsigns.nvim / lazygit).
