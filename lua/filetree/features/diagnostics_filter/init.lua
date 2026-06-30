---@module 'filetree.features.diagnostics_filter'
---@brief Overlay the tree buffer with LSP diagnostic counts and a filter mode.
---@description
--- Two behaviours:
---   decorations — EOL virtual text showing error/warning counts for each node
---                 (always active when feature is enabled).
---   filter      — dims or hides nodes that have NO diagnostics at or above
---                 the configured minimum severity.
---
--- Uses vim.diagnostic.get() which aggregates all open buffers.
--- Refreshes on DiagnosticChanged autocmd (debounced).
---
--- Config:
---   enabled        boolean
---   min_severity   integer  vim.diagnostic.severity level for filter
---                           (default ERROR = 1). Set 2 for WARN+.
---   show_counts    boolean  Render EOL count virt_text (default true).
---   count_icons    table    Icons for {error, warn, info, hint} (default E/W/I/H).
---   hl_groups      table    Hl groups for {error, warn, info, hint}.
---   filter_hl      string   Hl for dimmed nodes (default "Comment").
---   debounce_ms    integer  DiagnosticChanged debounce (default 500ms).
---   keymap         string?  Toggle filter (default "df").
---
--- Commands (via :Filetree dispatcher):
---   :Filetree diag filter
---   :Filetree diag refresh
---   :Filetree diag severity <1-4>

local notify = require("filetree.util.notify").create("[filetree.diagnostics_filter]")

local M = {}

---@type FiletreeDiagnosticsFilterConfig
local _cfg = {
  enabled      = false,
  min_severity = vim.diagnostic.severity.ERROR,
  show_counts  = true,
  count_icons  = { " E", " W", " I", " H" },
  hl_groups    = {
    "DiagnosticError",
    "DiagnosticWarn",
    "DiagnosticInfo",
    "DiagnosticHint",
  },
  filter_hl   = "Comment",
  debounce_ms = 500,
  keymap      = "df",
}

---@type FiletreeAdapter?
local _adapter  = nil
local _ns       = vim.api.nvim_create_namespace("filetree_diagnostics_filter")
local _filter   = false
local _timer    = nil

-- ── Diagnostic helpers ───────────────────────────────────────────────────────

local function uv() return vim.uv or vim.loop end

---Build map: path → { [severity] = count }
local function collect_counts()
  local counts = {}
  for _, d in ipairs(vim.diagnostic.get()) do
    local bufnr = d.bufnr
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local path = vim.api.nvim_buf_get_name(bufnr)
      if path ~= "" then
        counts[path]             = counts[path] or {}
        local s                  = d.severity or 1
        counts[path][s]          = (counts[path][s] or 0) + 1
      end
    end
  end
  return counts
end

local function max_severity(entry)
  for sev = 1, 4 do
    if entry[sev] and entry[sev] > 0 then return sev end
  end
  return nil
end

local function count_text(entry)
  local parts = {}
  for sev = 1, 4 do
    local n = entry[sev] or 0
    if n > 0 then
      parts[#parts + 1] = { _cfg.count_icons[sev] .. n, _cfg.hl_groups[sev] }
    end
  end
  return parts
end

-- ── Extmark rendering ─────────────────────────────────────────────────────────

local function render(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not _adapter then return end

  local nodes  = _adapter.get_visible_nodes and _adapter.get_visible_nodes() or {}
  local counts = collect_counts()

  for _, node in ipairs(nodes) do
    if not node.path or not node.line then goto continue end

    local entry = counts[node.path]
    local sev   = entry and max_severity(entry)

    -- EOL count decoration
    if _cfg.show_counts and entry then
      local virt = count_text(entry)
      if #virt > 0 then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, node.line - 1, -1, {
          virt_text     = virt,
          virt_text_pos = "eol",
          priority      = 110,
        })
      end
    end

    -- Filter dim: if active and node has no qualifying diagnostic → dim
    if _filter and (not sev or sev > _cfg.min_severity) then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, node.line - 1, 0, {
        line_hl_group = _cfg.filter_hl,
      })
    end

    ::continue::
  end
end

local function refresh()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
    vim.schedule(function() render(bufnr) end)
  end
end

local function schedule_refresh()
  if _timer then pcall(function() _timer:stop() end) end
  _timer = uv().new_timer()
  _timer:start(_cfg.debounce_ms, 0, function()
    _timer = nil
    refresh()
  end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.toggle_filter()
  _filter = not _filter
  refresh()
  notify.info("Diagnostic filter: " .. (_filter and "ON" or "OFF"))
end

function M.set_severity(level)
  local n = tonumber(level)
  if not n or n < 1 or n > 4 then notify.warn("Severity must be 1-4"); return end
  _cfg.min_severity = n
  refresh()
  local names = { "ERROR", "WARN", "INFO", "HINT" }
  notify.info("Diagnostic filter severity: " .. (names[n] or n))
end

function M.refresh() refresh() end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeDiagnosticsFilterConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_diagnostics_filter", { clear = true })

  -- Re-render on diagnostic changes (debounced)
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group    = _augroup,
    callback = schedule_refresh,
  })

  -- Initial render when tree buffer opens
  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      render(ev.buf)
      if _cfg.keymap then
        vim.keymap.set("n", _cfg.keymap, M.toggle_filter, {
          buffer = ev.buf, silent = true,
          desc   = "Filetree: toggle diagnostic filter",
        })
      end
    end,
  })
end

function M.teardown()
  _adapter = nil
  _filter  = false
  if _timer then pcall(function() _timer:stop(); _timer:close() end); _timer = nil end
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
