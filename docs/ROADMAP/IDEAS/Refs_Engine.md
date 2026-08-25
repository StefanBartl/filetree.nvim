# Reference engine — carrying refs along on move/rename

Status: ✅ **built.** The engine lives in
[lua/filetree/refs/](../../../lua/filetree/refs/), the documentation in
[docs/FEATURES/FILEOPS.md#references](../../FEATURES/FILEOPS.md#references),
the tests in [TESTS/refs/](../../../TESTS/refs/). This document stays as the
concept and decision record; what ended up different from the plan is under
"Deviations" at the bottom.

The idea, as originally put: `./README.md` holds a reference to `/Test.md`. I
move `Test.md` to `/docs/Test.md` — filetree scans the cwd for references,
lists them, and asks whether to update all of them, only some, or none.
Markdown first, Lua later, JS/TS later still.

---

## 1. Where things stood (what was already in the repo)

Worth stating, because the concept below builds no new subsystem: it
generalizes the existing one.

**Markdown refs — the pipeline existed in full**, in
[util/markdown_refs.lua](../../../lua/filetree/util/markdown_refs.lua):

- `prefetch(path)` starts the scan **before** anything is mutated (race-free:
  the mutation happens in the `await` callback, so the scan still sees the file
  at its old location), with `await_all()` for batches.
- `retarget(ref, new_path)` preserves the link style (`./x` stays `./x`, an
  absolute path stays absolute), with `relative_target()` as the fallback.
- `update(refs)` rewrites `](old)` to `](new)`, **content-verified** — a line is
  only touched if it still contains exactly the target that was scanned — and
  patches open buffers rather than only disk.
- UX: `confirm_choice` offering *Update all / Inspect first / Leave as-is*,
  where "Inspect" opens
  [util/refs_picker.lua](../../../lua/filetree/util/refs_picker.lua)
  (Telescope → fzf-lua → quickfix fallback, multi-select via Tab/C-a).

It was wired into: [smart_rename](../../../lua/filetree/features/fileops/smart_rename/init.lua),
[copy_move](../../../lua/filetree/features/fileops/copy_move/init.lua) (`cut` only, not `copy`),
[rename_batch](../../../lua/filetree/features/fileops/rename_batch/init.lua),
and [trash](../../../lua/filetree/features/fileops/trash/init.lua) (where refs are
marked `REF!`, or the delete is aborted).

**Code refs — present, but only half of it.**
`update_references_fallback()` in
`lua/filetree/features/fileops/smart_rename/init.lua:396` does a ripgrep scan
plus a textual rewrite after the rename, for **Lua** (`require`, including the
submodule cascade on directory renames), **Python** (`from x import`) and
**TS/JS** (`from "./x"`, `import("./x")`) — as a fallback for when no LSP client
served `workspace/willRenameFiles` (lua_ls never does).

## 2. The actual gaps

1. **Two separate worlds.** Markdown refs have prefetch, a selection UX, a
   picker, buffer patching. Code refs have none of it: they run **silently and
   unasked**, with no preview, no selection, no undo. So the UX you want exists
   already — just not for code.
2. **Only on rename.** The code-ref rewrite hangs off `smart_rename` alone. A
   move via `x`/`p` (copy_move), or a `rename_batch`, does **not** carry
   `require` paths along.
3. **Markdown needs a foreign plugin as a soft dependency** (`markdown.nvim`,
   `find_references`). Without it: `{}`, and the feature is silently off. Too
   little for a core feature of filetree.nvim.
4. **No dedicated move.** Moving is only possible in two steps (`x`, navigate,
   `p`). An `M` with a target prompt is missing.
5. **Incomplete link forms.** `apply_ref` only handles `](target)`. Not covered:
   reference definitions (`[id]: path`), wiki links, HTML (`<img src=…>`),
   frontmatter paths; anchors (`](x.md#section)`) only work by accident,
   because the anchor happens to be part of the target.

---

## 3. The target picture: one ref engine with a provider registry

A `filetree.refs` module as the **only** place that knows: "file X is moving to
Y — who points at X, and what should the reference say afterwards?"

```
                      ┌──────────────────────────────┐
  smart_rename ──┐    │  filetree.refs               │
  copy_move    ──┼──► │  scan → resolve → confirm →  │ ──► apply (buffer/disk)
  rename_batch ──┤    │  apply                       │
  trash        ──┘    └──────────┬───────────────────┘
                                 │ provider registry
             ┌───────────────────┼────────────────────┬─────────────┐
          markdown              lua               python         ts/js
```

### The provider interface

```lua
---@class FiletreeRefProvider
---@field name string                          -- "markdown" | "lua" | ...
---@field handles fun(path: string): boolean   -- can this file be referenced at all?
---@field extensions string[]                  -- which files are searched (rg -g)
---@field needles fun(old: string, root: string): string[]  -- fixed strings for the rg prefilter
---@field extract fun(file: string, lines: string[], old: string, root: string): FiletreeRef[]
---@field retarget fun(ref: FiletreeRef, new: string): string
```

```lua
---@class FiletreeRef
---@field file string       -- the file holding the reference (absolute)
---@field line integer      -- 1-based
---@field col? integer
---@field text string       -- the line as it was at scan time (content verify)
---@field target string     -- the reference as written ("./Test.md", "foo.bar")
---@field new_target string -- set by retarget()
---@field provider string
---@field display string    -- for the picker
```

The data model is deliberately **almost identical** to what `markdown_refs`
gets from markdown.nvim today (`file/line/target/display`) — existing callers
and `refs_picker` keep working with minimal change.

### The pipeline (the same for every filesystem mutation)

1. **Prefetch** on the keypress — `refs.prefetch({paths}, opts)` returns a
   handle. It runs while the user is still typing or navigating. The mechanics
   are taken from `markdown_refs.prefetch/await_all` unchanged.
2. **Scan** in two stages: `rg --files-with-matches --fixed-strings` with the
   provider's `needles` as a coarse prefilter (fast, ignores `.git` and
   `node_modules`, respects `.gitignore`), then `extract()` per candidate for
   the exact hit list with line and column. No full scan of the cwd.
3. **Mutation** (rename/move) — inside the `await` callback, so guaranteed after
   the scan.
4. **Resolve** — `retarget(ref, new_path)` per ref, style-preserving.
5. **Confirm** — one chooser across *all* providers together:
   `"7 references in 4 files (5 markdown, 2 lua)"` →
   **Update all / Select / Show diff / Leave as-is**.
6. **Apply** — grouped per file, content-verified; open buffers are patched
   live (the logic from `markdown_refs.update()` moved up), unmodified buffers
   written back `noautocmd`, modified ones left modified.

### Undo

New, and important the moment more than Markdown is touched: `refs.apply()`
returns an undo token (the affected files plus their original lines).
`:Filetree refs undo` rolls the last apply back. For open buffers their native
undo suffices; for files on disk the token is what makes it possible. Modelled
on [trash/undo.lua](../../../lua/filetree/features/fileops/trash/undo.lua).

---

## 4. UX: the `M` move

A new `fileops/move` feature — its own module rather than a keymap inside
`copy_move`, because the target prompt has nothing to do with the clipboard
logic:

```
M   → prefetch starts immediately for the node (or all marks)
    → kit.input "Move to: " with directory completion (default: cwd-relative)
    → conflict check (Overwrite / Keep both / Cancel — reusing copy_move's logic)
    → fsops.rename_file()   (the central mutation chokepoint, Windows retry included)
    → buffer.relocate()
    → refs pipeline, steps 4–6
```

The chooser afterwards:

```
  7 reference(s) to Test.md in 4 file(s)
    ▸ Update all
    ▸ Select…            → refs_picker (Tab/C-a multi-select, preview)
    ▸ Show diff          → a scratch buffer with a unified diff of every change
    ▸ Leave as-is
```

"Select…" is, by your own estimate, the rarest case — hence option 2 rather
than option 1, and no keymap shortcut of its own.

---

## 5. Growing the providers, in phases

### Phase 1 — Markdown, in-tree

Its own scanner; `markdown.nvim` goes from being a prerequisite to being an
accelerator (when present, keep using its `find_references` — the interface
fits). To cover:

| Form | Example |
|---|---|
| Inline link | `[text](./Test.md)` |
| Image | `![alt](./img/x.png)` |
| Anchor/title | `[t](./Test.md#section "Title")` |
| Reference definition | `[id]: ./Test.md` |
| Wiki link | `[[Test]]`, `[[Test\|Alias]]` (opt-in; not standard Markdown) |
| HTML inside Markdown | `<img src="./img/x.png">`, `<a href="…">` |

The important part of the matching: resolve the target **relative to the
referencing file**, normalize it to an absolute path, and compare *that* with
`old_path` — not the text. Otherwise `../Test.md` from `docs/` does not match,
and `Test.md` wrongly matches in every subdirectory. On Windows:
`path.slashify` plus a case-insensitive comparison.

Also **directory moves**: every ref whose resolved path lies under the old
directory is rewritten (a prefix match on a segment boundary).

### Phase 2 — Lua

The rewrite already exists (`file_to_lua_module`, the submodule cascade,
`require "x"` and `require("x")`). What is left:

- pull it out of `smart_rename` into a provider,
- extend `extract()` so hits come out *with line numbers* (today the patch is
  applied blind, which is why there is no preview),
- which then makes it available for move and batch automatically,
- edges: `require` inside strings or comments, `pcall(require, "x")`,
  `vim.pack`/`lazy` specs holding module names, `package.path` special cases.
  The `lua/` root match is already greedy on the *last* `/lua/`, which is
  right.

### Phase 3 — Python

Also present (`file_to_python_module`). Same treatment as Lua, plus relative
imports (`from .x import y`), which are not covered today.

### Phase 4 — JS/TS

Deliberately last, because this is where most of the work sits:

- extensionless specifiers, `/index` collapsing, the `.js` extension in ESM
  imports pointing at TS sources, `.mjs`/`.cjs`,
- `tsconfig.json` `paths`/`baseUrl` aliases (`@/components/x`) — without those
  the rewrite is nearly worthless in modern projects, so `tsconfig`/`jsconfig`
  has to be parsed (including `extends`) and alias targets resolved along with
  it,
- `require()` (CJS), dynamic `import()`, `export … from`,
- `package.json` `exports`/`imports` (`#internal/x`), monorepo workspaces.

A realistic cut: **4a** = relative specifiers plus `/index` plus extensions
(already there in the core), **4b** = tsconfig aliases. Anything beyond that
only when no LSP is present — `tsserver` handles `willRenameFiles` and is then
the better source anyway. Which is exactly why "LSP first, textual as a
fallback" is already the right order in `smart_rename`.

---

## 6. Config schema

Replaces the `check_markdown_refs` / `refs_picker_prefer` pair that is
currently duplicated across three features (see
`lua/filetree/@types/config.lua:254`, `:401`, `:433`, `:569`) with **one**
block the features reference:

```lua
refs = {
  enabled   = true,
  providers = {
    markdown = true,
    lua      = true,
    python   = true,
    ts_js    = false,   -- opt-in while phase 4b is not in place
  },
  on_move   = "ask",    -- "ask" | "auto" | "off"
  on_rename = "ask",
  on_delete = "ask",    -- trash: mark refs as REF!
  copy      = false,    -- a copy never breaks a reference
  picker    = "auto",   -- auto | telescope | fzf-lua | quickfix
  prefer_lsp = true,    -- willRenameFiles wins; textual only as a fallback
  scan = {
    root              = "project",  -- "project" | "cwd"
    respect_gitignore = true,
    max_files         = 5000,       -- beyond that: warn rather than scan
    timeout_ms        = 3000,
  },
  undo = true,
}
```

Migration: the old keys keep being read and are mapped onto the new block with
a deprecation notice.

---

## 7. Risks and edges

- **The "file gone before the scan" race** — solved by prefetch/`await`; it has
  to be honoured by every new caller.
- **Stale refs** in open, unsaved buffers — solved by the content verify
  (`apply_ref` checks the line); to be carried over to the code providers.
- **Performance** — the rg prefilter is mandatory; without `rg` the feature
  degrades to "silently off" (today's behaviour) rather than to a full Lua
  scan.
- **False positives** in code (a module name inside a string or comment).
  Which is exactly why preview and selection are worth more for code refs than
  for Markdown ones.
- **Windows** — separators and case: `path.slashify` consistently at every
  comparison site, and case-insensitive comparisons.
- **Symlinks** — genuinely possible since `link_create`: a ref to a symlink
  must not be rewritten to point at its target.
- **Binary and large files** — the provider's extension whitelist already
  covers this.

---

## 8. Implementation order

| # | Step | Effort |
|---|---|---|
| 1 | `filetree.refs` plus the provider registry and the ref data model; `markdown_refs` as the first provider behind it (behaviour unchanged) | M |
| 2 | The shared confirm/picker/apply layer plus the undo token | M |
| 3 | The Markdown provider in-tree (every link form, path resolution instead of text comparison) | M–L |
| 4 | The Lua provider extracted from `smart_rename`, with line-level hits | S–M |
| 5 | The `M` move feature (target prompt, conflict reuse, marks support) | S |
| 6 | The refs pipeline on `copy_move` (cut) and `rename_batch`, for **all** providers | S |
| 7 | The `refs` config block plus migration of the old keys, plus documentation | S |
| 8 | The Python provider (including relative imports) | S |
| 9 | TS/JS phase 4a, then 4b (tsconfig aliases) | L |

## 9. Tests

[TESTS/refs](../../../TESTS/refs) already exists with fixtures — extend the
pattern: one fixture tree per provider, a table test of
`(old layout, move, expected layout)`, plus the negative cases (a ref inside a
comment, a same-named prefix `testfs.rem` vs `testfs.rem_other`, a ref to a
symlink, an unsaved buffer with shifted lines).

---

## 10. Deviations from the plan

What was decided differently during implementation than sketched above:

- **Markdown without markdown.nvim, immediately.** Step 3 (an own scanner) was
  not deferred but built straight away — otherwise the soft dependency would
  have kept deciding whether a core feature runs at all. `markdown.nvim` is no
  longer used; `util/markdown_refs.lua` is gone.
- **Path keys are purely lexical.** `fnamemodify(":p")` silently expands an 8.3
  short name on Windows whenever it has to rewrite the path anyway
  (`C:/Users/STEFAN~1/…` → `C:/Users/StefanBartl/…`), but not when the path is
  already clean. So the same file ended up with two different keys depending on
  whether the reference was written `./Test.md` or `Test.md` — and **every**
  dotted reference was missed. `refs/pathutil.lua` therefore resolves purely
  through `vim.fs.normalize` and does not touch the filesystem at all.
- **Content verification by byte range rather than by pattern.** Every ref
  carries `col` plus `#target`, and exactly that span is replaced. That was not
  planned, but it makes several links on one line correct (applied right to
  left) and removes the need to escape Lua patterns entirely.
- **ts_js: phases 4a and 4b together.** The tsconfig `paths` resolution is in
  (including the `extends` chain and JSONC pre-cleaning), because relative
  specifiers alone hit almost nothing in alias-heavy projects. The provider is
  **off by default** regardless — with `tsserver` running, `willRenameFiles` is
  the better source.
- **Python relative imports only where they stay expressible.** If a file
  leaves its package, rewriting the import would be a change of semantics; such
  refs are counted and reported ("N references not automatically rewritable")
  rather than guessed at.
- **Two extra utilities** that were not in the concept but became visible
  during the change: `util/mutate.lua` (the Windows retry plus the EXDEV
  fallback, previously copied three times) and `util/conflict.lua` (exists /
  remove_existing / unique_name, shared by paste and move).
- **No rg does not mean total failure.** Instead of "silently off" (as the
  concept had it), there is a capped libuv walk as a fallback.
