---@module 'filetree.features.ui.cheatsheet'
---@brief `?` cheatsheet — a paged floating window with every key and command
---that is active on the current tree.
---@description
--- Pages (`<Tab>` / `<S-Tab>` or `1`..`3` switch):
---   1. filetree   -- filetree.nvim's own keymaps, grouped by category
---   2. other keys -- every other buffer-local key on the tree buffer: the
---                    adapter's native ones (neo-tree, nvim-tree, ...) and the
---                    ones other plugins of this ecosystem add (pickers.nvim
---                    entry actions, pdfport, ...)
---   3. commands   -- the `:Filetree` sub-commands
---
--- It used to skip neo-tree, on the argument that neo-tree's native `?` is
--- already complete. It was not: that list is built from a hand-kept table
--- (`attach.lua`'s SPEC) that lagged the features, so a key filetree rebinds
--- (`D`) was listed under the native action it had replaced. This one reads
--- what is **actually bound** -- lib.nvim's keymap registry for page 1, the
--- buffer's own keymaps for page 2 -- so it cannot disagree with the keys.
---
--- nvim-tree's `g?` rebuilds its list on a throwaway buffer and never sees keys
--- bound outside `on_attach`; netrw's `?` is a static page; so the other
--- adapters have no equivalent hook either. One adapter-agnostic implementation
--- instead of a bespoke integration per adapter.

local map = require("filetree.util.map")
local kit = require("ui.kit")
local bind = require("filetree.util.bind")

local M = {}

---@type FiletreeCheatsheetConfig
local _cfg = {
  enabled = true,
  keymap = "?",
}

---Option schema (see `filetree.config.schema`): exactly what
---`features.cheatsheet` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {
  keymap = "keymap",
}

---@type Ui.Kit.Surface|nil
local _surf = nil

---@type { title: string, lines: string[] }[]
local _pages = {}
---@type integer
local _page = 1

local function close_win()
  if _surf then _surf:close() end
end

---@internal
---Which category a feature belongs to, from the feature registry.
---@return table<string, string>
local function category_of()
  local ok, registry = pcall(require, "filetree.features")
  local out = {}
  if ok and type(registry.FEATURES) == "table" then
    for name, entry in pairs(registry.FEATURES) do
      out[name] = entry.category
    end
  end
  return out
end

---@class FiletreeCheatsheetRow
---@field lhs  string
---@field desc string

---@internal
---Lay rows out as `<lhs>  <desc>` lines under a header, lhs column aligned.
---@param lines string[]           # Appended to.
---@param header string
---@param rows FiletreeCheatsheetRow[]
---@param widest integer
local function emit_group(lines, header, rows, widest)
  table.sort(rows, function(a, b)
    return a.lhs < b.lhs
  end)
  lines[#lines + 1] = " " .. header
  for _, r in ipairs(rows) do
    lines[#lines + 1] = string.format("  %-" .. widest .. "s  %s", r.lhs, r.desc)
  end
  lines[#lines + 1] = ""
end

---@class FiletreeCheatsheetEntry
---@field key string                 # Registry surface, "filetree/<feature>[/global]".
---@field entry Lib.Keymap.Registered

---@internal
---filetree's registry entries that apply to tree buffer `buf`: the ones bound
---in it, and the global ones.
---
---The registry keeps one record per registration, so it also holds the keys of
---every other tree buffer -- a neo-tree symbol outline does not get the
---filesystem tree's keys, and the cheatsheet must not claim it does. When
---nothing is recorded for `buf` at all (the cheatsheet opened from somewhere
---that is not a tree buffer) the filter is dropped rather than showing an
---empty page. Ordered by surface so the winner among two features claiming the
---same key does not depend on `pairs` order.
---@param buf integer
---@return FiletreeCheatsheetEntry[]
local function registry_entries(buf)
  local all = require("lib.nvim.bindings.keymap").registered()
  local surfaces = {}
  for key in pairs(all) do
    if key:match("^filetree/") then surfaces[#surfaces + 1] = key end
  end
  table.sort(surfaces)

  ---@type FiletreeCheatsheetEntry[]
  local list = {}
  local scoped = false
  for _, key in ipairs(surfaces) do
    for _, e in ipairs(all[key]) do
      list[#list + 1] = { key = key, entry = e }
      if e.buffer == buf then scoped = true end
    end
  end
  if not scoped then return list end

  local out = {}
  for _, item in ipairs(list) do
    local b = item.entry.buffer
    if b == nil or b == buf then out[#out + 1] = item end
  end
  return out
end

---@internal
---The lhs of every bound filetree entry for `buf`, in the form
---`nvim_buf_get_keymap` reports it (`<leader>` expanded, key notation
---resolved), so page 2 can tell which buffer keymaps page 1 already lists.
---@param buf integer
---@return table<string, true>
local function registry_raw_lhs(buf)
  local out = {}
  for _, item in ipairs(registry_entries(buf)) do
    local e = item.entry
    if e.bound and e.lhs then
      out[vim.api.nvim_replace_termcodes(e.lhs, true, true, true)] = true
    end
  end
  return out
end

---@internal
---A stable string for an entry's mode (a string, or a list for a multi-mode
---action), for de-duplicating rows.
---@param mode string|string[]
---@return string
local function mode_id(mode)
  return type(mode) == "table" and table.concat(mode, ",") or tostring(mode)
end

---Page 1: filetree's own keymaps, one header per category, one row per key
---that is actually bound right now.
---
---Read back from the registry rather than from a catalog of defaults, so a
---remapped or disabled key shows up as what it is.
---@param buf integer
---@return string[]
local function build_filetree_page(buf)
  local ok_reg, registry = pcall(require, "filetree.features")
  local order = (ok_reg and registry.CATEGORY_ORDER) or {}
  local cat_of = category_of()

  local lines = {}
  local widest = 0

  ---@type table<string, FiletreeCheatsheetRow[]>
  local rows_by_cat = {}
  ---@type table<string, boolean>
  local seen = {}

  for _, item in ipairs(registry_entries(buf)) do
    -- "filetree/<feature>" is tree-scoped, "filetree/<feature>/global" is bound
    -- everywhere (the tree-toggle keys); other sub-surfaces are not keymaps of
    -- their own.
    local feature = item.key:match("^filetree/([^/]+)$")
    local global_feature = item.key:match("^filetree/([^/]+)/global$")
    local e = item.entry
    if (feature or global_feature) and e.bound and e.lhs then
      -- One row per key, not per registration: a buffer-local preset is
      -- registered again for every tree buffer that attaches.
      local id = mode_id(e.mode) .. " " .. e.lhs
      if not seen[id] then
        seen[id] = true
        local cat = global_feature and "global" or cat_of[feature] or "other"
        rows_by_cat[cat] = rows_by_cat[cat] or {}
        -- The registry's `desc` carries the plugin prefix, which every row
        -- here would repeat. Capitalized because a cheatsheet row is a
        -- sentence about the key, not a fragment of one.
        local desc = (e.desc or e.name):gsub("^filetree: ", ""):gsub("^%l", string.upper)
        table.insert(rows_by_cat[cat], { lhs = e.lhs, desc = desc })
        if #e.lhs > widest then widest = #e.lhs end
      end
    end
  end

  ---@type string[]
  local cats = {}
  for _, cat in ipairs(order) do
    cats[#cats + 1] = cat
  end
  -- Anything whose feature the registry does not classify still gets shown,
  -- after the known categories, rather than silently dropped.
  cats[#cats + 1] = "global"
  cats[#cats + 1] = "other"

  for _, cat in ipairs(cats) do
    local rows = rows_by_cat[cat]
    if rows and #rows > 0 then
      emit_group(lines, cat == "global" and "global (everywhere)" or cat, rows, widest)
    end
  end
  return lines
end

---@internal
---Show a leading `<leader>` as such rather than as the character it expands to.
---@param lhs string  # As `nvim_buf_get_keymap` reports it (only <Space> comes raw).
---@return string
local function unexpand_leader(lhs)
  local leader = vim.g.mapleader
  if type(leader) ~= "string" or leader == "" then leader = "\\" end
  if lhs:sub(1, #leader) == leader then lhs = "<leader>" .. lhs:sub(#leader + 1) end
  return (lhs:gsub(" ", "<Space>"))
end

---Page 2: every other buffer-local normal-mode key of the tree buffer.
---
---Whatever the adapter mapped natively plus what other plugins attached
---(pickers.nvim's entry actions, pdfport, ...) -- the keys that are not
---filetree's own and therefore not in the registry.
---@param buf integer
---@return string[]
local function build_other_page(buf)
  local lines = {}
  if not vim.api.nvim_buf_is_valid(buf) then return { " (no tree buffer)" } end

  local ours = registry_raw_lhs(buf)
  ---@type FiletreeCheatsheetRow[]
  local rows = {}
  local widest = 0
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    -- `<Plug>` targets and `<SNR>` internals are plumbing, and a key filetree
    -- itself bound is page 1's row (the registry is the better label).
    local raw = m.lhsraw or m.lhs
    if not ours[raw] and not m.lhs:match("^<Plug>") and not m.lhs:match("^<SNR>") then
      local desc = m.desc
      if not desc or desc == "" then
        if m.callback then
          desc = "(lua function)"
        elseif m.rhs == nil or m.rhs == "" or m.rhs:lower() == "<nop>" then
          desc = "(disabled)"
        else
          desc = m.rhs
        end
      end
      -- A row is one buffer line: an rhs (or a desc) with a newline in it would
      -- make `nvim_buf_set_lines` refuse the whole page.
      desc = desc:gsub("[%c]+", " "):gsub("^%l", string.upper)
      local lhs = unexpand_leader(m.lhs)
      rows[#rows + 1] = { lhs = lhs, desc = desc }
      if #lhs > widest then widest = #lhs end
    end
  end

  if #rows == 0 then return { " (no other buffer-local keys)" } end
  emit_group(lines, "buffer-local, from the adapter and other plugins", rows, widest)
  return lines
end

---Page 3: the `:Filetree` sub-commands.
---@return string[]
local function build_commands_page()
  local ok, commands = pcall(require, "filetree.commands")
  if not ok or type(commands.command_paths) ~= "function" then
    return { " (commands unavailable)" }
  end

  local name = type(commands.command_name) == "function" and commands.command_name() or "Filetree"

  local lines = { " :" .. name .. " <sub-command>", "" }
  local group
  for _, path in ipairs(commands.command_paths()) do
    local head = path:match("^(%S+)")
    if head ~= group then
      if group then lines[#lines + 1] = "" end
      group = head
    end
    lines[#lines + 1] = "  :" .. name .. " " .. path
  end
  lines[#lines + 1] = ""
  return lines
end

---@internal
---Build every page for the given tree buffer.
---@param buf integer
---@return { title: string, lines: string[] }[]
local function build_pages(buf)
  return {
    { title = "filetree", lines = build_filetree_page(buf) },
    { title = "other keys", lines = build_other_page(buf) },
    { title = "commands", lines = build_commands_page() },
  }
end

---@internal
---One page's buffer lines: the tab strip, then the page, then the footer.
---Every page is padded to the tallest one so the float never resizes while
---paging.
---@param height integer  # Rows of page body to pad to.
---@return string[]
local function render(height)
  local tabs = {}
  for i, p in ipairs(_pages) do
    tabs[#tabs + 1] = string.format(i == _page and "[%d %s]" or " %d %s ", i, p.title)
  end
  local lines = { " " .. table.concat(tabs, " "), "" }
  local body = _pages[_page].lines
  for i = 1, height do
    lines[#lines + 1] = body[i] or ""
  end
  lines[#lines + 1] = " <Tab>/<S-Tab> page   q / <Esc> close"
  return lines
end

---@internal
---@param delta integer
---@param height integer
local function turn(delta, height)
  if not _surf or not _surf:is_valid() then return end
  _page = (_page - 1 + delta) % #_pages + 1
  _surf:set_lines(render(height))
  vim.api.nvim_win_set_cursor(_surf.winid, { 1, 0 })
end

---Show or toggle (any key closes; a second `?` closes too) the cheatsheet.
function M.show()
  if _surf and _surf:is_valid() then
    close_win()
    return
  end

  _pages = build_pages(vim.api.nvim_get_current_buf())
  _page = 1

  local body_h, content_w = 1, 30
  for _, p in ipairs(_pages) do
    body_h = math.max(body_h, #p.lines)
    for _, l in ipairs(p.lines) do
      content_w = math.max(content_w, vim.fn.strdisplaywidth(l))
    end
  end
  local lines = render(body_h)
  local max_w = math.floor(vim.o.columns * 0.9)
  local max_h = math.floor(vim.o.lines * 0.8)

  _surf = kit.viewer({
    lines = lines,
    title = "filetree.nvim keymaps",
    filetype = "filetree_cheatsheet",
    width = math.min(content_w + 2, max_w),
    height = math.min(#lines, max_h),
  })
  if not _surf then return end
  _surf:on_close(function()
    _surf = nil
  end)

  local opts = { buffer = _surf.bufnr, nowait = true, silent = true }
  map("n", "<Tab>", function()
    turn(1, body_h)
  end, opts)
  map("n", "<S-Tab>", function()
    turn(-1, body_h)
  end, opts)
  for i = 1, #_pages do
    map("n", tostring(i), function()
      turn(i - _page, body_h)
    end, opts)
  end

  -- kit.viewer's own nice_quit only binds q/<Esc>; also close on a second
  -- press of the toggle key itself (e.g. a second `?`).
  if _cfg.keymap and _cfg.keymap ~= "q" and _cfg.keymap ~= "<Esc>" then
    map("n", _cfg.keymap, close_win, opts)
  end
end

function M.close()
  close_win()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeCheatsheetConfig
---@param _adapter FiletreeAdapter
function M.setup(config, _adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_extend("force", _cfg, config)
  if not _cfg.keymap then return end

  bind.bind("cheatsheet", _cfg, {
    { name = "show", field = "keymap", rhs = M.show, desc = "keymap cheatsheet" },
  })
end

function M.teardown()
  close_win()
end

return M
