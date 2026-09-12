# Quickstart

Install it, open your tree, and the full keymap set is already bound — that
is the whole point of opt-out defaults. `?` in the tree shows what is
available in the buffer you are in.

Then turn off what you do not want, and turn on what stays off by default:

```lua
require("filetree").setup({
  adapter = "neotree",
  features = {
    shell_run   = { enabled = false }, -- disable a default-on feature
    auto_resize = { enabled = true },  -- enable a default-off feature
    marks       = { keymap = "M" },    -- keep it on, remap its key
  },
})
```

Verify your setup any time with:

```vim
:checkhealth filetree
```

## See also

- [What you get with the defaults](what-you-get.md) — the things worth knowing on day one.
- [All options](configuration.md) — every `setup()` option and its default.
