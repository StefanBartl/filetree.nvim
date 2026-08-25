# TESTS/

Everything CI runs, plus the manual pass it cannot.

| | |
| --- | --- |
| [`smoke.lua`](smoke.lua) | integration: every feature module loads, opt-out defaults resolve, registry resolver + binding catalog work |
| [`units.lua`](units.lua) | unit: util layer, neo-tree adapter helpers, the reference engine's apply/undo layer and the chooser |
| [`menu.lua`](menu.lua) | unit: `integrations/menu.lua`, against a stubbed `filetree` module |
| [`cwd_mode.lua`](cwd_mode.lua) | unit: the cwd/root policy feature, against a stub adapter and a temp tree |
| [`refs/`](refs/) | fixture-based: real on-disk multi-file projects, described below |
| [`MANUAL.md`](MANUAL.md) | the manual checklist for what a headless run cannot reach — real neo-tree, real floats, real clipboard |

The four `.lua` suites are headless and need no tree plugin (stub adapter);
exit 0 is a pass. `MANUAL.md` describes each in more detail and carries the
lib.nvim resolution notes.

## refs/

Fixture-based regression tests that need real, on-disk multi-file projects —
too heavy for the unit-style checks above, which run against in-memory stubs.
Self-contained: fixtures plus a runnable `run.lua`.

Verifies the reference engine ([`lua/filetree/refs/`](../lua/filetree/refs/))
and the features that drive it: cross-file references — markdown links,
`require()`/`import` statements — must follow a file when it is renamed or
moved, and must NOT follow a similar-but-different name.

Run it from the repo root:

```
nvim --clean --headless -u NONE -l TESTS/refs/run.lua
```

For each language it copies `fixtures/<lang>/` to a scratch temp dir, renames
the "hub" module through the real feature (`smart_rename.rename_current()`
with a stubbed adapter and a stubbed `kit.input` — no tree plugin, no LSP
server, no floating window), and asserts every referencing file was rewritten
— plus a negative control that must stay untouched. It also covers the
directory-rename submodule cascade, the live-buffer patch (references in an
open buffer are patched in memory, not only on disk), the `M` move feature,
and `refs undo`.

The engine runs in `auto` mode there: the chooser is UI, covered by
`TESTS/units.lua`; this suite is about what lands on disk.

Currently covers Lua, Python, TS/JS (incl. `.tsx`/dynamic `import()`) and
Markdown (inline links, HTML `href=`, reference definitions).

To add another language: drop a `fixtures/<lang>/` tree with a project marker
file (anything in `project_root`'s marker list works — `.luarc.json`,
`pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, ...) and add a
`LANGS` entry in `run.lua` pointing at the hub file and the files that
reference it. Note: a language needs a provider in
[`lua/filetree/refs/providers/`](../lua/filetree/refs/providers/) before a
fixture for it will do anything.
