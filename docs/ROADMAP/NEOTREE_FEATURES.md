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

**Reviewed 2026-08-25.** The first two have since been built; only the two
source-model entries below are still open.

1. **Markdown-link bridge** ✅ **shipped** — `commands/markdown/links.lua`.
   Turns tree node(s) into Markdown links: single node, recursive, or all
   explicitly-marked nodes → clipboard.
   → Landed as `paths.markdown_links` (`ML` / `MR` / `MM`), not under
   `integration.*`: it writes the `[name](relative/path)` lines itself rather than calling
   into markdown.nvim, so it has no dependency to guard and belongs with the
   other path-to-clipboard features.

2. **pdfport integration** ✅ **shipped** — `actions/pdfport/`. Opens a PDF node
   as text.
   → Landed as `system.pdf_open`, plus `system.pdf_create` (converting nodes
   *to* PDF), which the audit did not anticipate. pdfport.nvim is a soft
   dependency; without it the node goes to the OS viewer. Both go through the
   adapter, so they are tree-agnostic. See `PDFPORT_INTEGRATION.md`.

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
  filetree.nvim's registry (56 features as of 2026-08-25) — this audit's real
  yield was the four gaps in the section above, of which two have since shipped.

---

## Pass 2: github_stats.nvim — reusable infra/UI patterns

**Purpose.** Second audit called for in `FINISH.md`, this time against
[`github_stats.nvim`](https://github.com/StefanBartl/github_stats.nvim)
(`E:/repos/github_stats.nvim`) — not a filetree plugin, so nothing here is a
feature *port target* the way the Neo-tree gaps above are. It's a different
kind of yield: **architectural/UI patterns** worth reusing when they come up in
filetree.nvim's own infra and UI work, since they were built and refined
against a real plugin with the same cross-platform/config-system/health-check
concerns.

For each: **what** it is, **origin** (`file:line`), **thematic home** in
filetree.nvim, and **notes** on applicability.

| Feature | Origin | Thematic home | Notes |
|---|---|---|---|
| Cross-platform command detection (PowerShell `Get-Command` on Windows, `command -v` on Unix, with a direct-exec fallback) | `lua/github_stats/health.lua:21` (`command_exists`) | `util/platform.lua`, `filetree/health.lua` | Directly portable. Same shape needed for anything filetree.nvim's `checkhealth` or `system.*` openers must probe for (external tools, `pdftotext`, etc.). |
| Atomic file write (write to `<path>.tmp`, then `vim.loop.fs_rename` to the final path; delete the temp file on failure) | `lua/github_stats/storage.lua:81-93` (`M.write_metric`), same pattern again at `:185-195` | `infra.safety` (file-operation safety wrapper) | Cheap, dependency-free crash-safety primitive. Worth using anywhere filetree.nvim persists state to disk (marks, bookmarks, watcher-quarantine data) instead of a plain `writefile`. |
| Dual config source with clear priority order: `setup(opts)` > `config.json` on disk > auto-created default `config.json`, merged via `vim.tbl_deep_extend("force", DEFAULTS, opts)` | `lua/github_stats/config/init.lua:96-138` (`M.init`, see the "Priority 1/2/3" comments) | `infra` (config system) | Not currently in filetree.nvim's registry. The JSON-file fallback is specifically useful for syncing config *and data* across machines via dotfiles — could matter if filetree.nvim ever persists cross-machine state (e.g. marks, recent-files) rather than just runtime config. |
| `notify(message, level)` wrapper gating on a 3-state `notification_level` ("all"\|"errors"\|"silent") | `lua/github_stats/config/init.lua:219` (`get_notification_level`), `:229` (`M.notify`) | `infra` / cross-cutting UX | Small, generically useful pattern for any plugin with frequent background notifications (fetches, watcher events) that shouldn't spam by default. |
| `bindings/{usrcmds,keymaps,autocmds}` module split, with a single `usrcmds/init.lua` registering every `vim.api.nvim_create_user_command` call, and keymaps split into **configurable** (read from a `keybindings` config table, `""` disables a binding) vs **fixed** (always-on, not user-remappable) | `lua/github_stats/bindings/{usrcmds/init.lua, keymaps.lua}` (whole module) | `bindings/` (already exists) | filetree.nvim already has its own `docs/BINDINGS/` — this is a cross-check/validation that the configurable-vs-fixed keymap split and the "empty string disables" convention are a sound, already-battle-tested design, not a new idea to import wholesale. |
| Optional which-key registration, guarded entirely by `pcall(require, "which-key")` so the integration is zero-cost and crash-free when which-key isn't installed | `lua/github_stats/bindings/keymaps.lua:83-93` (`register_which_key`) | `bindings/keymaps.lua`, `ui` | Directly portable pattern for any optional-dependency UI enhancement: never `require` unguarded, always collect entries and register once at the end. |
| Debounced re-render: a single-shot `vim.loop.new_timer()` coalesces rapid state changes into one render, with a `force` bypass for user-triggered actions that should feel instant | `lua/github_stats/dashboard/init.lua:20,28-57` (`RENDER_DEBOUNCE_MS`, `M.schedule_render`) | `ui` | Relevant to any tree/list UI that re-renders on frequent events (fs-watcher ticks, cursor moves) — avoids redrawing on every single event while keeping user-initiated actions (open, refresh) snappy via the `force` path. |
| Blocking native cursor movement in a display-only buffer (`h`/`l`/arrows/`<PageUp>`/`<PageDown>`/`<Home>`/`<End>` mapped to `<Nop>`) so custom navigation is the *only* way to move, avoiding races between Vim's native cursor motion and app-managed selection state | `lua/github_stats/bindings/keymaps.lua:57-77` (`block_cursor_movement`) | `nav`, `ui` | Same problem class as any custom list/tree buffer where "current selection" is app state, not just the cursor line — worth having as a named, reusable helper rather than re-deriving per feature. |
| Sort-cycling that resorts an ordered list in place, then restores the previously-selected item's new position **by identity** (name) so the highlighted item doesn't visually jump when the sort criteria changes | `lua/github_stats/dashboard/render.lua:145-186` (`sort_repos`) | `ui`, `nav` | Exactly the shape of "cycle a tree/list's sort order (name/size/mtime/type) without losing the user's place" — a common filetree expectation. The "capture selected identity before sort, look it up after" technique generalizes directly. |
| Async subprocess calls via `vim.system(args, ...)` with `args` as a **table of arguments**, never an interpolated shell string | `lua/github_stats/api.lua:117,176` | `util/platform.lua`, `system.open_in_fm`/`system.open_with` | Avoids shell-quoting/injection bugs entirely by construction. Directly applicable to the `pdfport` and open-in-system-app gaps noted in the Neo-tree audit above, which already shell out per-OS. |
| `@types/` split into one file per concern (`dashboard.lua`, `gh_api.lua`, `metrics.lua`, `state.lua`, `init.lua`), each returning `{}` and existing purely for `---@class`/`---@field` annotations | `lua/github_stats/@types/*.lua` | Coding convention (see `Arch&Coding.md`) | Not a runtime feature, a typing/organization convention: keeps LSP-facing type definitions colocated by domain instead of one sprawling types file. Matches the typing requirements already tracked in the Arch&Coding checklist. |

### Not applicable

github_stats.nvim's domain-specific modules (date-range presets, period diff/
comparison, CSV/Markdown export of traffic metrics, the GitHub REST API
client) don't map to anything a filetree plugin needs and aren't listed above.

---

## Pass 3: nvim-tree and netrw — the two sources the audit had not read

**Purpose.** The task this file answers names three sources: Neo-tree,
NvimTree and Netrw. Passes 1 and 2 covered the Neo-tree config and
github_stats.nvim; NvimTree and Netrw appeared only as *adapter targets*, never
as feature sources. This pass reads them as sources.

**Method.** Not from memory — against nvim-tree's actual action surface
(`lua/nvim-tree/actions/*/`, which is exactly the set of things it can be asked
to do) and Netrw's documented command set, each mapped onto
`lua/filetree/features/*/`.

### Already covered

Most of nvim-tree's surface maps onto something filetree.nvim already has:

| nvim-tree action | filetree.nvim |
|---|---|
| `finders/find-file`, `finders/search-node` | `search/find_files`, `search/live_search`, `search/filter` |
| `fs/clipboard` | `fileops/copy_move`, `paths/path_copy` |
| `fs/create-file` | `fileops/create`, `smart_create`, `create_from_template` |
| `fs/rename-file` | `fileops/rename_batch`, `smart_rename` |
| `fs/remove-file`, `fs/trash` | `fileops/trash` (with undo) |
| `node/open-file` | `fileops/open_variants`, `open_replace` |
| `node/system-open`, `node/run-command` | `system/open_in_fm`, `open_with`, `shell_run` |
| `node/file-popup` | `ui/node_info`, `ui/size_info` |
| `node/buffer` | `nav/buffer_cycle`, `fileops/buffer_save` |
| `tree/change-dir`, `tree/change-root` | `nav/cwd_mode`, `cwd_sync`, `tree_traverse` |
| `tree/find-file` | `nav/auto_reveal`, `reveal_alt` |
| `tree/resize` | `nav/auto_resize`, `ui/window_size_cycler` |
| `moves/item`, `moves/parent` | `nav/tree_traverse` (`up()`/`down()`) |

Netrw's marked-file workflow (`mf`/`mt`/`mc`/`mm`/`mx`) maps onto
`org/marks` + `fileops/copy_move` + `system/shell_run`, and its bookmarks
(`mb`/`gb`) onto `org/marks`.

### Gaps found

Three, each checked against the source tree rather than assumed:

| Gap | Source | Notes |
|---|---|---|
| **Sibling navigation** — jump to the next/previous entry at the *same* depth, without descending | nvim-tree `actions/moves/sibling` | `nav/tree_traverse` has `up()`/`down()`, which change the *root*. There is no same-level move; `grep -ri sibling lua/filetree/features/` is empty. Cheap and genuinely useful in a wide directory. |
| **Collapse all** — fold every open directory back to the root | nvim-tree `actions/tree/collapse` | The `collapse` hits in the tree are incidental (`auto_reveal`, `cwd_sync`, `marks`), none of them a user-facing action. Every adapter has this natively, so this is likely a thin adapter method rather than a feature of its own. |
| **Sort cycling** — name / size / mtime, and reverse | netrw `s` and `r` | No user-facing sort control at all; the `sort` hits are internal (`create_from_template`, `trash/undo`, `hooks_api`). Worth checking per adapter first: Neo-tree has `sort_function`, nvim-tree has `sort.sorter`, and if all of them can be driven, this is again an adapter method rather than an implementation. |

### Checked and deliberately *not* a gap

- **Toggle hidden/dot-files** (netrw `gh`, nvim-tree `H`). `infra/ignore_list`
  documents this as delegated to the adapter's own mechanism on purpose
  (`init.lua:17-19` names `H` for both Neo-tree and nvim-tree). Reimplementing
  it would mean two switches for one behaviour.
- **Remote editing over scp/ftp** (netrw). Out of scope: netrw is a file
  *browser plus transport*, filetree.nvim is a manager over local trees.
- **Listing styles** (netrw `i`: thin/long/wide/tree). `ui/window_style` and
  `ui/breadcrumbs` cover the display axis filetree.nvim actually owns; the rest
  is the adapter's rendering, not this plugin's.

