# Neo-tree feature audit → filetree.nvim port map

**Purpose.** This is the inventory called for in `FINISH.md`: a sweep of the
filetree features actually implemented in the personal Neovim config's Neo-tree
setup (`nvim/lua/config/neotree/`), so they can be reimplemented in
**filetree.nvim** — **cross-platform** and **filetree-manager agnostic** (Neo-tree,
NvimTree, Netrw, Oil, mini.files via the adapter layer).

For each feature: **what** it is, **origin** (config file), **thematic home** in
filetree.nvim, and **status** — whether filetree.nvim already covers it.

## How to read

- **Origin** paths are relative to `nvim/lua/config/neotree/` (the in-use config).
- **filetree.nvim** names the feature in `lua/filetree/features/init.lua`
  (`<category>.<name>`), or `MISSING` / `partial`.
- **Status:** ✅ ported · 🟡 partial / adapter-specific · ❌ gap (port target)
- Cataloged at **module granularity** (each `.../init.lua` = one feature); a few
  entries were confirmed by reading the source, the rest inferred from the
  module layout + the filetree.nvim registry.

---

## nav — navigation, reveal, window lifecycle

| Feature | Origin | filetree.nvim | Status |
|---|---|---|---|
| Tree traversal (jump parent/sibling/child) | `actions/traverse/` | `nav.tree_traverse` | ✅ |
| CWD sync (follow tree ↔ editor cwd) | `cwd_sync/` | `nav.cwd_sync` | ✅ |
| Reveal current file in tree | `open/reveal/controller.lua` | `nav.auto_reveal`, `nav.reveal_alt` | ✅ |
| Force-close target buffer | `helper/force_close_target_buffer/` | — | 🟡 helper, no distinct feature |
| Refresh adapter / event patching | `refresh_adapter/`, `utils/event_patch.lua` | `adapter.*` plumbing | 🟡 |

## ui — display / cosmetics

| Feature | Origin | filetree.nvim | Status |
|---|---|---|---|
| Current-node highlight | `current_hl/` | `ui.current_hl` | ✅ |
| Node information popup | `actions/node_informations/`, `actions/info/node/` | `ui.node_info` | ✅ |
| Window highlight / no statusline | `window/highlight.lua`, `window/disable_statusline.lua` | `ui.window_style` | ✅ |
| Icons / source selector | `sources/icons.lua`, `init/source_selector/` | adapter render config | 🟡 |
| Custom renderer helper | `helper/renderer/` | adapter render config | 🟡 |
| Line count component | `utils/line_count.lua` | `ui.size_info` (related) | 🟡 |

## fileops — create / edit / move / delete

| Feature | Origin | filetree.nvim | Status |
|---|---|---|---|
| Smart create (file/dir templates) | `commands/add/`, `keymaps/filesystem/create.lua` | `fileops.smart_create`, `fileops.create_from_template` | ✅ |
| Copy entries / folders | `actions/copy/entries/`, `actions/copy/folders/` | `fileops.copy_move` | ✅ |
| Open target, replacing buffer | `keymaps/filesystem/replace.lua` | `fileops.open_replace` | ✅ |
| Save adjacent / node buffer | `actions/save/adjacent_buffer/`, `actions/save/node_buffer/` | `fileops.buffer_save` | 🟡 variants |
| Trash (with confirmation, platform, undo) | `trash/`, `keymaps/filesystem/trash.lua` | `fileops.trash` | ✅ |
| Open in system app | `actions/open_system_app/` | `system.open_in_fm`, `system.open_with` | ✅ |

## search — filter / find / grep

| Feature | Origin | filetree.nvim | Status |
|---|---|---|---|
| Find-or-grep menu | `actions/find_or_grep_menu.lua` | `search.find_or_grep_menu` | ✅ |
| Grep picker (grep in dir) | `actions/grep_picker/` | `search.grep_in_dir`, `search.live_search` | ✅ |
| Filter tree | `keymaps/filesystem/filter.lua` | `search.filter` | ✅ |
| Search / find files | `keymaps/filesystem/search.lua` | `search.find_files` | ✅ |
| Telescope opts bridge | `commands/get_telescope_opts/` | `integration.telescope_integration` | ✅ |

## paths — clipboard / path tools

| Feature | Origin | filetree.nvim | Status |
|---|---|---|---|
| Copy node path to clipboard | `actions/copy/to_clipboard/`, `commands/clipboard/` | `paths.path_copy` | ✅ |
| Path → `require(...)` | `actions/path/to_require/` | `paths.lua_require_copy` | ✅ |
| Relative path → `require(...)` | `actions/rel_path_to_require/` | `paths.lua_require_copy` | ✅ |

## git

| Feature | Origin | filetree.nvim | Status |
|---|---|---|---|
| Git status keymaps | `keymaps/git_status.lua` | `git.git_status`, `git.git_actions` | ✅ |

## lsp

| Feature | Origin | filetree.nvim | Status |
|---|---|---|---|
| Diagnostics in tree | `keymaps/diagnostics.lua` | `lsp.lsp_diagnostics`, `lsp.diagnostics_filter` | ✅ |
| Document symbols / outline | `keymaps/document_symbols.lua` | `lsp.outline` | ✅ |

## compare

| Feature | Origin | filetree.nvim | Status |
|---|---|---|---|
| Diff two files / marked nodes | `commands/diff_files/` | `compare.diff` | ✅ |

## org — marks / organization

| Feature | Origin | filetree.nvim | Status |
|---|---|---|---|
| Node marks (mark/select) | `commands/mark/`, `components/marks/`, `keymaps/filesystem/mark.lua` | `org.marks` | ✅ |

## infra / safety — plumbing

| Feature | Origin | filetree.nvim | Status |
|---|---|---|---|
| Project root detection | `actions/project_root/`, `open/reveal/controller.lua` | `infra.project_root` | ✅ |
| Ignored-dir detection | `helper/is_ignored_dir/` | `infra.ignore_list`, `ui.ignore_patterns` | ✅ |
| File-operation safety wrapper / recovery / validation | `safety/file_operatiuon_wrapper/`, `safety/recovery/`, `safety/validation/` | `infra.safety` | ✅ |
| Watcher quarantine (fs-watch stability) | `watcher_quarantine/` | `infra.watcher_quarantine` | ✅ |
| Event handlers / autocmds / tree+window state | `event_handlers/`, `autocmds/`, `state/tree.lua`, `state/windows.lua` | `bindings.autocmds` + adapter | 🟡 |
| Benchmark harness (dev) | `sources/benchmark.lua` | — | 🟡 dev tooling |
| Config checkhealth | `checkhealth/` | `filetree/health.lua` | ✅ |

---

## Gaps — port targets not yet in filetree.nvim

These have **no** filetree.nvim counterpart and are the concrete work items:

1. **Markdown-link bridge** ❌ — `commands/markdown/links.lua`. Turns tree
   node(s) into Markdown links via `markdown_nvim.commands.markdown_links`:
   single node, recursive (`-r`), or all explicitly-marked nodes → clipboard.
   → New feature, likely `integration.markdown_links` (depends on markdown.nvim;
   guard it as a soft dependency). Cross-plugin, so keep it adapter-agnostic:
   operate on the selected node path(s) the adapter exposes.

2. **pdfport integration** ❌ — `actions/pdfport/` (via `:NeoTreePdfPort` /
   `:NeoTreePdfPortQuick` in `usercmds/init.lua`). Opens a PDF node as text
   (mode picker, or direct `pdftotext`).
   → New feature, e.g. `system.open_with` extension or `integration.pdfport`.
   Already shells out per-OS, so fold it into the cross-platform `system.*`
   opener rather than a bespoke path.

3. **Buffers source: `dd` = buffer_delete** 🟡 — `keymaps/buffers.lua`. Neo-tree's
   buffers source with a delete-buffer mapping (plus many `noop` guards that
   suppress filesystem-only keys on that source).
   → filetree.nvim has no "buffers" source concept. If the adapter target
   supports multiple sources, add a small buffer-list feature; otherwise skip
   (the `noop` guards are Neo-tree-source-specific and not portable).

4. **Neotest source (dormant)** ❌/parked — `keymaps/tests.lua`. Keymaps for a
   Neo-tree *tests* source (run/debug/watch/stop test under cursor). The file is
   annotated `AUDIT: Wird nicht verwendet derzeit!`.
   → Not in use; record as a **future** idea (`integration.neotest`), don't port
   until the config actually activates a tests source.

## Notes for the filetree.nvim implementation

- Everything above must land behind the **adapter** layer
  (`lua/filetree/adapter/{neotree,nvimtree,netrw,oil,mini_files}.lua`) so a
  feature reads "the node under cursor / the marked nodes / the current dir"
  from the adapter, never from a Neo-tree state object directly.
- Cross-platform: the gaps that shell out (pdfport, open-in-system-app) must go
  through `util/platform.lua`, not inline `xdg-open`/`start`/`open` branches.
- The bulk of the config's features (✅ above) are **already implemented** in
  filetree.nvim's 62-feature registry — this audit's real yield is the four gaps
  in the section above.
