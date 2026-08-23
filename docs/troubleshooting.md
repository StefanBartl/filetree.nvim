# Troubleshooting

## Health check

```vim
:checkhealth filetree
```

Reports the status of each feature category (in the same order as
`filetree.features.CATEGORY_ORDER`) and flags missing adapters or dependencies.

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

## Known adapter caveats

nvim-tree's `update_focused_file.update_root.enable` is not a drop-in
equivalent of neo-tree's `bind_to_cwd`, and can fight `cwd_sync`'s own cwd
management. See
[cwd_sync `reveal` per adapter](configuration.md#cwd_sync-reveal-per-adapter)
in the configuration guide for the full explanation and the recommended
setting per adapter.
