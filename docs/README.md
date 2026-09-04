# filetree.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | What has to be there first, and a spec per plugin manager |
| [configuration.md](configuration.md) | Every option, and the rule behind the defaults: everything is on unless it is marked opt-in |
| [troubleshooting.md](troubleshooting.md) | What `:checkhealth` asks, and what to do when the answer is a warning |

## Using it

| Page | Answers |
| --- | --- |
| [BINDINGS.md](BINDINGS.md) | The entry point to every keymap, `:Filetree` sub-command and autocommand — there are more than fit one readable page, so it hands off to [BINDINGS/](BINDINGS/) and says which page holds what |
| [commands.md](commands.md) | The `:Filetree` sub-command reference (the command name is configurable) |
| [keymaps.md](keymaps.md) | The tree-buffer keys, their defaults, and how to remap or switch one off |
| [menu.md](menu.md) | The context menu shipped for `nvzone/menu`, and what it offers |
| [api.md](api.md) | Every Lua function a config or another plugin can call |
| [WORKFLOW.md](WORKFLOW.md) | The different question: not what each feature does, but how they combine once several of them exist at once |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [FEATURES/](FEATURES/README.md) | One page per area — the core, navigation, file operations, search and paths, the UI, the backends, and the integrations — each about the decision rather than the feature list |

## Here, but not prose

**`BINDINGS.lua`** is the same catalogue as `BINDINGS.md`, machine-readable: it
returns every keymap, sub-command and autocommand as data, for anything that
wants to render or check them. **`install.json`** declares the external tools
this plugin can use, for `:Lib deps show filetree.nvim`.
