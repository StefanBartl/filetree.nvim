# filetree.nvim — Roadmap

Index over `docs/ROADMAP/`. Every document there is a design note, an audit or a
decision record; this file says what each one is and whether it is still live,
so a reader does not have to open four files to find the one that is still open.

For what the plugin *does* today, see [`docs/FEATURES/`](FEATURES/); for the
bindings, [`docs/BINDINGS/`](BINDINGS/).

## Live — open work

| Document | What it is | Still open |
| --- | --- | --- |
| [`ROADMAP/NEOTREE_FEATURES.md`](ROADMAP/NEOTREE_FEATURES.md) | Audit of the Neo-tree setup in the personal nvim config, mapped feature by feature onto filetree.nvim's registry — the port map. | Two of the four gaps it found. Both are about Neo-tree's *source* model (a buffers source, a dormant neotest source), which filetree.nvim has no concept for; both are deliberately parked, not forgotten. |
| [`ROADMAP/IDEAS/Neotree_Sources.md`](ROADMAP/IDEAS/Neotree_Sources.md) | Whether to rebuild Neo-tree's `sources/` registry. | Yes — Phase 4, low priority. Current thinking: a small recipe collection covers the actual pain ("setup was a pain") more cheaply than a template engine. |

## Reference — decided or shipped

| Document | What it is | Status |
| --- | --- | --- |
| [`ROADMAP/PDFPORT_INTEGRATION.md`](ROADMAP/PDFPORT_INTEGRATION.md) | Who owns what in "open a PDF from the tree" — filetree.nvim, pdfport.nvim, or the tree manager. | Decided and built: `system.pdf_open` and `system.pdf_create`. Kept as the record of *why* the split is where it is. |
| [`ROADMAP/IDEAS/Refs_Engine.md`](ROADMAP/IDEAS/Refs_Engine.md) | The reference engine that follows a move/rename through the imports pointing at the file. | Shipped — `lua/filetree/refs/`, documented in [`FEATURES/FILEOPS.md`](FEATURES/FILEOPS.md). Kept as the design record. |

## Known issues not tracked in any of the above

- **The suites fail on Windows.** `test/units.lua` (4) and `test/cwd_mode.lua`
  (41) compare temp-directory paths and hit 8.3 short paths against long paths
  (`C:/Users/STEFAN~1/…` vs `C:/Users/StefanBartl/…`). Linux CI is green, so
  this is an expectation problem in the tests, not a defect in the plugin — but
  it makes the suites unusable as a local gate on Windows.
