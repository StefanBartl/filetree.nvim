---@module 'filetree.features.cheatsheet'
---@brief `?` keymap cheatsheet — a floating window listing every currently
---active tree-scoped filetree.nvim keymap, grouped by category.
---@description
--- neo-tree already gets this for free: `attach.lua` injects filetree's
--- bindings into neo-tree's own `window.mappings`, so neo-tree's native
--- `?`/show_help already lists them. The other adapters don't have an
--- equivalent hook:
---   - nvim-tree's `g?`/`toggle_help` rebuilds its list by re-running
---     `on_attach` on a throwaway scratch buffer (see `nvim-tree/keymap.lua`
---     `generate_keymap`) — it never sees keys bound outside that callback,
---     which is how filetree binds all of its own.
---   - netrw's `?` is a static, hardcoded help page.
---   - oil/mini.files were not verified to be safely injectable either.
--- Rather than reverse-engineer (and maintain) a bespoke integration per
--- adapter, this feature is filetree's own adapter-agnostic replacement.
---
--- It reads what was **actually bound** out of lib.nvim's keymap registry,
--- not the declared defaults: it used to build from the `bindings.keymaps`
--- catalog, which lists the keys the plugin ships with, so a user who moved
--- one had a cheatsheet that confidently named a key they no longer had.
--- Skips neo-tree, whose native help is already complete.

local map = require("filetree.util.map")
local kit = require("lib.nvim.ui.kit")
local bind = require("filetree.util.bind")

local M = {}

---@type FiletreeCheatsheetConfig
local _cfg = {
  enabled = true,
  keymap = "?",
}

---@type Lib.UI.Kit.Surface|nil
local _surf = nil

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

---Build the display lines: one header per category, one row per key that is
---actually bound right now.
---
---Read back from the registry rather than from a catalog of defaults, so a
---remapped or disabled key shows up as what it is.
---@return string[]
local function build_lines()
  local ok_reg, registry = pcall(require, "filetree.features")
  local order = (ok_reg and registry.CATEGORY_ORDER) or {}
  local cat_of = category_of()

  local lines = { "" }
  local widest = 0

  ---@type table<string, { lhs: string, desc: string }[]>
  local rows_by_cat = {}
  ---@type table<string, boolean>
  local seen = {}

  local all = require("lib.nvim.bindings.keymap").registered()
  for key, entries in pairs(all) do
    -- "filetree/<feature>" and "filetree/<feature>/<sub>"; the global surface
    -- is not tree-scoped and does not belong on a tree buffer's cheatsheet.
    local feature = key:match("^filetree/([^/]+)$")
    if feature then
      for _, e in ipairs(entries) do
        -- One row per key, not per registration: a buffer-local preset is
        -- registered again for every tree buffer that attaches.
        local id = tostring(e.mode) .. " " .. tostring(e.lhs)
        if e.bound and e.lhs and not seen[id] then
          seen[id] = true
          local cat = cat_of[feature] or "other"
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
  end

  ---@type string[]
  local cats = {}
  for _, cat in ipairs(order) do
    cats[#cats + 1] = cat
  end
  -- Anything whose feature the registry does not classify still gets shown,
  -- after the known categories, rather than silently dropped.
  if rows_by_cat.other then cats[#cats + 1] = "other" end

  for _, cat in ipairs(cats) do
    local rows = rows_by_cat[cat]
    if rows and #rows > 0 then
      table.sort(rows, function(a, b)
        return a.lhs < b.lhs
      end)
      lines[#lines + 1] = " " .. cat
      for _, r in ipairs(rows) do
        lines[#lines + 1] = string.format("  %-" .. widest .. "s  %s", r.lhs, r.desc)
      end
      lines[#lines + 1] = ""
    end
  end

  lines[#lines + 1] = " q / <Esc>  close"
  return lines
end

---Show or toggle (any key closes; a second `?` closes too) the cheatsheet.
function M.show()
  if _surf and _surf:is_valid() then
    close_win()
    return
  end

  local lines = build_lines()
  local max_w = math.floor(vim.o.columns * 0.9)
  local max_h = math.floor(vim.o.lines * 0.8)
  local content_w = 20
  for _, l in ipairs(lines) do
    content_w = math.max(content_w, vim.fn.strdisplaywidth(l))
  end

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

  -- kit.viewer's own nice_quit only binds q/<Esc>; also close on a second
  -- press of the toggle key itself (e.g. a second `?`).
  if _cfg.keymap and _cfg.keymap ~= "q" and _cfg.keymap ~= "<Esc>" then
    map("n", _cfg.keymap, close_win, { buffer = _surf.bufnr, nowait = true, silent = true })
  end
end

function M.close()
  close_win()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeCheatsheetConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_extend("force", _cfg, config)

  -- neo-tree already has this via attach.lua's window.mappings injection into
  -- its own native `?`/show_help; don't shadow a working, richer solution.
  if adapter.name == "neotree" then return end
  if not _cfg.keymap then return end

  bind.bind("cheatsheet", _cfg, {
    { name = "show", field = "keymap", rhs = M.show, desc = "keymap cheatsheet" },
  })
end

function M.teardown()
  close_win()
end

return M
