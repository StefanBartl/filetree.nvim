---@module 'filetree.features.lsp_diagnostics'
---@brief Decorate tree nodes with LSP diagnostic counts via extmarks.
---@description
--- Subscribes to the DiagnosticChanged autocmd and recomputes error/warning
--- counts per file using vim.diagnostic.get(). Results are rendered as eol
--- virtual text on the matching tree node lines.
---
--- Default format:  E:2 W:1  (configurable)
--- Highlight groups follow the severity (DiagnosticError, DiagnosticWarn).
---
--- Updates on DiagnosticChanged and when the tree buffer is entered.

local notify = require("filetree.util.notify").create("[filetree.lsp_diagnostics]")

local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeLspDiagnosticsConfig
local _cfg = {
  enabled       = false,
  show_errors   = true,
  show_warnings = true,
  show_hints    = false,
  show_info     = false,
  format        = function(counts)
    local parts = {}
    if counts.error   > 0 then parts[#parts + 1] = "E:" .. counts.error   end
    if counts.warning > 0 then parts[#parts + 1] = "W:" .. counts.warning end
    if counts.hint    > 0 then parts[#parts + 1] = "H:" .. counts.hint    end
    if counts.info    > 0 then parts[#parts + 1] = "I:" .. counts.info    end
    return #parts > 0 and table.concat(parts, " ") or nil
  end,
  debounce_ms = 300,
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace
local _ns = -1

-- ── Count aggregation ─────────────────────────────────────────────────────────

---@class DiagCounts
---@field error   integer
---@field warning integer
---@field hint    integer
---@field info    integer

---@type table<string, DiagCounts>  abs_path → counts
local _counts = {}

local sev = vim.diagnostic and vim.diagnostic.severity or {
  ERROR = 1, WARN = 2, INFO = 3, HINT = 4,
}

local function recompute()
  local new_counts = {}
  local all = vim.diagnostic.get(nil)
  for _, d in ipairs(all) do
    local bufnr = d.bufnr
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local path = vim.api.nvim_buf_get_name(bufnr)
      if path and path ~= "" then
        local c = new_counts[path] or { error = 0, warning = 0, hint = 0, info = 0 }
        if d.severity == sev.ERROR   then c.error   = c.error   + 1
        elseif d.severity == sev.WARN  then c.warning = c.warning + 1
        elseif d.severity == sev.HINT  then c.hint    = c.hint    + 1
        elseif d.severity == sev.INFO  then c.info    = c.info    + 1
        end
        new_counts[path] = c
      end
    end
  end
  _counts = new_counts
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

local function sev_hl(counts)
  if counts.error   > 0 then return "DiagnosticError" end
  if counts.warning > 0 then return "DiagnosticWarn"  end
  if counts.hint    > 0 then return "DiagnosticHint"  end
  return "DiagnosticInfo"
end

function M._render()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not _adapter.get_node_at_line then return end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for linenr = 0, line_count - 1 do
    local node = _adapter.get_node_at_line(bufnr, linenr)
    if node and node.path then
      -- For directories: aggregate counts from all children
      local c
      if node.type == "directory" then
        local agg = { error = 0, warning = 0, hint = 0, info = 0 }
        local prefix = node.path:gsub("\\", "/")
        if prefix:sub(-1) ~= "/" then prefix = prefix .. "/" end
        for path, pc in pairs(_counts) do
          local np = path:gsub("\\", "/")
          if np:sub(1, #prefix) == prefix then
            agg.error   = agg.error   + pc.error
            agg.warning = agg.warning + pc.warning
            agg.hint    = agg.hint    + pc.hint
            agg.info    = agg.info    + pc.info
          end
        end
        if agg.error + agg.warning + agg.hint + agg.info > 0 then c = agg end
      else
        c = _counts[node.path:gsub("\\", "/")]
      end

      if c then
        local filtered = {
          error   = _cfg.show_errors   and c.error   or 0,
          warning = _cfg.show_warnings and c.warning or 0,
          hint    = _cfg.show_hints    and c.hint    or 0,
          info    = _cfg.show_info     and c.info    or 0,
        }
        local total = filtered.error + filtered.warning + filtered.hint + filtered.info
        if total > 0 then
          local fmt = type(_cfg.format) == "function"
            and _cfg.format(filtered)
            or table.concat(
              (function()
                local p = {}
                if filtered.error   > 0 then p[#p+1] = "E:" .. filtered.error   end
                if filtered.warning > 0 then p[#p+1] = "W:" .. filtered.warning end
                return p
              end)(), " ")
          if fmt then
            pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, -1, {
              virt_text     = { { " " .. fmt, sev_hl(filtered) } },
              virt_text_pos = "eol",
              priority      = 60,
            })
          end
        end
      end
    end
  end
end

-- ── Debounce ──────────────────────────────────────────────────────────────────

---@type any?
local _timer = nil

local function schedule_update()
  local uv = vim.uv or vim.loop
  if _timer then pcall(function() _timer:stop() end)
  else _timer = uv.new_timer() end
  _timer:start(_cfg.debounce_ms, 0, vim.schedule_wrap(function()
    recompute()
    M._render()
  end))
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeLspDiagnosticsConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("keep", config, _cfg)
  _adapter = adapter
  _ns      = vim.api.nvim_create_namespace("filetree_lsp_diagnostics")

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_lsp_diagnostics", true)

  au.acmd("DiagnosticChanged", {
    group    = _augroup,
    callback = schedule_update,
  })

  au.acmd({ "BufEnter", "BufWritePost" }, {
    group   = _augroup,
    pattern = "*",
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft == "neo-tree" or ft == "NvimTree" then
        recompute()
        M._render()
      end
    end,
  })

  -- Initial render after adapters set up
  vim.defer_fn(function()
    recompute()
    M._render()
  end, 500)
end

function M.teardown()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  end
  _counts  = {}
  _adapter = nil
  if _timer then pcall(function() _timer:stop(); _timer:close() end); _timer = nil end
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
