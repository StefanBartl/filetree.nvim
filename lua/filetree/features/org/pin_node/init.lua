---@module 'filetree.features.pin_node'
---@brief Pin tree nodes for quick access; show pinned list in a floating picker.
---@description
--- Pinned paths are highlighted with an eol extmark and persisted to
--- stdpath("data")/filetree/pins.json. They can be jumped to via a
--- floating picker (similar to bookmarks but project-agnostic by default).
---
--- Difference from bookmarks:
---   bookmarks — scoped to current project root, star indicator
---   pins      — global across all projects, pin indicator, quick-jump picker
---
--- Config:
---   enabled     boolean
---   indicator   string    EOL indicator text (default "📌").
---   hl_group    string    Highlight group (default "DiagnosticWarn").
---   keymap      string?   Key inside tree to toggle pin (default "gp").
---   global      boolean   Store pins globally (not per-project). Default true.
---
--- Commands (via :Filetree dispatcher):
---   :Filetree pin toggle
---   :Filetree pin show
---   :Filetree pin clear

local notify = require("filetree.util.notify").create("[filetree.pin_node]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreePinNodeConfig
local _cfg = {
  enabled   = false,
  indicator = "📌",
  hl_group  = "DiagnosticWarn",
  keymap    = "gp",
  global    = true,
}

---@type FiletreeAdapter?
local _adapter = nil

local _ns = vim.api.nvim_create_namespace("filetree_pin_node")

-- ── Persistence ───────────────────────────────────────────────────────────────

local function store_path()
  return vim.fn.stdpath("data") .. "/filetree/pins.json"
end

---@type string[]
local _pins = {}

local function load()
  local path = store_path()
  if vim.fn.filereadable(path) == 0 then return end
  local ok, raw = pcall(vim.fn.readfile, path)
  if not ok or not raw[1] then return end
  local ok2, data = pcall(vim.fn.json_decode, raw[1])
  if ok2 and type(data) == "table" then _pins = data end
end

local function save()
  local dir = vim.fn.stdpath("data") .. "/filetree"
  vim.fn.mkdir(dir, "p")
  pcall(vim.fn.writefile, { vim.fn.json_encode(_pins) }, store_path())
end

-- ── Extmark rendering ─────────────────────────────────────────────────────────

local _pin_set = {}  -- quick lookup table

local function rebuild_set()
  _pin_set = {}
  for _, p in ipairs(_pins) do _pin_set[p] = true end
end

local function render(bufnr)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, _ns, 0, -1)
  if vim.tbl_isempty(_pin_set) then return end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    -- extract trailing path component from the tree line
    local name = line:match("([^%s/\\]+)%s*$") or ""
    if name ~= "" then
      for pin_path in pairs(_pin_set) do
        if pin_path:match("[/\\]" .. vim.pesc(name) .. "$") or pin_path == name then
          vim.api.nvim_buf_set_extmark(bufnr, _ns, i - 1, -1, {
            virt_text       = { { " " .. _cfg.indicator, _cfg.hl_group } },
            virt_text_pos   = "eol",
            priority        = 120,
          })
          break
        end
      end
    end
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Toggle pin on the current tree node.
function M.toggle_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end
  local path = node.path

  local found = false
  for i, p in ipairs(_pins) do
    if p == path then
      table.remove(_pins, i)
      found = true
      break
    end
  end
  if not found then _pins[#_pins + 1] = path end

  rebuild_set()
  save()

  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then render(bufnr) end

  notify.info(found and ("Unpinned: " .. vim.fn.fnamemodify(path, ":t"))
                    or ("Pinned: "   .. vim.fn.fnamemodify(path, ":t")))
end

---Open a floating picker of all pinned paths.
function M.show()
  if #_pins == 0 then notify.info("No pins"); return end

  local labels = vim.tbl_map(function(p)
    return vim.fn.fnamemodify(p, ":~")
  end, _pins)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, labels)
  vim.bo[buf].modifiable = false

  local width  = math.min(70, vim.o.columns - 4)
  local height = math.min(#labels, 15)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    width    = width,    height = height,
    row      = math.floor((vim.o.lines - height) / 2),
    col      = math.floor((vim.o.columns - width) / 2),
    title    = " Pins ", title_pos = "center",
  })
  vim.wo[win].cursorline = true

  local function open_current()
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    local path = _pins[idx]
    vim.api.nvim_win_close(win, true)
    if path and vim.fn.filereadable(path) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    elseif _adapter and _adapter.reveal then
      pcall(_adapter.reveal, path)
    end
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  map("n", "<CR>",  open_current,                              opts)
  map("n", "q",     function() vim.api.nvim_win_close(win, true) end, opts)
  map("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, opts)
end

---Remove all pins.
function M.clear_all()
  _pins = {}
  _pin_set = {}
  save()
  if _adapter then
    local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
    if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, _ns, 0, -1)
    end
  end
  notify.info("All pins cleared")
end

---@param path string
---@return boolean
function M.is_pinned(path)
  return _pin_set[path] == true
end

---@return string[]
function M.get_all()
  return vim.list_slice(_pins)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreePinNodeConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  load()
  rebuild_set()

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_pin_node", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      render(ev.buf)
      if _cfg.keymap then
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap, M.toggle_current, {
            buffer = buf, silent = true, desc = "Filetree: toggle pin",
          })
        end)
      end
    end,
  })

  au.acmd({ "BufEnter", "TextChanged" }, {
    group   = _augroup,
    pattern = { "neo-tree://*", "NvimTree_*" },
    callback = function(ev) render(ev.buf) end,
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
