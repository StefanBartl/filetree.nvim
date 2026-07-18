---@module 'filetree.features.pdf_open'
---@brief Open the PDF under the cursor via pdfport.nvim (optional dependency).
---@description
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
---   The explicit-mode keys (text / system / terminal) are opt-in (default off).

local pdf    = require("filetree.util.pdf")
local notify = require("filetree.util.notify").create("[filetree.pdf_open]")
local map    = require("filetree.util.map")
local au     = require("filetree.util.autocmd")

local M = {}

---@type FiletreePdfOpenConfig
local _cfg = {
  enabled         = false,
  default_mode    = "buffer",   -- mode used by keymap_open
  keymap_open     = "gp",
  keymap_text     = false,      -- mode "buffer"   (pdfport text extraction)
  keymap_system   = false,      -- mode "system"   (OS viewer, dependency-free)
  keymap_terminal = false,      -- mode "terminal" (pdfport in a terminal)
}

---@type FiletreeAdapter?
local _adapter = nil

---Path of the PDF file under the cursor, or nil (skips folders / non-PDFs).
---@return string?
local function current_pdf()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()
  local path = (node and node.type == "file") and node.path or nil
  if pdf.is_pdf(path) then return path end
  return nil
end

---@param mode FiletreePdfOpenMode
local function open(mode)
  local path = current_pdf()
  if not path then notify.warn("No PDF under cursor"); return end
  local opts = { mode = mode }
  if mode == "buffer" then
    opts.split, opts.focus = "vsplit", true
  end
  pdf.open(path, opts)
end

function M.open_default()  open(_cfg.default_mode or "buffer") end
function M.open_text()     open("buffer")   end
function M.open_system()   open("system")   end
function M.open_terminal() open("terminal") end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreePdfOpenConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_pdf_open", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local function kmap(key, fn, desc)
          if key and key ~= "" then
            map("n", key, fn, { buffer = buf, silent = true, desc = "Filetree: " .. desc })
          end
        end
        kmap(_cfg.keymap_open,     M.open_default,  "open PDF (pdfport)")
        kmap(_cfg.keymap_text,     M.open_text,     "open PDF as text (pdfport)")
        kmap(_cfg.keymap_system,   M.open_system,   "open PDF in system viewer")
        kmap(_cfg.keymap_terminal, M.open_terminal, "open PDF in terminal (pdfport)")
      end)
    end,
  })
end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
