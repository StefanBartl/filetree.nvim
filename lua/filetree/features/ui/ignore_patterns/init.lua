---@module 'filetree.features.ignore_patterns'
---@brief Hide/dim tree nodes that match custom Lua patterns.
---@description
--- Applies additional ignore rules on top of whatever the adapter already hides.
--- Patterns are Lua patterns (string.match). Glob-style wildcards are auto-
--- converted: "*" → ".-", "?" → ".", "." → "%."
---
--- Two modes (config.mode):
---   "dim"  — render non-ignored nodes at full brightness, match → Comment hl
---   "hide" — call adapter native filter API if available, else dim
---
--- Toggle: `gi` inside tree buffer, or :Filetree ignore toggle.
---
--- Config:
---   enabled   boolean
---   patterns  string[]   Lua patterns or globs (e.g. "node_modules", "*.log").
---   mode      "dim"|"hide"
---   keymap    string?    Key to toggle all ignores (default "gi").
---   hl_group  string     Highlight for dimmed lines (default "Comment").
---
--- Commands (via :Filetree dispatcher):
---   :Filetree ignore toggle
---   :Filetree ignore add <pattern>
---   :Filetree ignore clear

local notify = require("filetree.util.notify").create("[filetree.ignore_patterns]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeIgnorePatternsConfig
local _cfg = {
  enabled  = false,
  patterns = {},
  mode     = "dim",
  keymap   = "gi",
  hl_group = "Comment",
}

---@type FiletreeAdapter?
local _adapter = nil

local _ns    = vim.api.nvim_create_namespace("filetree_ignore_patterns")
local _active = true  -- whether ignoring is currently on

-- ── Glob → Lua pattern conversion ────────────────────────────────────────────

local function glob_to_pattern(g)
  -- escape magic chars, then un-escape wildcards
  local p = g
    :gsub("([%(%)%+%[%]%^%$%%])", "%%%1")  -- escape regex magic
    :gsub("%.", "%%.")                       -- escape literal dot
    :gsub("%*", ".-")                        -- * → .-
    :gsub("%?", ".")                         -- ? → .
  return p
end

local function compile_patterns(raw)
  local compiled = {}
  for _, p in ipairs(raw) do
    -- if it looks like a glob (has * or ? but no Lua %-escapes), convert
    local is_glob = p:find("[%*%?]") ~= nil and p:find("%%") == nil
    compiled[#compiled + 1] = is_glob and glob_to_pattern(p) or p
  end
  return compiled
end

local _compiled = {}

local function matches_any(name)
  for _, pat in ipairs(_compiled) do
    if name:match(pat) then return true end
  end
  return false
end

-- ── Dim rendering ─────────────────────────────────────────────────────────────

local function clear_ns(bufnr)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, _ns, 0, -1)
end

local function render_dim(bufnr)
  clear_ns(bufnr)
  if not _active or #_compiled == 0 then return end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    -- Extract the filename component from the line (last path segment)
    local name = line:match("([^/\\%s]+)%s*$") or ""
    if name ~= "" and matches_any(name) then
      vim.api.nvim_buf_set_extmark(bufnr, _ns, i - 1, 0, {
        line_hl_group = _cfg.hl_group,
        priority      = 90,
      })
    end
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.toggle()
  _active = not _active
  notify.info("Ignore patterns " .. (_active and "ON" or "OFF"))
  if _adapter then
    local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
    if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
      render_dim(bufnr)
    end
  end
end

---Add a pattern at runtime.
---@param pattern string
function M.add(pattern)
  _cfg.patterns[#_cfg.patterns + 1] = pattern
  _compiled = compile_patterns(_cfg.patterns)
  notify.info("Ignore pattern added: " .. pattern)
  if _adapter then
    local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
    if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
      render_dim(bufnr)
    end
  end
end

---Remove all runtime patterns (does not persist).
function M.clear_all()
  _cfg.patterns = {}
  _compiled     = {}
  if _adapter then
    local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
    if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
      clear_ns(bufnr)
    end
  end
  notify.info("All ignore patterns cleared")
end

---@return boolean
function M.is_active() return _active end

---@return string[]
function M.get_patterns() return vim.list_slice(_cfg.patterns) end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeIgnorePatternsConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg      = vim.tbl_deep_extend("force", _cfg, config)
  _adapter  = adapter
  _compiled = compile_patterns(_cfg.patterns)

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_ignore_patterns", true)

  -- Re-render on every tree buffer refresh
  au.acmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
    group   = _augroup,
    pattern = { "neo-tree://*", "NvimTree_*" },
    callback = function(ev)
      render_dim(ev.buf)
    end,
  })

  au.acmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      render_dim(ev.buf)
      if _cfg.keymap then
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap, M.toggle, {
            buffer = buf, silent = true, desc = "Filetree: toggle ignore patterns",
          })
        end)
      end
    end,
  })
end

function M.teardown()
  _adapter  = nil
  _compiled = {}
  _active   = true
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
