---@module 'filetree.features.size_info'
---@brief Show file and directory sizes as eol extmarks on tree nodes.
---@description
--- File sizes come from vim.uv.fs_stat() (fast, synchronous per node).
--- Directory sizes are computed asynchronously via `du -sh` (POSIX) or
--- PowerShell Get-ChildItem (Windows), since walking a full directory tree
--- is slow. Sizes are cached and refreshed lazily.
---
--- Display examples:  4.2 KB   1.3 MB   128 B   (dir: 23 MB)
---
--- Refresh triggers:
---   - Tree BufEnter
---   - CursorHold inside tree buffer (re-renders cached values)
---   - :FiletreeSizeRefresh

local M = {}

---@type FiletreeSizeInfoConfig
local _cfg = {
  enabled       = false,
  show_files    = true,
  show_dirs     = true,
  hl_group      = "Comment",
  dir_async     = true,  -- use du for dirs (async; may be slow on large trees)
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace
local _ns = -1

---@type table<string, string>  abs_path → formatted size string
local _cache = {}

-- ── Formatting ────────────────────────────────────────────────────────────────

local function fmt_bytes(n)
  n = tonumber(n) or 0
  if n < 1024 then
    return string.format("%d B", n)
  elseif n < 1024 * 1024 then
    return string.format("%.1f KB", n / 1024)
  elseif n < 1024 * 1024 * 1024 then
    return string.format("%.1f MB", n / (1024 * 1024))
  else
    return string.format("%.2f GB", n / (1024 * 1024 * 1024))
  end
end

-- ── Async dir size ────────────────────────────────────────────────────────────

local _pending = {} ---@type table<string, boolean>

local function query_dir_size(path, callback)
  if _pending[path] then return end
  _pending[path] = true

  local cmd
  if vim.fn.has("win32") == 1 then
    cmd = {
      "powershell", "-NoProfile", "-Command",
      string.format(
        "(Get-ChildItem -Recurse -Force '%s' -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum",
        path:gsub("'", "''")
      ),
    }
  else
    cmd = { "du", "-sb", path }
  end

  vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
    _pending[path] = nil
    if result.code ~= 0 then return end
    local out = result.stdout or ""
    local bytes
    if vim.fn.has("win32") == 1 then
      bytes = tonumber(vim.trim(out))
    else
      bytes = tonumber(out:match("^(%d+)"))
    end
    if bytes then
      _cache[path] = fmt_bytes(bytes)
      M._render()
    end
    callback(bytes)
  end))
end

-- ── File size (sync via uv.fs_stat) ──────────────────────────────────────────

local function get_file_size(path)
  if _cache[path] then return _cache[path] end
  local uv  = vim.uv or vim.loop
  local stat = uv.fs_stat(path)
  if stat then
    local s = fmt_bytes(stat.size)
    _cache[path] = s
    return s
  end
  return nil
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

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
      local size_str

      if node.type == "file" and _cfg.show_files then
        size_str = get_file_size(node.path)

      elseif node.type == "directory" and _cfg.show_dirs then
        size_str = _cache[node.path]
        if not size_str and _cfg.dir_async then
          -- Kick off async query; render will be called again when done
          query_dir_size(node.path, function() end)
          size_str = "…"
        end
      end

      if size_str then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, -1, {
          virt_text     = { { " " .. size_str, _cfg.hl_group } },
          virt_text_pos = "eol",
          priority      = 40,
        })
      end
    end
  end
end

---Clear the size cache and re-render.
function M.refresh()
  _cache   = {}
  _pending = {}
  M._render()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeSizeInfoConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter
  _ns      = vim.api.nvim_create_namespace("filetree_size_info")

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_size_info", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group   = _augroup,
    pattern = "*",
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft == "neo-tree" or ft == "NvimTree" then M._render() end
    end,
  })

  vim.api.nvim_create_autocmd("CursorHold", {
    group   = _augroup,
    pattern = "*",
    callback = function()
      local ft = vim.bo.filetype
      if ft == "neo-tree" or ft == "NvimTree" then M._render() end
    end,
  })

  M._render()
end

function M.teardown()
  if _adapter then
    local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
    if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
    end
  end
  _cache   = {}
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end

end

return M
