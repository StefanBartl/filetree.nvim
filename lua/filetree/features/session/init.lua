---@module 'filetree.features.session'
---@brief Save and restore tree scroll position and adapter root across sessions.
---@description
--- Persists per-project tree state to JSON:
---   - adapter name
---   - tree root directory
---   - scroll position (topline)
---   - cursor line
---   - a list of expanded directory paths (adapter-dependent; best-effort)
---
--- State is keyed by project root (detected via project_root feature or cwd).
--- On VimLeavePre the current state is written; on VimEnter (deferred) it is
--- restored.
---
--- User commands:
---   :FiletreeSessionSave
---   :FiletreeSessionRestore
---   :FiletreeSessionClear

local notify = require("filetree.util.notify").create("[filetree.session]")

local M = {}

---@type FiletreeSessionConfig
local _cfg = {
  enabled       = false,
  auto_save     = true,
  auto_restore  = true,
  max_sessions  = 50,
}

---@type FiletreeAdapter?
local _adapter = nil

---@type string  path to session JSON file
local _store_path = ""

-- ── Storage ───────────────────────────────────────────────────────────────────

---@class FiletreeSessionEntry
---@field adapter   string
---@field root      string?   Tree root dir at save time.
---@field topline   integer   Scroll position.
---@field cursor    integer   Cursor line number.
---@field expanded  string[]  Expanded directory paths (best-effort).
---@field saved_at  integer   Unix timestamp.

---@type table<string, FiletreeSessionEntry>  project_key → entry
local _sessions = {}

local function ensure_dir()
  local dir = vim.fn.fnamemodify(_store_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end
end

local function load_store()
  if vim.fn.filereadable(_store_path) == 0 then return end
  local ok, content = pcall(vim.fn.readfile, _store_path)
  if not ok or not content or #content == 0 then return end
  local json_ok, data = pcall(vim.fn.json_decode, table.concat(content, "\n"))
  if json_ok and type(data) == "table" then _sessions = data end
end

local function save_store()
  ensure_dir()
  -- Prune oldest if over limit
  local keys = vim.tbl_keys(_sessions)
  if #keys > _cfg.max_sessions then
    table.sort(keys, function(a, b)
      return (_sessions[a].saved_at or 0) < (_sessions[b].saved_at or 0)
    end)
    for i = 1, #keys - _cfg.max_sessions do
      _sessions[keys[i]] = nil
    end
  end
  local ok, encoded = pcall(vim.fn.json_encode, _sessions)
  if ok then pcall(vim.fn.writefile, { encoded }, _store_path) end
end

-- ── Project key ───────────────────────────────────────────────────────────────

local function project_key()
  local ok_pr, pr = pcall(require, "filetree.features.project_root")
  if ok_pr and type(pr.find) == "function" then
    local buf  = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    return pr.find(name ~= "" and name or vim.fn.getcwd())
  end
  return vim.fn.getcwd()
end

-- ── Save / Restore ────────────────────────────────────────────────────────────

function M.save()
  if not _adapter then return end

  local bufnr  = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  local winid  = _adapter.get_winid and _adapter.get_winid() or -1

  local topline = 1
  local cursor  = 1
  if winid > 0 and vim.api.nvim_win_is_valid(winid) then
    topline = vim.fn.line("w0", winid)
    cursor  = vim.api.nvim_win_get_cursor(winid)[1]
  end

  -- Best-effort: ask adapter for expanded paths (optional API)
  local expanded = {}
  if _adapter.get_expanded_paths then
    expanded = _adapter.get_expanded_paths() or {}
  end

  local root = _adapter.get_root and _adapter.get_root() or nil

  local key = project_key()
  _sessions[key] = {
    adapter  = _adapter.name,
    root     = root,
    topline  = topline,
    cursor   = cursor,
    expanded = expanded,
    saved_at = os.time(),
  }
  save_store()
end

function M.restore()
  if not _adapter then return end

  local key   = project_key()
  local entry = _sessions[key]
  if not entry then return end

  -- Only restore if adapter matches
  if entry.adapter and entry.adapter ~= _adapter.name then
    return
  end

  vim.defer_fn(function()
    -- Restore tree root
    if entry.root and _adapter.set_root then
      pcall(_adapter.set_root, entry.root)
    end

    -- Restore expanded dirs
    if entry.expanded and #entry.expanded > 0 and _adapter.expand_paths then
      pcall(_adapter.expand_paths, entry.expanded)
    end

    -- Restore scroll / cursor
    local winid = _adapter.get_winid and _adapter.get_winid() or -1
    if winid > 0 and vim.api.nvim_win_is_valid(winid) then
      pcall(vim.api.nvim_win_set_cursor, winid, { entry.cursor or 1, 0 })
      -- topline: use normal-mode command as there is no direct API
      pcall(function()
        local prev_win = vim.api.nvim_get_current_win()
        vim.api.nvim_set_current_win(winid)
        vim.cmd("normal! " .. (entry.topline or 1) .. "zt")
        vim.api.nvim_set_current_win(prev_win)
      end)
    end
  end, 100)
end

function M.clear()
  local key = project_key()
  _sessions[key] = nil
  save_store()
  notify.info("Session cleared for: " .. key)
end

function M.clear_all()
  _sessions = {}
  save_store()
  notify.info("All sessions cleared")
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeSessionConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg      = vim.tbl_deep_extend("force", _cfg, config)
  _adapter  = adapter
  _store_path = vim.fn.stdpath("data") .. "/filetree/sessions.json"

  load_store()

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_session", { clear = true })

  if _cfg.auto_save then
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group    = _augroup,
      callback = M.save,
    })
    -- Also save when the tree buffer is hidden
    vim.api.nvim_create_autocmd("BufHidden", {
      group   = _augroup,
      pattern = "*",
      callback = function(ev)
        local ft = vim.bo[ev.buf].filetype
        if ft == "neo-tree" or ft == "NvimTree" then M.save() end
      end,
    })
  end

  if _cfg.auto_restore then
    -- Restore after the tree is opened (FileType fires after buffer is set up)
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      once    = true,
      callback = function() M.restore() end,
    })
  end

  vim.api.nvim_create_user_command("FiletreeSessionSave",    M.save,      { desc = "Save tree session"          })
  vim.api.nvim_create_user_command("FiletreeSessionRestore", M.restore,   { desc = "Restore tree session"       })
  vim.api.nvim_create_user_command("FiletreeSessionClear",   M.clear,     { desc = "Clear session for this project" })
end

function M.teardown()
  if _cfg.auto_save then pcall(M.save) end
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
  pcall(vim.api.nvim_del_user_command, "FiletreeSessionSave")
  pcall(vim.api.nvim_del_user_command, "FiletreeSessionRestore")
  pcall(vim.api.nvim_del_user_command, "FiletreeSessionClear")
end

return M
