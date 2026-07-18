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

## Known adapter caveats

nvim-tree's `update_focused_file.update_root.enable` is not a drop-in
equivalent of neo-tree's `bind_to_cwd`, and can fight `cwd_sync`'s own cwd
management. See
[cwd_sync `reveal` per adapter](configuration.md#cwd_sync-reveal-per-adapter)
in the configuration guide for the full explanation and the recommended
setting per adapter.
