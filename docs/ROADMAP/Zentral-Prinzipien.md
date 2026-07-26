# Zentrale Prinzipien — applied to filetree.nvim

Audit of filetree.nvim against
[`Zentrale-Prinzipien.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md).
Status: ✅ good · 🟡 partial / improvable · ❌ gap (action item).

## lib.nvim usage (the "WICHTIG" preamble)

| Helper | Status | Notes |
|---|---|---|
| `lib.notify` | ✅ | `util.notify` delegates to `lib.nvim.notify` (local fallback). |
| `lib.map` | ✅ | `util.map` delegates to `lib.nvim.map` (local `vim.keymap.set` fallback); every feature goes through it. |
| `lib.usercmd` | ✅ | `commands.lua` builds `:Filetree`/`:Ft` via `lib.nvim.usercmd.composer`. |
| `lib.autocmd` / `lib.augroup` | ✅ | `util.autocmd` delegates to `lib.nvim.autocmd`; every feature goes through it (native augroup API kept for idempotent re-setup, see the module's doc comment). |
| `lib.cross` | 🟡 | `util.platform` mirrors it; system launchers now use `vim.ui.open`. Migrate to `lib.nvim.cross`. |
| `lib.hover_select` | ✅ | `util.select` wraps it; batch choosers (trash, copy_move, etc.) go through it. |
| `lib.lazy` | 🟡 | own registry resolver loads features lazily; could use `lib.lazy` proxy. |
| `lib.memo` | ❌ | `util.buffer` hand-rolls a TTL cache; could use `lib.memo`. |

**Action:** `lib.map` / `lib.usercmd` / `lib.autocmd` / `lib.augroup` /
`lib.hover_select` adoption is done. Remaining: `lib.cross` (partial) and
`lib.memo` (not started).

## The 10 principles

**1. Events bündeln, Logik entkoppeln** — ✅
A single central dispatcher (`util.tree_attach`) owns the one `FileType`
autocmd; every feature registers an `on_attach(buf)` callback with it instead
of its own autocmd (N→1). `hooks_api` remains for decoupling other
cross-feature signals.

**2. Eigene Logik lazy laden** — ✅
`features/init.lua` resolver loads a module only when enabled; cross-feature refs
use `registry.load(name)` inside functions; adapter/plugin deps are `pcall`-guarded.

**3. Kontext statt Mehrfach-API-Zugriffe** — 🟡
`util.buffer.context()` exists, but features call `adapter.get_current_node()` /
`vim.fn.*` repeatedly per action. *Action:* pass a resolved node/context object
into feature handlers instead of re-querying.

**4. Autocommand-Gruppen sauber nutzen** — ✅
Every feature uses a named `filetree_<feature>` augroup, cleared on setup and
teardown → reload works without restart; origin is obvious.

**5. Event oder Command?** — ✅
Automatic behaviours (`preview`, `current_hl`, `cwd_sync`, `auto_reveal`,
`auto_resize`) are state-driven and mostly opt-in / default-off; the rest are
keymap/`:Filetree`-command driven.

**6. Treesitter notwendig?** — ✅ (N/A)
filetree uses no Treesitter; `outline` uses LSP symbols with a ctags fallback.

**7. Cache vorhanden und explizit?** — 🟡
`util.buffer` has an explicit TTL cache invalidated on `BufDelete`. *Action:*
verify `recent_files` / `quick_open` / `session` persist under `stdpath("data")`/
`stdpath("cache")`, not runtime state.

**8. Allokationen im Hot-Path vermeiden** — 🟡
`current_hl` is debounced; `preview` buffer-mode is cheap (`bufadd` +
`win_set_buf`). *Action:* audit `CursorMoved` handlers for per-event table churn.

**9. Debugbarkeit eingeplant?** — 🟡
`notify.debug` + per-feature `silent` flags exist; `test/smoke.lua` allows
isolated testing. *Action:* add a single global debug switch (`config.debug`).

**10. Laufzeit wichtiger als Startup?** — ✅
The few `CursorMoved`/`BufEnter` handlers are minimal/guarded/debounced; startup
work is deferred (VimEnter, `vim.schedule`).

## Summary

Structurally sound (augroups, lazy loading, event choice). **lib.nvim adoption**
(map/usercmd/autocmd/augroup/hover_select) and **centralizing the per-feature
FileType keymap binding** (`util.tree_attach`) are both done. Remaining
concentrated work: `lib.cross`/`lib.memo` adoption and broader test coverage
(see [Arch&Coding](Arch&Coding.md)).
