# Zentrale Prinzipien — applied to filetree.nvim

Audit of filetree.nvim against
[`Zentrale-Prinzipien.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md).
Status: ✅ good · 🟡 partial / improvable · ❌ gap (action item).

## lib.nvim usage (the "WICHTIG" preamble)

| Helper | Status | Notes |
|---|---|---|
| `lib.notify` | ✅ | `util.notify` delegates to `lib.nvim.notify` (local fallback). |
| `lib.map` | ❌ | features call `vim.keymap.set` directly — should route through `lib.nvim.map`. |
| `lib.usercmd` | ❌ | `commands.lua` uses `nvim_create_user_command` directly. |
| `lib.autocmd` / `lib.augroup` | ❌ | every feature uses raw `nvim_create_autocmd` / `nvim_create_augroup`. |
| `lib.cross` | 🟡 | `util.platform` mirrors it; system launchers now use `vim.ui.open`. Migrate to `lib.nvim.cross`. |
| `lib.hover_select` | ❌ | pickers use `vim.ui.select` / custom floats directly. |
| `lib.lazy` | 🟡 | own registry resolver loads features lazily; could use `lib.lazy` proxy. |
| `lib.memo` | ❌ | `util.buffer` hand-rolls a TTL cache; could use `lib.memo`. |

**Action:** a `lib.map` / `lib.autocmd` / `lib.augroup` migration is the single
biggest lib-adoption item (touches every feature). Track under
[ROADMAP.md → lib.nvim adoption](../ROADMAP.md).

## The 10 principles

**1. Events bündeln, Logik entkoppeln** — 🟡
Each feature registers its own `FileType` autocmd to bind tree-buffer keymaps →
N autocmds on the same event. `hooks_api` exists for decoupling but keymap
binding is not centralized. *Action:* one FileType dispatcher that binds all
enabled features' keymaps (N→1).

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

Structurally sound (augroups, lazy loading, event choice). The concentrated work
is **lib.nvim adoption** (map/usercmd/autocmd/augroup/hover_select) and
**centralizing the per-feature FileType keymap binding**.
