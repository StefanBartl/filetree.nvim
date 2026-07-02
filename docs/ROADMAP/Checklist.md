# Lua/Neovim Checklist — applied to filetree.nvim

Audit against
[`Checklist.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Checklist.md).
✅ good · 🟡 partial · ❌ gap · ➖ N/A for this plugin.

## Schnell-Check (10 Punkte, vor jedem Merge) — mostly ✅
- Types on public config keys — ✅ (`@types/config.lua`).
- `pcall` around external / optional calls — ✅.
- Named augroups, teardown-safe — ✅.
- No hard dependency without fallback — ✅ (lib.nvim, tree plugins, pickers all pcall).
- Cross-platform shell-outs — ✅ (`vim.ui.open`, `termopen` cwd, platform branches).
- User-configurable keymaps, disable via `false` — ✅.
- `:checkhealth` support — ✅ (grouped by category).
- Docs (README + vimdoc + BINDINGS) current — ✅.
- No license refs (project policy) — ✅.
- Smoke test green — ✅ (`test/smoke.lua`, 13/13).

## PR-Review-Checkliste — 🟡
Structure/naming/annotations solid. *Gap:* not every change ships a test; add
specs alongside behavioural changes.

## Coding-Checkliste (beim Implementieren) — ✅
Cached `require` locals; guard clauses / early returns; no magic literals in hot
paths; consistent `M`-table module shape; feature `setup(config, adapter)` +
`teardown()` contract everywhere.

## Architektur-Checkliste — ✅
Adapter interface isolates backends; feature registry is the single name→path
source; util layer is dependency-free of features (no cycles). Cross-feature refs
go through `registry.load` (no physical-path coupling).

## Anti-Pattern-Check — ✅ / 🟡
- No global mutable state leaking across features — ✅ (module-local `_cfg`/state).
- No `require` of features by hard path outside the registry — ✅ (enforced this session).
- 🟡 Per-feature FileType autocmds duplicate a pattern → candidate to centralize.

## Import- und Dateistruktur-Check — ✅
`features/<category>/<name>/init.lua`; `@types/`, `util/`, `adapter/`, `bindings/`,
`config/` separated; `docs/BINDINGS.lua` machine-readable catalog; `.luarc.json`
present.

## Performance-Spickzettel (Hotpaths) — 🟡
Hotpaths = `CursorMoved` (preview/current_hl), `get_visible_nodes` (tree walk).
current_hl debounced; preview buffer-mode cheap. *Action:* debounce/bound the
tree-walk on very large trees; verify no per-keystroke allocation.

## Sortier- / Such- / Insert- / Delete-Algorithmen, Komplexität, Bitoperationen — ➖
Reference material; filetree is not an algorithms library. Relevant touch-points:
`fs.collect_recursive` (iterative stack, O(n)), `command_paths` walk (O(n) + sort),
catalog sorts (built once). No custom sort/search hot loops to optimise.

## Reviewer-Notizen — ➖ (template)

## Concentrated action items
Same three as [Arch&Coding](Arch&Coding.md): lib.nvim adoption · centralize
FileType keymap binding · broaden tests. Plus: bound `get_visible_nodes` on huge
trees.
