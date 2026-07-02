# Architektur- & Codierungsrichtlinien — applied to filetree.nvim

Audit against
[`Arch&Coding-Regeln.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Arch&Coding-Regeln.md).
✅ good · 🟡 partial · ❌ gap.

## 1. Sicherheitsprinzipien & Fehlerbehandlung — ✅
Adapter methods are contractually "must not throw" (`@types/adapter.lua`); external
calls (`require` of optional plugins, `vim.system`, feature cross-refs) are
`pcall`-guarded; failures surface via `notify.warn/error`. `setup()` wraps each
feature's `setup` in `pcall` so one bad feature can't abort the rest.

## 2. Modularisierung & Strukturprinzipien — ✅
Clear layers: `adapter/` (backend translation) · `features/<category>/` (70
single-purpose modules) · `util/` (shared primitives) · `bindings/` (catalog) ·
`config/` (defaults). One registry (`features/init.lua`) maps name → module.

## 3. Buffer- & Window-Management — ✅
Centralized in `util.buffer` (`is_valid_file_buffer`, `find_editor_win`, shared
`TREE_FT`, weak-key TTL cache). Features no longer hand-roll window discovery.

## 4. Methoden, Metatables & Datenmodelle — ✅
Modules are plain `M` tables; adapters implement a documented interface. Metatables
used sparingly and deliberately (weak-key cache in `util.buffer`).

## 5. Dokumentation & Annotationen — ✅
Every module carries `---@module` + `---@brief`; config is fully typed in
`@types/config.lua`; feature functions have `---@param`/`---@return`. *Action:*
the two newest features type their config inline — keep central `@types` in sync
(done for `window_style` / `tree_open_keymaps`).

## 6. Testbarkeit & Lesbarkeit — 🟡
`test/smoke.lua` (headless, stub adapter) + `test/minimal_neotree.lua` (manual).
*Action:* add focused specs for high-traffic features (preview modes, copy_move,
path helpers).

## 7. Fehlerbehandlung & Validierung — ✅
`config.validate()` checks types before use; node/path presence is validated in
each feature before acting.

## 8. Performance & Speicher — 🟡
See [Zentral-Prinzipien](Zentral-Prinzipien.md) §8/§10. Hot paths are the
`CursorMoved` handlers (preview/current_hl) — debounced/cheap. *Action:* audit
per-event allocations.

## 9. Cache hitting — 🟡
Explicit TTL cache in `util.buffer`. *Action:* confirm persisted feature state
(recent_files/session/quick_open) lives under `stdpath`.

## 10. Schwache Tabellen & Memoisierung — ✅ / 🟡
`util.buffer` uses a weak-key cache (`__mode = "k"`). *Action:* consider
`lib.nvim.memo` for repeated pure computations (path→module, line counts).

## 11. Spezialfälle & NVIM-Config-spezifisch — 🟡
Windows/WSL/mac/linux branches exist where POSIX tools are unavoidable
(`file_permissions`, `trash`); system launchers now use `vim.ui.open`. *Action:*
keep the cross-platform matrix in mind for any new shell-outs.

## Annotations- / Import-Regeln — ✅
Features cache `require` results in top-level locals (`local notify = require(...)`)
rather than repeated `require("mod").fn`; import ordering is consistent
(util → features → adapter). Direct field lookups are hoisted where hot.

## Tables / Strings / GC / CPU — ✅ (mostly)
No obvious hot-path string concatenation in loops; `fs.collect_recursive` uses a
stack, not recursion; catalogs are built once. *Action:* spot-check
`get_visible_nodes` (recursive tree walk) for large trees.

## Concentrated action items
1. **lib.nvim adoption** — `map` / `usercmd` / `autocmd` / `augroup` / `hover_select`
   (biggest, touches every feature). See [Zentral-Prinzipien](Zentral-Prinzipien.md).
2. **Centralize FileType keymap binding** (N autocmds → 1 dispatcher).
3. **Broaden automated tests** beyond the smoke test.
