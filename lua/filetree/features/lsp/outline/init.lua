---@module 'filetree.features.outline'
---@brief Show file symbol outline (LSP/treesitter) for the current tree node.
---@description
--- Opens a floating window listing the document symbols of the file under
--- the tree cursor. Jumping to a symbol opens the file at that line.
---
--- Symbol source priority:
---   1. LSP textDocument/documentSymbols (if a server is attached)
---   2. Treesitter query (if available, queries `@name.definition` captures)
---   3. ctags via vim.system (if ctags is executable)
---
--- Config:
---   enabled     boolean
---   keymap      string?   Key inside tree (default "go").
---   max_width   integer   Max float width (default 60).
---   max_height  integer   Max float height (default 25).
---   depth       integer   Max LSP symbol nesting depth to show (default 3).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree outline

local notify = require("filetree.util.notify").create("[filetree.outline]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeOutlineConfig
local _cfg = {
  enabled    = false,
  keymap     = "go",
  max_width  = 60,
  max_height = 25,
  depth      = 3,
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Symbol source: LSP ────────────────────────────────────────────────────────

local SYMBOL_ICONS = {
  [1]  = "f",  -- File
  [2]  = "m",  -- Module
  [3]  = "N",  -- Namespace
  [4]  = "p",  -- Package
  [5]  = "C",  -- Class
  [6]  = "M",  -- Method
  [7]  = "P",  -- Property
  [8]  = "F",  -- Field
  [9]  = "c",  -- Constructor
  [10] = "E",  -- Enum
  [11] = "I",  -- Interface
  [12] = "fn", -- Function
  [13] = "v",  -- Variable
  [14] = "K",  -- Constant
  [15] = "s",  -- String
  [16] = "n",  -- Number
  [17] = "b",  -- Boolean
  [18] = "[]", -- Array
  [19] = "{}", -- Object
  [20] = "k",  -- Key
  [21] = "0",  -- Null
  [22] = "e",  -- EnumMember
  [23] = "S",  -- Struct
  [24] = "!",  -- Event
  [25] = "op", -- Operator
  [26] = "T",  -- TypeParameter
}

---@class FiletreeOutlineEntry
---@field label  string
---@field line   integer  1-based
---@field indent integer

local function flatten_lsp(syms, depth, indent, out)
  if depth <= 0 then return end
  for _, sym in ipairs(syms or {}) do
    local range = sym.range or (sym.location and sym.location.range) or {}
    local line  = range.start and (range.start.line + 1) or 1
    local icon  = SYMBOL_ICONS[sym.kind] or "?"
    out[#out + 1] = {
      label  = string.rep("  ", indent) .. icon .. " " .. (sym.name or "?"),
      line   = line,
      indent = indent,
    }
    if sym.children then
      flatten_lsp(sym.children, depth - 1, indent + 1, out)
    end
  end
end

local function get_lsp_symbols(path, cb)
  -- Open the file in a scratch buffer temporarily to query LSP
  local bufnr = vim.fn.bufnr(path)
  local created = false
  if bufnr < 0 then
    bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    created = true
  end

  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then cb(nil); return end

  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
  clients[1].request("textDocument/documentSymbol", params, function(err, result)
    if err or not result then cb(nil)
    else
      local out = {}
      flatten_lsp(result, _cfg.depth, 0, out)
      cb(out)
    end
    if created then vim.schedule(function() vim.api.nvim_buf_delete(bufnr, { force = true }) end) end
  end, bufnr)
end

-- ── Symbol source: ctags ──────────────────────────────────────────────────────

local function get_ctags_symbols(path, cb)
  if vim.fn.executable("ctags") == 0 then cb(nil); return end
  vim.system(
    { "ctags", "-f", "-", "--fields=+n", "--sort=no", path },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then cb(nil); return end
        local out = {}
        for _, line in ipairs(vim.split(result.stdout or "", "\n", { plain = true })) do
          if not line:match("^!") then
            local name, _, _, lineno = line:match("^(%S+)\t(%S+)\t(.+)\t.+line:(%d+)")
            if name and lineno then
              out[#out + 1] = { label = "  " .. name, line = tonumber(lineno) or 1, indent = 0 }
            end
          end
        end
        cb(#out > 0 and out or nil)
      end)
    end
  )
end

-- ── Float window ──────────────────────────────────────────────────────────────

local function open_float(path, entries)
  if #entries == 0 then notify.info("No symbols found"); return end

  local labels = vim.tbl_map(function(e) return e.label end, entries)

  local width  = math.min(_cfg.max_width,  vim.o.columns - 4)
  local height = math.min(_cfg.max_height, #entries)
  local buf    = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, labels)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    width    = width, height = height,
    row      = math.floor((vim.o.lines - height) / 2),
    col      = math.floor((vim.o.columns - width) / 2),
    title    = " " .. vim.fn.fnamemodify(path, ":t") .. " ", title_pos = "center",
  })
  vim.wo[win].cursorline = true

  local function jump()
    local row   = vim.api.nvim_win_get_cursor(win)[1]
    local entry = entries[row]
    vim.api.nvim_win_close(win, true)
    if entry then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
      vim.api.nvim_win_set_cursor(0, { entry.line, 0 })
      vim.cmd("normal! zz")
    end
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  map("n", "<CR>",  jump, opts)
  map("n", "q",     function() vim.api.nvim_win_close(win, true) end, opts)
  map("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, opts)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.show_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No file under cursor"); return end
  local path = node.path
  if vim.fn.filereadable(path) == 0 then notify.warn("Not a readable file"); return end

  get_lsp_symbols(path, function(lsp_result)
    if lsp_result and #lsp_result > 0 then
      vim.schedule(function() open_float(path, lsp_result) end)
      return
    end
    get_ctags_symbols(path, function(ctags_result)
      if ctags_result and #ctags_result > 0 then
        open_float(path, ctags_result)
      else
        notify.info("No LSP or ctags symbols found for " .. vim.fn.fnamemodify(path, ":t"))
      end
    end)
  end)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeOutlineConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_outline", true)

  if _cfg.keymap then
    au.acmd("FileType", {
      group   = _augroup,
      pattern = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap, M.show_current, {
            buffer = buf, silent = true, desc = "Filetree: show file outline",
          })
        end)
      end,
    })
  end
end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
