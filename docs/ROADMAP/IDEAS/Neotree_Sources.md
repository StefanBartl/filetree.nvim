# Neotree sources

| **sources/ + icons/** | A lazy source registry, 3 icon families (nerd/codicons/common), responsive sizing |

Reproduce neotree's `sources` feature — 🔲 **phase 4, low priority.** Verified: `lua/config/neotree/sources/registry.lua` is currently a simple lazy loader (register/load/is_loaded/list), not a template system — the wish does not exist in the code yet. Instead of a full template engine: first a small collection of recipes / copy-paste configs (2-3 common source setups) in the `filetree.nvim` README or in `docs/` — it covers the actual pain point ("setting it up was a pain") more cheaply than a new system.

Feedback: it would be great, though, if somebody using filetree.nvim with neotree as the engine could simply enable/disable the sources from the filetree.nvim user config (the spec).
