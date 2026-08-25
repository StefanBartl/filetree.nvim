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
--- adapter, this feature is filetree's own adapter-agnostic replacement:
--- built once from the same `bindings.keymaps()` catalog that already backs
--- `docs/BINDINGS.lua`, filtered to keys that are actually live right now
--- (tree-scoped + the owning feature currently enabled). Skips neo-tree,
--- whose native help is already complete.

local bindings_mod = require("filetree.bindings")
local map = require("filetree.util.map")
local tree_attach = require("filetree.util.tree_attach")
local kit = require("lib.nvim.ui.kit")

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

---Build the display lines: one header per category, one row per active
---tree-scoped binding in it. Categories/bindings with nothing live are
---skipped entirely.
---@return string[]
local function build_lines()
  local ok_ft, ft = pcall(require, "filetree")
  local is_enabled = (ok_ft and type(ft.is_feature_enabled) == "function") and ft.is_feature_enabled
    or function()
      return true
    end

  local ok_reg, registry = pcall(require, "filetree.features")
  local order = (ok_reg and registry.CATEGORY_ORDER) or {}

  local catalog = bindings_mod.keymaps
  local lines = { "" }
  local widest = 0

  -- First pass: collect per-category rows and the widest lhs (for padding).
  ---@type table<string, { lhs: string, desc: string }[]>
  local rows_by_cat = {}
  for _, cat in ipairs(order) do
    local entries = catalog[cat]
    if entries then
      for _, b in ipairs(entries) do
        if b.scope == "tree" and is_enabled(b.feature) then
          rows_by_cat[cat] = rows_by_cat[cat] or {}
          table.insert(rows_by_cat[cat], { lhs = b.lhs, desc = b.desc })
          if #b.lhs > widest then widest = #b.lhs end
        end
      end
    end
  end

  for _, cat in ipairs(order) do
    local rows = rows_by_cat[cat]
    if rows and #rows > 0 then
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

  tree_attach.on_attach(function(buf)
    map(
      "n",
      _cfg.keymap,
      M.show,
      { buffer = buf, desc = "filetree: keymap cheatsheet", silent = true }
    )
  end)
end

function M.teardown()
  close_win()
end

return M
