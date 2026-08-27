---@module 'filetree.features.system.pdf_open'
--- Open the PDF under the cursor via pdfport.nvim (optional dependency).
---
--- Bridges the tree node under the cursor to pdfport.nvim's core `open{}` API
--- through filetree's own adapter — no per-tree code, no filetype switching. The
--- adapter already abstracts neo-tree / nvim-tree / oil / …, so this feature is
--- tree-agnostic: a new tree needs a new adapter, nothing here changes.
---
--- pdfport.nvim is a SOFT dependency (see filetree.util.pdf). Absent it — or for
--- `mode = "system"` — the PDF is handed to the OS default viewer (zero external
--- CLIs). Text extraction (`mode = "buffer"`) uses whatever backends the user
--- configured in pdfport's own setup(); filetree never names a backend or the
--- fallback chain.
---
--- Keymaps (in tree buffer, defaults):
---   gp   Open PDF with `default_mode` (default "buffer" = pdfport text view;
---        falls back to the system viewer when pdfport isn't installed).
---   The explicit-mode keys (text / system / terminal / picker) are opt-in
---   (default off) — set `default_mode = "picker"` (or bind `keymap_picker`)
---   to get an interactive "how do you want this PDF opened?" chooser
---   instead of a fixed mode; see `filetree.util.pdf`'s `M.pick_open`.

local pdf = require("filetree.util.pdf")
local notify = require("filetree.util.notify").create("[filetree.pdf_open]")
local bind = require("filetree.util.bind")

local M = {}

---@type FiletreePdfOpenConfig
local _cfg = {
  enabled = false,
  default_mode = "buffer", -- mode used by keymap_open
  keymap_open = "gp",
  keymap_text = false, -- mode "buffer"   (pdfport text extraction)
  keymap_system = false, -- mode "system"   (OS viewer, dependency-free)
  keymap_terminal = false, -- mode "terminal" (pdfport in a terminal)
  keymap_picker = false, -- mode "picker"   (ask; see M.open_picker)
}

---@type FiletreeAdapter?
local _adapter = nil

---@internal
---Path of the PDF file under the cursor, or nil (skips folders / non-PDFs).
---@return string?
local function current_pdf()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()
  local path = (node and node.type == "file") and node.path or nil
  if pdf.is_pdf(path) then return path end
  return nil
end

---@internal
---@param mode FiletreePdfOpenMode
local function open(mode)
  local path = current_pdf()
  if not path then
    notify.warn("No PDF under cursor")
    return
  end

  if mode == "picker" then
    pdf.pick_open(path, { title = "Open PDF: " .. vim.fn.fnamemodify(path, ":t") })
    return
  end

  local opts = { mode = mode }
  if mode == "buffer" then
    opts.split, opts.focus = "vsplit", true
  end
  pdf.open(path, opts)
end

---Open the PDF under the cursor using the configured `default_mode`.
function M.open_default()
  open(_cfg.default_mode or "buffer")
end
---Open the PDF under the cursor with pdfport's text extraction ("buffer" mode).
function M.open_text()
  open("buffer")
end
---Open the PDF under the cursor in the OS default viewer.
function M.open_system()
  open("system")
end
---Open the PDF under the cursor with pdfport in a terminal.
function M.open_terminal()
  open("terminal")
end
---Ask how to open the PDF under the cursor (every mode/backend pdfport
---knows about, plus "system application" — always available even without
---pdfport, see `filetree.util.pdf`'s `M.pick_open`).
function M.open_picker()
  open("picker")
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreePdfOpenConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  bind.bind("pdf_open", _cfg, {
    { name = "open", field = "keymap_open", rhs = M.open_default, desc = "open PDF (pdfport)" },
    {
      name = "text",
      field = "keymap_text",
      rhs = M.open_text,
      desc = "open PDF as text (pdfport)",
    },
    {
      name = "system",
      field = "keymap_system",
      rhs = M.open_system,
      desc = "open PDF in system viewer",
    },
    {
      name = "terminal",
      field = "keymap_terminal",
      rhs = M.open_terminal,
      desc = "open PDF in terminal (pdfport)",
    },
    {
      name = "picker",
      field = "keymap_picker",
      rhs = M.open_picker,
      desc = "open PDF — ask how (pdfport/system)",
    },
  })
end

function M.teardown()
  _adapter = nil
end

return M
