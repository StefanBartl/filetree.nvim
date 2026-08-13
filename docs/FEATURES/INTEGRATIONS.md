# Integrations

Everything that connects the tree to something outside itself: git,
external programs, LSP, diffing, marks/session persistence, and the
PDF bridge to [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim).

## Git Status

Decorates tree nodes with git status (modified/staged/untracked/…),
resolved per adapter — each backend surfaces this through its own native
mechanism rather than filetree.nvim reimplementing git status parsing.

- **Module:** `lua/filetree/features/git/git_status/`

## Marks

Toggle a mark on the node under the cursor (`m`), batch mark/unmark
(`]m`/`[m`), and list every current mark (`<C-m>`) — the selection
mechanism several fileops features (trash, copy/move, copy_file_list)
build on for "act on more than one node at once".

- **Module:** `lua/filetree/features/org/marks/`
- **Keymaps:** `m`, `]m`, `[m`, `<C-m>`, `<leader>ms`

## Session

Persists and restores tree state (root, expanded nodes, marks) across
Neovim sessions, so reopening a project brings the tree back roughly
where you left it rather than starting fresh every time.

- **Module:** `lua/filetree/features/org/session/`

## Open In File Manager

Shows the node in the system file manager — a file selected inside its
parent directory, a directory navigated straight into (`<leader>fm`).
Cross-platform (Explorer/Finder/xdg-open-based managers).

- **Module:** `lua/filetree/features/system/open_in_fm/`
- **Keymaps:** `<leader>fm`

## Open With

Opens the node with a configured external application (`<leader>sm`) —
for file types you want handled by a specific program rather than
Neovim's own `preview`/`open` path.

- **Module:** `lua/filetree/features/system/open_with/`
- **Keymaps:** `<leader>sm`
- **Config:** external-app mapping — see [configuration.md](../configuration.md)

## Shell Run

`i` prompts for a shell command and runs it in the node's directory —
for one-off commands (`npm install`, `go build`) scoped to wherever the
cursor happens to be in the tree, no manual `cd` first.

- **Module:** `lua/filetree/features/system/shell_run/`
- **Keymaps:** `i`

## LSP Diagnostics

Decorates tree nodes with LSP diagnostic severity (error/warn/…) rolled
up from the files under them, so a directory with a broken file inside
it is visible without expanding into it first.

- **Module:** `lua/filetree/features/lsp/lsp_diagnostics/`

## Diff

`D` diffs the node under the cursor — against the working tree, a git
revision, or another node, depending on how it's invoked. Native
diffmode under the hood, nothing custom rendered.

- **Module:** `lua/filetree/features/compare/diff/`
- **Keymaps:** `D`

## PDF bridge (pdfport.nvim)

When [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) is
installed, `.pdf` nodes dispatched through `preview` ([UI.md](UI.md)) or
opened directly can route through pdfport's own backend fallback chain
(render into a buffer) instead of always shelling out to the system PDF
reader. Soft dependency — without pdfport.nvim installed, `.pdf` nodes
just open with the system reader, no prompt.

- **Module:** `lua/filetree/features/system/pdf_open/`,
  `lua/filetree/features/system/pdf_create/` (dispatch/creation sites,
  wired into `preview` — [UI.md](UI.md)); see
  [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) for the
  render side
