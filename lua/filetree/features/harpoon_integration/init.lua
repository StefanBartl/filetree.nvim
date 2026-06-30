---@module 'filetree.features.harpoon_integration'
---@brief harpoon.nvim bridge — mark files with harpoon from the tree.
---@description
--- Supports harpoon v2 (default) with automatic fallback to harpoon v1.
---
--- Features:
---   • Add / remove the current node from the harpoon list.
---   • Show the harpoon quick-menu.
---   • EOL virtual text showing the harpoon slot number for marked files.
---   • Refreshes extmarks on CursorMoved (debounced) in the tree buffer.
---
--- Config:
---   enabled       boolean
---   keymap_add    string?   Add to harpoon (default "gh").
---   keymap_menu   string?   Open quick-menu (default "gH").
---   indicator_hl  string    Highlight for slot indicator (default "DiagnosticHint").
---   debounce_ms   integer   Debounce for mark refresh (default 250ms).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree harpoon add
---   :Filetree harpoon remove
---   :Filetree harpoon menu

local notify = require("filetree.util.notify").create("[filetree.harpoon_integration]")

local M = {}

---@type FiletreeHarpoonConfig
local _cfg = {
  enabled      = false,
  keymap_add   = "gh",
  keymap_menu  = "gH",
  indicator_hl = "DiagnosticHint",
  debounce_ms  = 250,
}

---@type FiletreeAdapter?
local _adapter = nil

local _ns    = vim.api.nvim_create_namespace("filetree_harpoon")
local _timer = nil

local function uv() return vim.uv or vim.loop end

-- ── Harpoon detection ─────────────────────────────────────────────────────────

local _harpoon = nil
local _v2      = false

local function ensure_harpoon()
  if _harpoon then return _harpoon end

  -- Try v2 first
  local ok2, hp = pcall(require, "harpoon")
  if ok2 and hp.get_list then
    _harpoon = hp
    _v2      = true
    return _harpoon
  end
  -- Try v1
  local ok1, hm = pcall(require, "harpoon.mark")
  if ok1 then
    _harpoon = hm
    _v2      = false
    return _harpoon
  end

  return nil
end

-- ── Harpoon API wrappers ──────────────────────────────────────────────────────

local function hp_add(path)
  local h = ensure_harpoon()
  if not h then notify.warn("harpoon not installed"); return false end

  if _v2 then
    local list = h:list()
    list:add({ value = path, context = {} })
  else
    local hm = h
    hm.mark_file(path)
  end
  return true
end

local function hp_remove(path)
  local h = ensure_harpoon()
  if not h then return false end

  if _v2 then
    local list = h:list()
    for i, item in ipairs(list.items) do
      local val = type(item) == "table" and (item.value or item.filename) or item
      if val == path then
        list:removeAt(i)
        return true
      end
    end
    return false
  else
    local hm = h
    local idx = hm.get_index_of(path)
    if idx then hm.rm_file(path); return true end
    return false
  end
end

local function hp_open_menu()
  local h = ensure_harpoon()
  if not h then notify.warn("harpoon not installed"); return end

  if _v2 then
    local ok, ui = pcall(require, "harpoon.ui")
    if ok then ui.toggle_quick_menu(h:list()) end
  else
    local ok, ui = pcall(require, "harpoon.ui")
    if ok then ui.toggle_quick_menu() end
  end
end

---Returns a map: path → slot (1-indexed)
local function hp_slots()
  local h = ensure_harpoon()
  if not h then return {} end

  local map = {}
  if _v2 then
    local list = h:list()
    for i, item in ipairs(list.items) do
      local val = type(item) == "table" and (item.value or item.filename) or tostring(item)
      if val then map[val] = i end
    end
  else
    local hm = h
    local marks = hm.get_marked_file_names and hm.get_marked_file_names() or {}
    for i, path in ipairs(marks) do map[path] = i end
  end
  return map
end

-- ── Extmark rendering ─────────────────────────────────────────────────────────

local function render(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not _adapter then return end

  local slots = hp_slots()
  if vim.tbl_isempty(slots) then return end

  local nodes = _adapter.get_visible_nodes and _adapter.get_visible_nodes() or {}
  for _, node in ipairs(nodes) do
    if not node.path or not node.line then goto continue end
    local slot = slots[node.path]
    if slot then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, node.line - 1, -1, {
        virt_text     = { { " [" .. slot .. "]", _cfg.indicator_hl } },
        virt_text_pos = "eol",
        priority      = 115,
      })
    end
    ::continue::
  end
end

local function schedule_render()
  if _timer then pcall(function() _timer:stop() end) end
  _timer = uv().new_timer()
  _timer:start(_cfg.debounce_ms, 0, vim.schedule_wrap(function()
    _timer = nil
    if not _adapter then return end
    local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
    if bufnr > 0 then render(bufnr) end
  end))
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.add_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end
  if hp_add(node.path) then
    notify.info("Added to harpoon: " .. vim.fn.fnamemodify(node.path, ":t"))
    schedule_render()
  end
end

function M.remove_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end
  if hp_remove(node.path) then
    notify.info("Removed from harpoon: " .. vim.fn.fnamemodify(node.path, ":t"))
    schedule_render()
  else
    notify.info("Not in harpoon list")
  end
end

function M.menu() hp_open_menu() end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeHarpoonConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_harpoon", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      render(ev.buf)
      local buf = ev.buf
      local function km(key, fn, desc)
        if key then
          vim.keymap.set("n", key, fn, { buffer = buf, silent = true, desc = desc })
        end
      end
      km(_cfg.keymap_add,  M.add_current, "Filetree: add to harpoon")
      km(_cfg.keymap_menu, M.menu,        "Filetree: open harpoon menu")
    end,
  })

  -- Refresh marks when cursor moves in tree
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = _augroup,
    callback = function()
      if not _adapter then return end
      local winid = _adapter.get_winid and _adapter.get_winid() or -1
      if winid > 0 and vim.api.nvim_get_current_win() == winid then
        schedule_render()
      end
    end,
  })
end

function M.teardown()
  _adapter = nil
  _harpoon = nil
  if _timer then pcall(function() _timer:stop(); _timer:close() end); _timer = nil end
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
