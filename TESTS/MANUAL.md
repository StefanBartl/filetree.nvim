# filetree.nvim — manual integration test guide

A manual pass: neo-tree plus filetree.nvim, without a real user config.

---

## Automated tests

Headless, no tree plugin needed (stub adapter). Exit 0 = pass, 1 = fail.

- **[smoke.lua](smoke.lua)** — integration: every feature module loads, opt-out
  defaults resolve, registry resolver + binding catalog work.
- **[units.lua](units.lua)** — unit: the util layer (path, buffer, line_count,
  map/autocmd, select adapter) + neo-tree adapter helpers + the reference
  engine's apply/undo layer and the chooser each fileops feature drives.
- **[menu.lua](menu.lua)** — unit: `integrations/menu.lua` (nvzone/menu context
  menu). Stubs the top-level `filetree` module (`feature()`/`config()`) so it
  runs without a real adapter/tree window — the exact seam a host (RightMouse
  dispatcher) uses. Covers entries building, self-gating on feature
  availability, group-level opt-out (`config.menu`), the master `enable=false`
  switch, `cmd()` calling through, and `submenu()`.

- **[cwd_mode.lua](cwd_mode.lua)** — unit: the cwd/root policy feature. Decision
  logic per mode (follow/project/lock/manual), sticky project roots, lock
  enforcement against a foreign `:cd`, manual re-rooting, the mode cycle, the
  tree-window badge in both drawing strategies, and the `:Filetree cwd …`
  command wiring incl. enum completion. Uses a stub adapter and a temp tree.

```
cd /path/to/filetree.nvim
nvim --clean --headless -u NONE -l TESTS/smoke.lua
nvim --clean --headless -u NONE -l TESTS/units.lua
nvim --clean --headless -u NONE -l TESTS/menu.lua
nvim --clean --headless -u NONE -l TESTS/cwd_mode.lua
```

**lib.nvim resolution:** the suites put a sibling `../lib.nvim` checkout on the
runtimepath. Set `FILETREE_LIB_NVIM` to point somewhere else — e.g. a lib.nvim
worktree carrying modules a new feature depends on that are not merged yet:

```
FILETREE_LIB_NVIM=/path/to/lib.nvim/.claude/worktrees/<name> \
  nvim --clean --headless -u NONE -l TESTS/cwd_mode.lua
```

---

## Setup

```
cd /path/to/filetree.nvim
nvim --clean -u TESTS/minimal_neotree.lua .
```

On the first start, lazy.nvim downloads neo-tree and its dependencies into
`%TEMP%/filetree-test/`. That takes about 30 seconds. Afterwards nvim starts
with the repository root as its working directory.

**State dir:** `%TEMP%/filetree-test/` (Windows) / `/tmp/filetree-test/` (Unix)
Delete that folder to start over from scratch.

---

## Global test keymaps

| Key           | Action                                          |
|---------------|-------------------------------------------------|
| `<C-e>`       | toggle neo-tree                                 |
| `<leader>e`   | reveal the current file in the tree             |
| `<leader>H`   | open `:checkhealth filetree`                    |
| `<leader>fa`  | print the active adapter in a notification      |
| `<leader>fn`  | print the current tree node via `vim.inspect()` (cursor must be in the tree) |

---

## Checklist

### 0. Groundwork — before anything else

| # | Test | Expected | Result |
|---|------|----------|--------|
| 0.1 | `:checkhealth filetree` | Every adapter line OK/WARN, no ERROR; every feature either "enabled" or "not configured" | |
| 0.2 | `<leader>fa` | `"Active adapter: neotree"` in the notification | |
| 0.3 | `<C-e>` → tree opens, then `<leader>fn` | A node table appears: `{ id = "...", name = "...", type = "file"\|"directory", path = "...", ... }` | |
| 0.4 | `<leader>fn` with no tree open | Notification: `"No node under cursor"` — no error, no stack trace | |

---

### A. Adapter basics — current_hl

Exercises: `get_current_node()`, `get_visible_nodes()`, extmarks.

| # | Test | Expected |
|---|------|----------|
| A.1 | Open the tree (`<C-e>`), move the cursor inside it | The current line has the `CursorLine` highlight; the parent directory has the `Visual` one |
| A.2 | Move up/down in the tree (`j`/`k`) | The highlight follows the cursor with a slight delay (100 ms debounce) |
| A.3 | Close the tree, open a different file in the editor | On the next tree open, the highlight sits on the current file |

---

### B. CWD / reveal

Exercises: autocommands, `adapter.open_reveal()`.

| # | Test | Expected |
|---|------|----------|
| B.1 | Open a file (`:e lua/filetree/init.lua`) | The tree scrolls to it on its own (auto_reveal) |
| B.2 | After B.1: `:pwd` in the editor | Shows the directory of the file opened last (cwd_sync) |
| B.3 | `<leader>e` with the cursor on a file in the editor | The tree opens with the current file marked |
| B.4 | Open a file in a subdirectory | The cwd moves to that file's directory; the tree focuses it |

---

### C. Virtual text / extmarks — marks + git_status

Exercises: `nvim_buf_set_extmark`, end-of-line virtual text.

**marks** (keymap `m` in the tree):

| # | Test | Expected |
|---|------|----------|
| C.1 | Cursor on a file in the tree, press `m` | A green `✓` appears at the end of the line |
| C.2 | Press `m` again on the same file | The `✓` disappears (toggle) |
| C.3 | Mark several files | All of them show `✓` at once |
| C.4 | Close and reopen the tree | The marks are gone — no persistence is expected here, and that is correct |

**git_status** (automatic, no keymap needed):

| # | Test | Expected |
|---|------|----------|
| C.5 | Edit and save a file (`:w`) | After ~300 ms a `~` (modified) appears at the end of its tree line |
| C.6 | Create a new file (`:e TESTS/newfile.lua`, `:w`) | It shows `?` (untracked) in the tree |
| C.7 | `git add` in a terminal, then move the tree cursor | It shows `+` (staged) |

---

### D. Floating windows — node_info + preview

Exercises: `nvim_open_win`, buffer-local keymaps, close-on-`q`.

**node_info** (keymap `I` in the tree):

| # | Test | Expected |
|---|------|----------|
| D.1 | Cursor on a file, press `I` | A floating window with: path, type, size (bytes + MiB), permissions, mtime, line count |
| D.2 | `q` or `<Esc>` in the float | The window closes |
| D.3 | Press `I` again on the same file | The window closes (toggle: same path = close) |
| D.4 | `I` on a directory | The float shows type `directory` and no line count |
| D.5 | `I` on a very large file (>5 MB) | The line count reads `(skipped — file too large)` |

**preview** (keymap `<Tab>` in the tree — the default since phase 4):

| # | Test | Expected |
|---|------|----------|
| D.6 | Cursor on a Lua file, press `<Tab>` | A floating window with the file's content (max 100 lines) |
| D.7 | `q` closes the preview | |

---

### E. Input / search — filter + live_search

Exercises: `vim.ui.input`, floating prompt buffers, dimming.

**filter** (keymap `/` in the tree):

| # | Test | Expected |
|---|------|----------|
| E.1 | Press `/` in the tree | A floating input prompt appears |
| E.2 | Type `init` and press Enter | Non-matching nodes are dimmed (Comment highlight) |
| E.3 | `:Filetree filter clear` | Dimming is lifted, every node is normal again |

**live_search** (keymap `gs` in the tree):

| # | Test | Expected |
|---|------|----------|
| E.4 | Press `gs` in the tree | A floating prompt buffer at the bottom of the tree |
| E.5 | Type | Non-matching nodes dim live (~80 ms debounce) |
| E.6 | `<Esc>` | The prompt closes and the dimming is lifted |
| E.7 | Enter | The filter stays (commit_to_filter = true) |

---

### F. Clipboard / copy

Exercises: `vim.fn.setreg`, notifications.

**path_copy** (keymaps `<leader>yp`/`[a`/`]a`/`<leader>yn` in the tree):

| # | Test | Expected |
|---|------|----------|
| F.1 | `<leader>yp` | A floating picker with 7 format options |
| F.2 | `[a` | Notification `"Copied: /absolute/path"`; pasting with `<C-r>+` in the editor confirms it |
| F.3 | `]a` | The path relative to the cwd |
| F.4 | `<leader>yn` | The filename only |

**copy_file_list** (keymaps `[f`/`]f`/`[F`/`]F` in the tree):

| # | Test | Expected |
|---|------|----------|
| F.5 | Cursor on a directory, `[f` | A notification previewing the first 5 absolute paths; `<C-r>+` in the editor shows all of them |
| F.6 | `]f` | Relative paths |
| F.7 | `[F` / `]F` | Directories only, recursively |
| F.8 | `[f` on a file rather than a directory | Just that one file — not an error |

**lua_require_copy** (keymap `rq` in the tree):

| # | Test | Expected |
|---|------|----------|
| F.9 | Cursor on `lua/filetree/init.lua`, `rq` | The clipboard holds `require('filetree')` |
| F.10 | Cursor on `lua/filetree/features/org/marks/init.lua`, `rq` | `require('filetree.features.org.marks')` |
| F.11 | Cursor on the directory `lua/filetree/features/`, `rq` | Every Lua module in that directory, in the clipboard |

---

### G. Navigation — tree_traverse

Exercises: `adapter.open_reveal()`, cwd sync.

| # | Test | Expected |
|---|------|----------|
| G.1 | Tree cursor on a file or folder, `-` | The tree root moves to the parent directory; notification `"cwd → /parent"` |
| G.2 | Tree cursor on a directory, `+` | That directory becomes the new root |
| G.3 | `:pwd` after G.1/G.2 | The cwd matches the new tree root |
| G.4 | `-` from the repository root | Moves to the repository's parent — not an error |

**buffer_cycle** (keymaps `<C-n>`/`<C-p>` in the tree):

| # | Test | Expected |
|---|------|----------|
| G.5 | At least 2 buffers open, focus in the tree, `<C-n>` | The editor window (not the tree) shows the next buffer; focus stays in the tree |
| G.6 | Then `<C-p>` | The editor window goes back to the previous buffer; focus stays in the tree |
| G.7 | No editor window at all (only the tree), `<C-n>` | Notification `"No editor window found"` — not an error |

---

### H. Find / grep menu

Exercises: the `vim.ui.select` fallback, the telescope/fzf cascade.

| # | Test | Expected |
|---|------|----------|
| H.1 | Cursor on a directory in the tree, `<M-p>` | A `vim.ui.select` picker with 2 options: `find_files` / `live_grep` |
| H.2 | Choose `find_files` | Telescope (or fzf-lua, or vim.ui.select) opens with cwd = that directory |
| H.3 | Choose `live_grep` | The grepper opens with cwd = that directory |
| H.4 | `<M-p>` on a file rather than a directory | Uses the file's parent directory as the cwd |
| H.5 | `find_files` with no picker installed | An input prompt appears: `"Filename pattern: "`; after typing, `vim.ui.select` shows the hits |

---

### I. Phase 3 — the remapping system

To enable these, uncomment the corresponding blocks in `minimal_neotree.lua`.

**I.1 — keymap remap (`keymaps = { ["gs"] = "<leader>gs" }`):**

| # | Test | Expected |
|---|------|----------|
| I.1 | Press `gs` in the tree | No live search — the key was remapped |
| I.2 | Press `<leader>gs` in the tree | Live search opens |

**I.2 — keymap disable (`keymaps = { ["I"] = false }`):**

| # | Test | Expected |
|---|------|----------|
| I.3 | Press `I` in the tree | Nothing happens (no node_info float) |
| I.4 | `:Filetree info` | The float opens — the command still works |

**I.3 — command rename (`command = { name = "Ft", aliases = { "Filetree" } }`):**

| # | Test | Expected |
|---|------|----------|
| I.5 | `:Ft marks show` | The marks float opens |
| I.6 | `:Filetree marks show` | Works too (alias) |
| I.7 | Tab completion on `:Ft<Tab>` | Subcommands are offered |

**I.4 — autocmd disable (`autocmds = { auto_reveal = false }`):**

| # | Test | Expected |
|---|------|----------|
| I.8 | Open a file (`:e lua/filetree/init.lua`) | The tree does NOT scroll to it (auto_reveal off) |
| I.9 | `<leader>e` | Reveal still works — manually, via the command |

---

### J. ignore_list + the `:Ft` alias

**J.1 — ignore_list default (no config entry needed, on by default):**

| # | Test | Expected |
|---|------|----------|
| J.1 | Open the tree | The `.git` folder is NOT visible — hidden from the start |
| J.2 | Press `H` in the tree | Every hidden item (including `.git`) is shown |
| J.3 | Press `H` again | Hidden again |

**J.2 — ignore_list off (uncomment `ignore_list = false` in minimal_neotree.lua):**

| # | Test | Expected |
|---|------|----------|
| J.4 | Open the tree | `.git` is visible |

**J.3 — ignore_list with a custom list (`ignore_list = { ".git", "node_modules" }`):**

| # | Test | Expected |
|---|------|----------|
| J.5 | Open the tree | Only `.git` and `node_modules` are hidden; other folders (e.g. `build`) are visible |

**J.4 — the `:Ft` alias (always on, needs no config):**

| # | Test | Expected |
|---|------|----------|
| J.6 | `:Ft marks show` | The marks float opens (identical to `:Filetree marks show`) |
| J.7 | `:Ft<Tab>` | Tab completion offers the subcommands |

---

### K. Cursor / reset / buffer save

**cursor_hide** (automatic when the tree opens):

| # | Test | Expected |
|---|------|----------|
| K.1 | `<C-e>` → open the tree | The block cursor is invisible in the tree window (blend=100) |
| K.2 | Switch to the editor (`<C-w>w`) | The cursor is visible again there |
| K.3 | Switch back into the tree | Hidden again |

**tree_reset** (keymap `<Esc>` in the tree):

| # | Test | Expected |
|---|------|----------|
| K.4 | A filter is active (e.g. `init` via `/`), then `<Esc>` | The filter is cleared, every node visible again |
| K.5 | A preview is open (`<Tab>`), then `<Esc>` | The preview closes |
| K.6 | Nothing active, `<Esc>` | No error, no stack trace |

**buffer_save** (`<C-s>` / `<M-s>` in the tree):

| # | Test | Expected |
|---|------|----------|
| K.7 | An editor buffer is modified but unsaved; switch into the tree and press `<C-s>` | Notification `"Saved: lua/filetree/..."`, and the buffer's `[+]` is gone |
| K.8 | `<C-s>` with no neighbouring editor window open | Notification `"No editor window found"` |
| K.9 | Cursor on `lua/filetree/init.lua` in the tree (its buffer open in the background), `<M-s>` | Saves exactly that buffer |
| K.10 | `<M-s>` on a file that is not open as a buffer | Notification `"File not loaded: ..."` |

---

### L. Preview — image/PDF dispatch

| # | Test | Expected |
|---|------|----------|
| L.1 | Cursor on a `.png`/`.jpg` in the tree, `<Tab>` | The system app opens the image (Explorer/Preview/eog); the preview float does NOT appear |
| L.2 | Cursor on a `.pdf` in the tree, `<Tab>` | pdfport.nvim opens it (or the system app, if pdfport is not installed) |
| L.3 | Cursor on a `.lua` in the tree, `<Tab>` | The floating text preview, as usual |
| L.4 | Cursor on a `.png`, `<CR>` | The system app opens the image |
| L.5 | Cursor on a `.lua`, `<CR>` | The adapter's own `<CR>` (expand/open) takes over |

---

### M. Window / system FM / shell

**window_size_cycler** (keymap `w` in the tree):

| # | Test | Expected |
|---|------|----------|
| M.1 | Press `w` in the tree | The width changes to 55 (large) |
| M.2 | `w` again | The width changes to 18 (small) |
| M.3 | `w` again | Back to 35 (normal) |

**open_in_fm** (keymap `<leader>fm` in the tree):

| # | Test | Expected |
|---|------|----------|
| M.4 | Cursor on a file, `<leader>fm` | The system file manager opens at the file's directory (Explorer/Finder/Nautilus) |
| M.5 | Cursor on a directory, `<leader>fm` | The file manager opens that directory |

**shell_run** (keymap `i` in the tree — neo-tree's own `i` is nooped via `adapter_keymaps`):

| # | Test | Expected |
|---|------|----------|
| M.6 | Press `i` in the tree | A prompt appears: `$ (~path/to/node/dir) ` |
| M.7 | Type `echo hello` and press Enter | A horizontal split terminal opens, shows `hello`, and closes afterwards (close_on_ok=true) |
| M.8 | Type `ls -la` | The terminal shows the ls output and closes when it finishes |
| M.9 | Type a command that does not exist (e.g. `doesnotexist`) | The terminal stays open (exit code ≠ 0) |
| M.10 | `<Esc>` at the prompt with no command | Nothing happens, no error |

---

### N. adapter_keymaps — overriding neo-tree's own keymaps

| # | Test | Expected |
|---|------|----------|
| N.1 | In the tree: press `i` | The shell_run prompt opens (NOT neo-tree's run_command) |
| N.2 | In the tree: neo-tree's old `i` behaviour | Gone entirely / noop (adapter_keymaps noop is active) |

---

### O. tree_integrity — the nui `set_nodes` guard

Needs a real nui.nvim, so it cannot live in the headless suites (which run with
no tree plugin at all); `TESTS/units.lua` covers the pre-pass logic against a
hand-built stand-in for nui's node store.

Paste this into a scratch buffer of a session that has neo-tree loaded, then
`:setf lua` and `:source`. It builds a throwaway nui tree, hands the same live
nodes back to `set_nodes` — what neo-tree's `group_empty_dirs` branch does for a
lazily loaded single sub-folder — and prints what the node index looks like
afterwards:

```lua
local NuiTree = require("nui.tree")
local function mk(id, kids) return NuiTree.Node({ id = id, text = id }, kids) end
local tree = NuiTree({
  bufnr = vim.api.nvim_create_buf(false, true),
  nodes = { mk("root", { mk("docs", { mk("a", { mk("a1") }), mk("b") }) }) },
  get_node_id = function(n) return n.id end,
})
tree:set_nodes({ tree:get_node("root") })          -- the same live node, twice
local ids = vim.tbl_keys(tree.nodes.by_id); table.sort(ids)
print("by_id: " .. table.concat(ids, ","))
print("second set_nodes: " .. tostring((pcall(tree.set_nodes, tree, { tree:get_node("root") }))))
```

| # | Test | Expected |
|---|------|----------|
| O.1 | Run the snippet with `tree_integrity` enabled (the default) | `by_id: a,a1,b,docs,root` and `second set_nodes: true` |
| O.2 | `:lua print(require("filetree.features.infra.tree_integrity").installed())` after a tree buffer has been opened | `true` |
| O.3 | Re-run the snippet after `require("filetree").setup({ features = { tree_integrity = { enabled = false } } })` | `by_id: root` and `second set_nodes: false` — the upstream bug, unguarded |
| O.4 | With the guard back on: expand a directory that sits next to a grouped one-child chain (`a/b/c` shown as one line), repeatedly | No `[Neo-tree ERROR] Error setting nodes` in `:messages`, and the grouped chain still renders as one line |
| O.5 | `:checkhealth filetree` | `tree_integrity installed`, plus a healed count if this session hit the corruption |

---

## Known limits of this test environment

- **No git blame**: needs `git log`, and only works inside a real git repository
  — which is given here, as long as the test is started from the repo root.
- **No harpoon**: not installed in this config, so harpoon_integration is not
  exercised.
- **POSIX features** (`file_permissions`): a no-op on Windows, and not enabled
  in the test config.
- **Telescope/fzf**: not installed, so find_or_grep_menu falls back to
  `vim.ui.select` — which is the expected behaviour.
- **No persistence** between sessions: `marks`, `bookmarks`, `session` and the
  rest write to `%TEMP%/filetree-test/data/nvim/filetree/`, which is emptied by
  `rm -rf /tmp/filetree-test`.

---

## Typical failure signatures

| Symptom | Likely cause |
|---------|--------------|
| The tree keymaps are missing | The FileType autocommand did not fire — `:set ft?` in the tree buffer should say `neo-tree` |
| `adapter = nil` from `<leader>fa` | `setup()` failed — `:checkhealth filetree` says why |
| The EOL virtual text does not appear | `get_visible_nodes()` returned an empty list — check with `<leader>fn` whether `get_current_node()` returns anything at all |
| A floating window does not open | An `nvim_open_win` error — usually `width`/`height` = 0 because an adapter method returned nil |
| `rq` copies the wrong module | No `/lua/` found in the path — check the tree root path; it has to sit under a `lua/` directory |
