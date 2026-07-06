# TESTS/

Fixture-based regression tests that need real, on-disk multi-file projects —
too heavy for the unit-style checks in `test/` (which run against in-memory
stubs). Each subfolder is self-contained: fixtures + a runnable `run.lua`.

## smart_rename_refs/

Verifies the `smart_rename` feature's require()/import reference-update
fallback (see [`lua/filetree/features/fileops/smart_rename/init.lua`](../lua/filetree/features/fileops/smart_rename/init.lua)).
That fallback rewrites cross-file references on rename/move whenever no LSP
client applied a workspace edit — which, for Lua, is always (lua_ls doesn't
implement `workspace/willRenameFiles`).

Run it from the repo root:

```
nvim --clean --headless -u NONE -l TESTS/smart_rename_refs/run.lua
```

It copies `fixtures/<lang>/` to a scratch temp dir, renames the "hub" module
via `smart_rename.rename_current()` (stubbed adapter + `vim.ui.input`, no real
tree plugin or LSP server needed), and asserts every referencing file was
rewritten — plus a negative-control file with a similar-but-different module
name that must stay untouched.

Currently covers Lua, Python, and TS/JS (incl. `.tsx`/dynamic `import()`).

To add another language: drop a `fixtures/<lang>/` tree with a project marker
file (anything in `project_root`'s marker list works — `.luarc.json`,
`pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, ...) and add a
`LANGS` entry in `run.lua` pointing at the hub file and the files that
reference it. Note: `smart_rename`'s fallback only has a pattern replacer for
lua/python/typescript/javascript today — a new language needs a matching
branch in `build_line_replacer` (and `reference_scan_spec`) before a fixture
for it will do anything.
