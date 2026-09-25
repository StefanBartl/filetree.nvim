# Troubleshooting

## Health check

```vim
:checkhealth filetree
```

Reports the status of each feature category (in the same order as
`filetree.features.CATEGORY_ORDER`) and flags missing adapters or dependencies. It also
says whether the pickers.nvim integration is active and, if not, which of its three
conditions fails, and lists any key that two actions claim.

## Debug notifications

```lua
require("filetree").setup({
  debug = true,  -- show internal debug notifications
})
```

Turn this on when a feature isn't behaving as expected — it surfaces internal
notifications that are otherwise silent.

## References were not updated after a rename/move

Start with `:Filetree refs status` — it prints, in one screen, whether the
engine is on, what each operation is set to (`ask` / `auto` / `off`), which
providers are enabled, whether ripgrep was found, and whether there is an undo
token pending. `:checkhealth filetree` shows the same block.

The usual causes, in the order worth checking:

- **The provider is off.** `ts_js` is opt-in
  (`refs = { providers = { ts_js = true } }`) because `tsserver` does the job
  better via `willRenameFiles` when it is running.
- **A language server already handled it.** With `prefer_lsp = true` (the
  default) the textual code providers stand down when a client applied a
  workspace edit — the references *were* updated, just not by filetree.
- **The reference is not one of the covered forms.** See the provider table in
  [FEATURES/FILEOPS.md](FEATURES/FILEOPS.md#references); `[[wiki]]` links in
  particular are off unless `refs.wiki_links = true`.
- **The scan stopped early.** Without ripgrep the fallback walk is capped at
  `refs.scan.max_files` (5000) and says so; installing ripgrep is the better
  fix, raising the cap the quick one.
- **The file lives outside the scan root.** `refs.scan.root` defaults to
  `"project"` (nearest root marker); a reference in a *different* project is
  deliberately out of scope. `"cwd"` widens it.

If the wrong thing was rewritten, `:Filetree refs undo` puts the last batch
back, line for line.

## Neo-tree repeats "Error setting nodes" and dumps the whole tree

```
[Neo-tree ERROR] Error setting nodes:  .../nui/tree/init.lua:494:
attempt to index local 'node' (a nil value)
```

An upstream inconsistency between neo-tree and nui.nvim, not a filetree
setting: once neo-tree's node index has lost a subtree it still lists, every
render throws again, so the messages come in series with a full `vim.inspect`
of the tree behind each one. Closing and re-opening neo-tree is the manual way
out.

The `tree_integrity` feature prevents it, and repairs a tree that is already in
that state on the next render. It is **on by default** — if you see this error,
check that it is actually running:

```lua
:lua print(require("filetree.features.infra.tree_integrity").installed())
```

`false` means either the feature is disabled in your config, or the adapter in
use is not neo-tree (no other adapter uses nui), or no tree buffer has been
opened yet — the patch installs on the first one. `:Filetree health` reports
the same thing, plus how many stale ids it has had to drop.

See [BACKENDS.md → Tree Integrity](FEATURES/BACKENDS.md#tree-integrity) for the
mechanism.

## A key does nothing, or does something else

Two filetree actions on one key: Vim does not complain, the later `:map` wins, and
the other action silently loses its key — which one is later depends on attach
order, so it can even differ between sessions. filetree's own defaults never do
this, but keys you set yourself can.

```vim
:Filetree keys
```

lists every key claimed by more than one action (the live one marked), recommends
free alternatives, and moves the action you pick for this session; it copies the
`setup()` fragment that makes the change permanent. The same list is the
**conflicts** page of the `?` cheatsheet (`<CR>` there starts the same flow) and a
warning in `:checkhealth filetree`. An action bound per buffer (`preview`) cannot be
moved while the session runs — set its key in `setup()`.

A key that filetree binds over one of neo-tree's own (`/`, `i`, `m`) is deliberate
and not a conflict in this sense; see *Known conflicts* in
[BINDINGS/KEYMAPS.md](BINDINGS/KEYMAPS.md).

## `f` / `gr` do not open pickers.nvim

`:checkhealth filetree` → "pickers.nvim integration" names the condition that fails:
pickers.nvim missing (or too old to ship `pickers.integrations.filetree`),
`integrations.pickers = false` here, or `filetree = { enabled = false }` (or no
picker engine) on the pickers.nvim side. `f`/`gr` fall back to telescope / fzf-lua /
mini.pick / the built-in backend in every one of those cases.

## Known adapter caveats

nvim-tree's `update_focused_file.update_root.enable` is not a drop-in
equivalent of neo-tree's `bind_to_cwd`, and can fight `cwd_sync`'s own cwd
management. See
[cwd_sync `reveal` per adapter](configuration.md#cwd_sync-reveal-per-adapter)
in the configuration guide for the full explanation and the recommended
setting per adapter.
