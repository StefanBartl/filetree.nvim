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
local au  = require("filetree.util.autocmd")

local M = {}

---@type FiletreeCheatsheetConfig
local _cfg = {
  enabled = true,
  keymap  = "?",
}

---@type FiletreeAdapter?
local _adapter = nil

local _win = nil

local function close_win()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  _win = nil
end

---Build the display lines: one header per category, one row per active
---tree-scoped binding in it. Categories/bindings with nothing live are
---skipped entirely.
---@return string[]
local function build_lines()
  local ok_ft, ft = pcall(require, "filetree")
  local is_enabled = (ok_ft and type(ft.is_feature_enabled) == "function")
    and ft.is_feature_enabled
    or function() return true end

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
  if _win and vim.api.nvim_win_is_valid(_win) then
    close_win()
    return
  end

  local lines = build_lines()

  local width = 20
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(width + 2, math.floor(vim.o.columns * 0.9))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.8))

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype   = "filetree_cheatsheet"

  local row = math.max(1, math.floor((vim.o.lines - height) / 2))
  local col = math.max(1, math.floor((vim.o.columns - width) / 2))

  _win = vim.api.nvim_open_win(bufnr, true, {
    relative  = "editor",
    row       = row,
    col       = col,
    width     = width,
    height    = height,
    border    = "rounded",
    style     = "minimal",
    title     = " filetree.nvim keymaps ",
    title_pos = "center",
  })

  local close_fn = function() close_win() end
  for _, k in ipairs({ "q", "<Esc>", _cfg.keymap }) do
    map("n", k, close_fn, { buffer = bufnr, nowait = true, silent = true })
  end
  au.acmd({ "BufLeave", "WinLeave" }, {
    buffer   = bufnr,
    once     = true,
    callback = function() vim.schedule(close_win) end,
  })
end

function M.close()
  close_win()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeCheatsheetConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_extend("force", _cfg, config)
  _adapter = adapter

  -- neo-tree already has this via attach.lua's window.mappings injection into
  -- its own native `?`/show_help; don't shadow a working, richer solution.
  if adapter.name == "neotree" then return end
  if not _cfg.keymap then return end
  -- Minimal/stub/test adapters may not declare `filetypes` (or route missing
  -- fields through a catch-all __index that returns a function, not a table)
  -- — nothing sane to attach a FileType autocmd to in that case, so no-op.
  if type(adapter.filetypes) ~= "table" or #adapter.filetypes == 0 then return end

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_cheatsheet", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = adapter.filetypes,
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        map("n", _cfg.keymap, M.show,
          { buffer = buf, desc = "filetree: keymap cheatsheet", silent = true })
      end)
    end,
  })
end

function M.teardown()
  close_win()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
