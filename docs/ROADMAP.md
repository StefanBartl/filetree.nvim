# filetree.nvim — Roadmap

Index over `docs/ROADMAP/`. Every document there is a design note, an audit or a
decision record; this file says what each one is and whether it is still live,
so a reader does not have to open four files to find the one that is still open.

For what the plugin *does* today, see [`docs/FEATURES/`](FEATURES/); for the
bindings, [`docs/BINDINGS/`](BINDINGS/).

## Live — open work

| Document | What it is | Still open |
| --- | --- | --- |
| [`ROADMAP/CWD_MODES.md`](ROADMAP/CWD_MODES.md) | Implementation status for the cwd/root policy stack — what shipped, in which commit, and what is still open. Moved here from `docs/FEATURES/` on 2026-08-26: it is a status note, not a catalogue theme, and the features parser was reading its `Done`/`Open` headings as features. The feature itself is catalogued in [`FEATURES/CORE.md`](FEATURES/CORE.md#cwd-mode). | Its `Open` section. |
| [`ROADMAP/IDEAS/Neotree_Sources.md`](ROADMAP/IDEAS/Neotree_Sources.md) | Whether to rebuild Neo-tree's `sources/` registry. | Yes — Phase 4, low priority. Current thinking: a small recipe collection covers the actual pain ("setup was a pain") more cheaply than a template engine. |

## Open work not tied to a document

- **Optimize `cwd_mode`'s badge.** `component()` returns the badge as plain
  text for whatever draws the statusline — native `%{v:lua…}`, heirline, or
  lualine, all three documented, none of them a dependency. It is the piece
  that gets touched if the personal config ever swaps its statusline
  framework, so it is worth being cheap and correct before that: the redraw
  path recomputes on every call, and `refresh()` asks the host to redraw
  rather than the other way round.

  Context for *why* this came up lives in the config, not here:
  `nvim/docs/ROADMAP/IDEAS/nvim.nvim.md`, the UI-plugin section.

## Reference — decided or shipped

| Document | What it is | Status |
| --- | --- | --- |
| [`ROADMAP/PDFPORT_INTEGRATION.md`](ROADMAP/PDFPORT_INTEGRATION.md) | Who owns what in "open a PDF from the tree" — filetree.nvim, pdfport.nvim, or the tree manager. | Decided and built: `system.pdf_open` and `system.pdf_create`. Kept as the record of *why* the split is where it is. |
| [`ROADMAP/IDEAS/Refs_Engine.md`](ROADMAP/IDEAS/Refs_Engine.md) | The reference engine that follows a move/rename through the imports pointing at the file. | Shipped — `lua/filetree/refs/`, documented in [`FEATURES/FILEOPS.md`](FEATURES/FILEOPS.md). Kept as the design record. |

## Known issues not tracked in any of the above

- **`TESTS/refs/` is 52 of 54.** Two cases fail, both the same shape: a rename
  updates `lua/proj/nested/b.lua` but not `lua/proj/nested/deep/c.lua`, one
  level further down, even though both files hold the byte-identical
  `require("proj.util.shared")`. The plain rename and the directory-cascade
  case each fail on that one file.

  What it is *not*, so the next reader does not re-check: not a regression
  (identical before and after the 2026-08-25 cross-platform round), not the
  scan backend (identical with ripgrep and with the libuv fallback — and rg
  itself lists `nested/deep/c.lua` when run by hand with the same arguments),
  and not the candidate set. The candidates arrive; the rewrite skips that one
  file. So the defect sits in the apply layer, downstream of `refs/scan.lua`.

  One lead worth starting from: for a ripgrep-relative hit,
  `filetree.util.path.to_absolute` returns
  `C:\repos\…\.\lua\proj\nested\deep\c.lua`
  — backslashes kept and a literal `\.\` segment left in the middle. If
  anything downstream dedups or matches on that string, an unnormalized
  path is the first place to look.

- ~~**The suites fail on Windows.**~~ Fixed 2026-08-25. The 45 failures
  (`units.lua` 4, `cwd_mode.lua` 41) were *not* an expectation problem as
  recorded here: `lib.nvim`'s `normkey` returned a different key for the same
  path before and after `mkdir`, because `fs_realpath` fails on a path that
  does not exist yet and the fallback kept the 8.3 spelling. Fixed at the root
  in lib.nvim; 41 of the 45 went away without a test being touched. Of the
  rest, two were a real defect here — `find_files`' builtin backend globbed a
  tilde path and got an empty list — and two were genuine expectations. All
  four suites are green on Windows now.
