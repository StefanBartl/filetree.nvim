---@module 'filetree.features.color_labels'
---@brief Assign color labels to tree nodes (macOS Finder-style).
---@description
--- Labels are stored in stdpath("data")/filetree/labels.json (global).
--- Each node can have one label (1–7). Labels render as a colored left-column
--- extmark character before the node line.
---
--- Built-in colors (index → name → highlight):
---   1 red     DiagnosticError   ●
---   2 orange  DiagnosticWarn    ●
---   3 yellow  WarningMsg        ●
---   4 green   DiagnosticOk      ●
---   5 blue    DiagnosticInfo    ●
---   6 purple  Special           ●
---   7 gray    Comment           ●
---
--- Config:
---   enabled    boolean
---   indicator  string            Character shown left of node (default "●").
---   keymap     string?           Opens color picker (default "cl").
---   labels     table?            Override default label definitions.
---
--- Commands (via :Filetree dispatcher):
---   :Filetree label set <1-7|name>
---   :Filetree label clear
---   :Filetree label list

local notify = require("filetree.util.notify").create("[filetree.color_labels]")

local M = {}

---@class FiletreeLabel
---@field name     string
---@field hl_group string

---@type FiletreeLabel[]
local DEFAULT_LABELS = {
  { name = "red",    hl_group = "DiagnosticError" },
  { name = "orange", hl_group = "DiagnosticWarn"  },
  { name = "yellow", hl_group = "WarningMsg"       },
  { name = "green",  hl_group = "DiagnosticOk"     },
  { name = "blue",   hl_group = "DiagnosticInfo"   },
  { name = "purple", hl_group = "Special"          },
  { name = "gray",   hl_group = "Comment"          },
}

---@type FiletreeColorLabelsConfig
local _cfg = {
  enabled   = false,
  indicator = "●",
  keymap    = "cl",
  labels    = nil,
}

---@type FiletreeAdapter?
local _adapter = nil

local _ns = vim.api.nvim_create_namespace("filetree_color_labels")

-- ── Persistence ───────────────────────────────────────────────────────────────

local function store_path()
  return vim.fn.stdpath("data") .. "/filetree/labels.json"
end

---@type table<string, integer>  path → label index (1-7)
local _data = {}

local function load()
  local p = store_path()
  if vim.fn.filereadable(p) == 0 then return end
  local ok, raw = pcall(vim.fn.readfile, p)
  if not ok or not raw[1] then return end
  local ok2, d = pcall(vim.fn.json_decode, raw[1])
  if ok2 and type(d) == "table" then _data = d end
end

local function save()
  local dir = vim.fn.stdpath("data") .. "/filetree"
  vim.fn.mkdir(dir, "p")
  pcall(vim.fn.writefile, { vim.fn.json_encode(_data) }, store_path())
end

-- ── Labels table ──────────────────────────────────────────────────────────────

local function labels()
  return (_cfg.labels and #_cfg.labels > 0) and _cfg.labels or DEFAULT_LABELS
end

local function label_by_name(name)
  for i, l in ipairs(labels()) do
    if l.name == name then return i end
  end
  return nil
end

-- ── Extmark rendering ─────────────────────────────────────────────────────────

local function render(bufnr)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, _ns, 0, -1)
  if vim.tbl_isempty(_data) then return end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lbls  = labels()

  for i, line in ipairs(lines) do
    local name = line:match("([^%s/\\]+)%s*$") or ""
    if name ~= "" then
      for path, idx in pairs(_data) do
        if path:match("[/\\]" .. vim.pesc(name) .. "$") or path == name then
          local lbl = lbls[idx]
          if lbl then
            vim.api.nvim_buf_set_extmark(bufnr, _ns, i - 1, 0, {
              virt_text     = { { _cfg.indicator .. " ", lbl.hl_group } },
              virt_text_pos = "inline",
              priority      = 130,
            })
          end
          break
        end
      end
    end
  end
end

local function render_all()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then render(bufnr) end
end

-- ── Color picker ─────────────────────────────────────────────────────────────

local function open_picker(on_select)
  local lbls  = labels()
  local lines = {}
  for i, l in ipairs(lbls) do
    lines[#lines + 1] = string.format("%d  %s", i, l.name)
  end
  lines[#lines + 1] = "0  (clear label)"

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width  = 24
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor", style = "minimal", border = "rounded",
    width = width, height = height, row = 1, col = 0,
    title = " Label ", title_pos = "center",
  })
  vim.wo[win].cursorline = true

  -- Highlight each line with the label color
  for i, l in ipairs(lbls) do
    vim.api.nvim_buf_add_highlight(buf, -1, l.hl_group, i - 1, 0, -1)
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_close(win, true)
    on_select(row <= #lbls and row or 0)  -- 0 = clear
  end, opts)
  vim.keymap.set("n", "q",     function() vim.api.nvim_win_close(win, true) end, opts)
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, opts)
  -- digit shortcuts
  for d = 0, 9 do
    vim.keymap.set("n", tostring(d), function()
      vim.api.nvim_win_close(win, true)
      on_select(d)
    end, opts)
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Set label on the current node. idx = 1–7, or nil/0 to clear.
---@param idx? integer
function M.set_current(idx)
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end
  local path = node.path

  if not idx or idx == 0 then
    _data[path] = nil
    notify.info("Label cleared: " .. vim.fn.fnamemodify(path, ":t"))
  else
    local lbls = labels()
    if not lbls[idx] then notify.warn("Invalid label index: " .. idx); return end
    _data[path] = idx
    notify.info(string.format("Label %s → %s", lbls[idx].name, vim.fn.fnamemodify(path, ":t")))
  end
  save()
  render_all()
end

---Open a color picker then set the label on the current node.
function M.pick_current()
  open_picker(function(idx) M.set_current(idx) end)
end

---Set by name ("red", "blue", etc.) on the current node.
---@param name string
function M.set_by_name(name)
  local idx = label_by_name(name)
  if not idx then notify.warn("Unknown label: " .. name); return end
  M.set_current(idx)
end

---Clear label on current node.
function M.clear_current()
  M.set_current(0)
end

---List all labelled paths.
---@return { path: string, label: FiletreeLabel }[]
function M.list_all()
  local out = {}
  local lbls = labels()
  for path, idx in pairs(_data) do
    if lbls[idx] then
      out[#out + 1] = { path = path, label = lbls[idx] }
    end
  end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

function M.show_list()
  local all = M.list_all()
  if #all == 0 then notify.info("No labels set"); return end
  local lines = vim.tbl_map(function(e)
    return string.format("[%s] %s", e.label.name, vim.fn.fnamemodify(e.path, ":~"))
  end, all)
  vim.notify("[filetree] Labels:\n  " .. table.concat(lines, "\n  "), vim.log.levels.INFO)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeColorLabelsConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  load()

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_color_labels", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      render(ev.buf)
      if _cfg.keymap then
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.keymap.set("n", _cfg.keymap, M.pick_current, {
            buffer = buf, silent = true, desc = "Filetree: set color label",
          })
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged" }, {
    group   = _augroup,
    pattern = { "neo-tree://*", "NvimTree_*" },
    callback = function(ev) render(ev.buf) end,
  })
end

function M.teardown()
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
