---@module 'filetree.features.size_info'
---@brief Show file and directory sizes as eol extmarks on tree nodes.
---@description
--- File sizes come from vim.uv.fs_stat() (fast, synchronous per node).
--- Directory sizes are computed asynchronously via `du -sh` (POSIX) or
--- PowerShell Get-ChildItem (Windows), since walking a full directory tree
--- is slow. Sizes are cached, each entry expiring after a few seconds
--- (see CACHE_TTL) so a size measured once does not stay frozen for the
--- rest of the session.
---
--- Display examples:  4.2 KB   1.3 MB   128 B   (dir: 23 MB)
---
--- Refresh triggers:
---   - Tree BufEnter and CursorHold inside the tree buffer: re-render;
---     re-measures whatever a node's cache entry has since expired.
---   - BufWritePost on any buffer: invalidates that one path's cache entry
---     immediately, instead of waiting out the TTL.
---   - :FiletreeSizeRefresh: clears every entry unconditionally.

local bufevents = require("filetree.util.bufevents")
local au = require("filetree.util.autocmd")
local bufutil = require("filetree.util.buffer")
local M = {}

---@type FiletreeSizeInfoConfig
local _cfg = {
  enabled = false,
  show_files = true,
  show_dirs = true,
  hl_group = "Comment",
  dir_async = true, -- use du for dirs (async; may be slow on large trees)
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace
local _ns = -1

-- A node's size can change from outside this Neovim session entirely (a
-- build growing the file, `git pull`, another process writing to it) with no
-- event filetree would ever see, so "cached forever" has no defined point at
-- which it becomes wrong -- PERF-42. TTL + an explicit invalidation trigger,
-- same shape as util/buffer.lua's validity cache: a short TTL bounds the
-- staleness of everything, and BufWritePost below clears the one path that
-- has a precise "it just changed" signal instead of waiting out the TTL.
---@type table<string, {value:string, timestamp:number}>  abs_path → cached size + when
local _cache = {}

local CACHE_TTL = 5000 -- ms

---@param path string
---@return string?
local function cache_get(path)
  local entry = _cache[path]
  if not entry then return nil end
  if (vim.uv or vim.loop).now() - entry.timestamp >= CACHE_TTL then
    _cache[path] = nil
    return nil
  end
  return entry.value
end

---@param path string
---@param value string
local function cache_set(path, value)
  _cache[path] = { value = value, timestamp = (vim.uv or vim.loop).now() }
end

-- ── Formatting ────────────────────────────────────────────────────────────────

-- Delegates to lib.lua.strings.format.format_bytes, which also handles
-- TB/PB (this module's own version capped out at GB, growing digits
-- unbounded beyond that).
local function fmt_bytes(n)
  return require("lib.lua.strings.format").format_bytes(tonumber(n) or 0)
end

-- ── Async dir size ────────────────────────────────────────────────────────────

local _pending = {} ---@type table<string, boolean>

local function query_dir_size(path, callback)
  if _pending[path] then return end
  _pending[path] = true

  local cmd
  if vim.fn.has("win32") == 1 then
    cmd = {
      "powershell",
      "-NoProfile",
      "-Command",
      string.format(
        "(Get-ChildItem -Recurse -Force '%s' -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum",
        path:gsub("'", "''")
      ),
    }
  else
    -- `-sk`, not `-sb`: `-b` is a GNU extension. On macOS and the BSDs `du`
    -- rejects it, the process exits non-zero, and the size silently never
    -- appears -- no error, just a column that stays empty forever. `-sk` is
    -- POSIX and reports kibibytes, which after formatting is invisible: a
    -- directory shown as "4.2 MB" does not change by being rounded to the
    -- kibibyte.
    cmd = { "du", "-sk", path }
  end

  vim.system(
    cmd,
    { text = true },
    vim.schedule_wrap(function(result)
      _pending[path] = nil
      if result.code ~= 0 then return end
      local out = result.stdout or ""
      local bytes
      if vim.fn.has("win32") == 1 then
        bytes = tonumber(vim.trim(out))
      else
        local kib = tonumber(out:match("^(%d+)"))
        bytes = kib and (kib * 1024) or nil
      end
      if bytes then
        cache_set(path, fmt_bytes(bytes))
        M._render()
      end
      callback(bytes)
    end)
  )
end

-- ── File size (sync via uv.fs_stat) ──────────────────────────────────────────

local function get_file_size(path)
  local cached = cache_get(path)
  if cached then return cached end
  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(path)
  if stat then
    local s = fmt_bytes(stat.size)
    cache_set(path, s)
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
        size_str = cache_get(node.path)
        if not size_str and _cfg.dir_async then
          -- Kick off async query; render will be called again when done
          query_dir_size(node.path, function() end)
          size_str = "…"
        end
      end

      if size_str then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, -1, {
          virt_text = { { " " .. size_str, _cfg.hl_group } },
          virt_text_pos = "eol",
          priority = 40,
        })
      end
    end
  end
end

---Clear the size cache and re-render.
function M.refresh()
  _cache = {}
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
  _cfg = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter
  _ns = vim.api.nvim_create_namespace("filetree_size_info")

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_size_info", true)

  bufevents.register("size_info", { "BufEnter:tree", "BufWritePost:*" }, {
    desc = "[filetree] Re-draw the tree's size column; on a write, invalidate that file's cached size first",
    load = function(evt)
      if evt.key:find("BufWritePost", 1, true) == 1 then
        local path = vim.api.nvim_buf_get_name(evt.buf)
        if path ~= "" then _cache[path] = nil end
      end
      M._render()
    end,
  })

  au.acmd("CursorHold", {
    group = _augroup,
    pattern = "*",
    desc = "[filetree] Refresh the tree's size column while the cursor rests",
    callback = function()
      if bufutil.is_tree_buffer() then M._render() end
    end,
  })

  M._render()
end

function M.teardown()
  bufevents.unregister("size_info")
  if _adapter then
    local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
    if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
    end
  end
  _cache = {}
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
