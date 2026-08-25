# Concept: pdfport.nvim × filetree.nvim × filetree manager

> The division of responsibility for the "open a PDF from the tree" feature.
> Status: concept / decision paper. Concerns `filetree.nvim` (a new feature)
> and `pdfport.nvim` (no mandatory change).
>
> **Correction (2026-08-07):** this document assumed a module name
> `pdfport_nvim` throughout. The module is in fact called `pdfport`
> (`lua/pdfport/`) — the error was carried over unchanged into `util/pdf.lua`
> and `health.lua`, where it made `has_pdfport()` always return `false` even
> with pdfport.nvim installed. Both places are fixed; the `pdfport_nvim`
> occurrences below are left in place as history, except where they were
> meant to document the actual module name.
>
> **Addition (2026-08-09) — the writing direction:** this document describes
> only the reading direction ("open a PDF from the tree"). The opposite
> direction ("produce a PDF from file(s) in the tree") is now wired up as
> well, following exactly the same pattern:
> `filetree.util.pdf.create(paths, opts)` calls `pdfport.create()` per input
> file (skipping files without a matching pdfport producer, rather than
> aborting), and the new feature `features/system/pdf_create` (target
> determination as with `trash`/`copy_move`: marked nodes, otherwise the
> current node; a folder node expands to its direct child files, not
> recursively) asks before every creation through `filetree.util.confirm`
> (= `lib.nvim.ui.kit.confirm`) — a single file as yes/no, several files with
> a preview of the first few names. Default keymap `gP` (upper case; it does
> not collide with `pdf_open`'s `gp`). See
> [docs/BINDINGS/KEYMAPS.md](../BINDINGS/KEYMAPS.md) and, for the full
> producer/expansion-stage context, `pdfport.nvim`'s own
> `docs/ROADMAP/PDF_CREATE.md`.

---

## 1. The problem: a duplicated tree abstraction

Both plugins today solve **the same task independently** — "give me the path
of the node under the cursor in tree X":

| Plugin          | Where                                          | Mechanism                            |
| --------------- | ---------------------------------------------- | ------------------------------------ |
| `pdfport.nvim`  | `integrations/{neotree,nvim_tree,netrw,oil}.lua` + `integrations/init.lua` | `current_pdf_path()` through a `filetype` switch |
| `filetree.nvim` | `adapter/{neotree,nvimtree,netrw,oil,mini_files}.lua` | `FiletreeAdapter.get_current_node()` (a real port) |

`pdfport` thereby reinvents — worse, through an `ft ==` branch — what
`filetree` already owns as a clean port/adapter. As soon as another tree
comes along, it has to be maintained in **two** places. That N×2 matrix is
the redundancy we are dissolving.

---

## 2. The target architecture: port/adapter, extended

Your assumption is correct. Three levels with clear, non-overlapping roles:

```
┌──────────────────────────────────────────────────────────────────┐
│  pdfport.nvim  —  CORE / domain logic                             │
│  "open/convert the PDF at path P"                                 │
│  fallback_chain: pdftotext → pdfplumber → marker → … → claude     │
│  Public API:  require("pdfport_nvim").open{ path=P, mode=… }      │
│  ▸ knows NOTHING about filetrees (for the filetree path)         │
└──────────────────────────────────────────────────────────────────┘
                              ▲  optional require (pcall)
                              │
┌──────────────────────────────────────────────────────────────────┐
│  filetree.nvim  —  PORT + ADAPTER + BRIDGE                        │
│  ▸ adapter/*  : knows every tree (already exists)                │
│  ▸ feature 'pdf_open' : node under cursor → is_pdf? → pdfport    │
│    binds keymaps buffer-locally on the tree's FileType            │
└──────────────────────────────────────────────────────────────────┘
                              ▲  a finished feature / keymap
                              │
┌──────────────────────────────────────────────────────────────────┐
│  neotree / nvimtree / oil / …  —  HOST                            │
│  receives the finished feature, otherwise knows nothing of it     │
└──────────────────────────────────────────────────────────────────┘
```

**The core idea:** `filetree.nvim` gets a new feature `pdf_open` — built
identically to the existing `open_with` (`features/system/open_with/init.lua`).
It uses **the existing adapter** for the node path (no more `filetype`
switch!) and calls **only pdfport's core API**.

---

## 3. The direction of dependency

* `filetree.nvim` → **optionally** `pdfport.nvim` (via `pcall(require, "pdfport_nvim")`).
  No hard dependency. If pdfport is missing, the feature is a no-op (a health
  warning when `enabled = true` explicitly). The same soft-dependency pattern
  as markdown.nvim in color_my_ascii.
* `pdfport.nvim` → **depends on nothing** from filetree. It stays standalone
  (Telescope/fzf/its own tree integrations for standalone users).

The arrow you proposed (`filetree → pdfport as a dependency`) is therefore
right — but **optional**, one-way, and filetree calls exclusively
`pdfport_nvim.open{}`, **not** `pdfport.neotree()` / `.integrations()`.

---

## 4. What stays where (the responsibility matrix)

| Concern                                                   | Owner                                     |
| -------------------------------------------------------- | ----------------------------------------- |
| PDF → text/render, `fallback_chain`, backends            | **pdfport.nvim** core                     |
| "which node lies under the cursor in tree X"             | **filetree.nvim** adapter (exists)        |
| "cursor on a PDF → open with pdfport" + keymaps in the tree | **filetree.nvim** feature `pdf_open` (new)|
| pdfport **standalone** in a tree (without filetree.nvim) | **pdfport.nvim** `integrations/*` (stays) |
| being a dumb host                                         | neotree / nvimtree / …                    |

Important: the `integrations/*` modules in pdfport **stay** — they are the
convenience for users who use pdfport in a tree **without** filetree.nvim.
filetree users do not use them; they get `pdf_open`.

---

## 5. The worry about the fallback_chain (your points 2 and 3)

> "not every filetree user wants to install pdftotext/marker/docling/ollama/claude"

They do not have to:

1. **pdfport is itself an optional dependency.** Whoever never installs
   pdfport simply does not get the feature — zero additional tools.
2. **filetree prescribes no backends.** `pdf_open` only calls
   `.open{path, mode}`; *which* backends apply is decided solely by pdfport's
   own `setup()`. filetree does not even know the chain.
3. **Default = `mode = "system"`** → opens in the OS PDF viewer, needs not a
   single external CLI. Text extraction (`mode = "buffer"`) is opt-in per
   keymap. That satisfies "on by default, but only with in-house means;
   individual tools opt-in" exactly. And pdfport's chain degrades gracefully
   anyway.

---

## 6. The config surface in filetree.nvim

```lua
require("filetree").setup({
  features = {
    pdf_open = {
      enabled      = true,        -- inert if pdfport.nvim is missing
      default_mode = "system",    -- "system"|"buffer"|"float"|"terminal"
      keymaps = {
        open     = "P",           -- the default action = default_mode
        text     = false,         -- text extraction into a buffer (needs a text backend)
        system   = false,
        terminal = false,
      },
    },
  },
})
```

filetree passes `mode`/`backend_id` **through** to pdfport, but never names a
backend itself.

### An optional flourish: a handler port instead of a fixed pdfport coupling

For pure hexagonal: `pdf_open` defines a tiny "PDF handler port". The default
handler = a `pcall` on pdfport; a user could inject their own
`open = function(path, opts) … end` through the config. That mirrors
filetree's adapter philosophy. The `pcall` pdfport default is the pragmatic
core; the port is the extension, should a second PDF backend ever appear.

---

## 7. Implementation sketch, `features/system/pdf_open/init.lua`

Analogous to `open_with` (the same `setup(config, adapter)` signature, the
same FileType keymap registration):

```lua
local _adapter, _cfg = nil, { enabled = false, default_mode = "system", keymaps = {} }

local function current_pdf()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()            -- ← the port, no ft switch
  local path = node and node.path or nil
  if path and path:lower():match("%.pdf$") then return path end
  return nil
end

local function open(mode)
  local path = current_pdf()
  if not path then notify.warn("No PDF under the cursor"); return end
  local ok, pdfport = pcall(require, "pdfport_nvim")   -- ← optional dependency
  if not ok then notify.warn("pdfport.nvim is not installed"); return end
  pdfport.open({ path = path, mode = mode or _cfg.default_mode })
end

function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg, _adapter = vim.tbl_deep_extend("force", _cfg, config), adapter
  -- a FileType autocommand on _adapter.filetypes → bind keymaps buffer-locally
  -- (take the pattern 1:1 from open_with)
end
```

The advantage over pdfport's current `integrations/init.lua`: **not a single
tree-specific line** — `get_current_node()` already abstracts
neotree/nvimtree/oil/… away. A new tree = a new filetree adapter, nothing
else.

---

## 8. Migration steps

1. **nvim config**: the old pdfport neotree wiring is already removed
   (`config/neotree/keymaps/filesystem/init.lua` documents it; the former
   `…/filesystem/pdfport.lua` no longer exists). ✔ nothing to do.
2. **filetree.nvim**:
   - create `lua/filetree/features/system/pdf_open/init.lua`.
   - register it in `features/init.lua`: `pdf_open = { mod = "…system.pdf_open", category = "system" }`.
   - `@types` plus `config/DEFAULTS.lua` (default `enabled = false`, or `true` and inert — see below).
   - `health.lua`: warn when `pdf_open.enabled` but `pdfport_nvim` is missing.
   - the `cheatsheet` feature shows the new keys in the `?` overlay automatically (verify).
   - docs: `BINDINGS/KEYMAPS.md` plus the README (the optional pdfport dependency).
3. **pdfport.nvim**: no mandatory change. Optionally a README note:
   "filetree.nvim users enable `pdf_open` instead of wiring up pdfport's
   neotree integration."

### Decisions taken (as implemented)

* **`enabled` defaults to ON** (not in `DEFAULT_DISABLED`), which fits the
  opt-out model and "on by default". Without pdfport it stays usable (the
  system-viewer fallback).
* **`default_mode = "buffer"`** (a slight deviation from the original
  proposal of "system"): pdfport's core value is text extraction into nvim.
  Without pdfport the opener falls back to the OS viewer automatically → "it
  works with zero dependencies" stays satisfied. `default_mode = "system"` is
  a one-liner in the config for whoever wants the pure viewer.
* **The default keymap `gp`** ("get pdf") for `default_mode`;
  text/system/terminal are opt-in (off by default). `gp` collides with no
  existing binding (`P` is taken by `copy_move`).

### A shared opener instead of scattered pdfport calls

The bridge lives in **`filetree.util.pdf`** (`open(path, opts)` /
`system_open` / `is_pdf` / `has_pdfport`). It encapsulates the correct
`require("pdfport_nvim")` and the **table** signature
`pp.open({ path, mode, … })`. Two consumers:

* the new `pdf_open` feature, and
* the existing `preview` feature (the `<Tab>`/`<CR>` dispatch).

> **Side finding/fix:** `preview/open_pdf` was broken twice over —
> `require("pdfport")` (the module is called `pdfport_nvim`, and no shim
> exists) and `pp.open(path)` (a string instead of a table). It therefore fell
> back silently to the system viewer on *every* PDF. Switching to
> `filetree.util.pdf` fixes both.

---

## 9. Why this is the right division

* **One** tree abstraction instead of two (filetree's adapter wins,
  pdfport's ft switch falls away for filetree users).
* pdfport stays **framework-free** and usable standalone (Telescope/fzf/its
  own integrations untouched).
* filetree gains arbitrarily many trees for the feature "for free" — every
  new adapter brings `pdf_open` along automatically.
* New PDF backends? Purely a pdfport matter. New trees? Purely a filetree
  matter. The host stays dumb. A clean, one-way, **optional** coupling.
