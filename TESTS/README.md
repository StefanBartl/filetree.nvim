# TESTS/

Fixture-based regression tests that need real, on-disk multi-file projects —
too heavy for the unit-style checks in `test/` (which run against in-memory
stubs). Each subfolder is self-contained: fixtures + a runnable `run.lua`.

## refs/

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
`test/units.lua`; this suite is about what lands on disk.

Currently covers Lua, Python, TS/JS (incl. `.tsx`/dynamic `import()`) and
Markdown (inline links, HTML `href=`, reference definitions).

To add another language: drop a `fixtures/<lang>/` tree with a project marker
file (anything in `project_root`'s marker list works — `.luarc.json`,
`pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, ...) and add a
`LANGS` entry in `run.lua` pointing at the hub file and the files that
reference it. Note: a language needs a provider in
[`lua/filetree/refs/providers/`](../lua/filetree/refs/providers/) before a
fixture for it will do anything.
