---@module 'filetree.features.workspace'
---@brief Multi-root workspace: manage and switch between project directories.
---@description
--- Maintains a list of project root directories. Switching to a root calls
--- adapter.set_root(path) and optionally restores the session for that root.
---
--- Persisted to stdpath("data")/filetree/workspace.json.
--- Integrates with session feature to save/restore state per root.
---
--- Config:
---   enabled         boolean
---   keymap_switch   string?  Key inside tree for picker (default "gw").
---   auto_add        boolean  Auto-add cwd to workspace on setup (default false).
---   max_roots       integer  Max stored roots (default 20).
---   session_restore boolean  Call session.restore() after switching (default true).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree workspace switch
---   :Filetree workspace add [path]
---   :Filetree workspace remove
---   :Filetree workspace list

local notify = require("filetree.util.notify").create("[filetree.workspace]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeWorkspaceConfig
local _cfg = {
  enabled         = false,
  keymap_switch   = "gw",
  auto_add        = false,
  max_roots       = 20,
  session_restore = true,
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Persistence ───────────────────────────────────────────────────────────────

local function store_path()
  return vim.fn.stdpath("data") .. "/filetree/workspace.json"
end

---@type string[]
local _roots = {}

local function load()
  local path = store_path()
  if vim.fn.filereadable(path) == 0 then return end
  local ok, raw = pcall(vim.fn.readfile, path)
  if not ok or not raw[1] then return end
  local ok2, data = pcall(vim.fn.json_decode, raw[1])
  if ok2 and type(data) == "table" then _roots = data end
end

local function save()
  local dir = vim.fn.stdpath("data") .. "/filetree"
  vim.fn.mkdir(dir, "p")
  pcall(vim.fn.writefile, { vim.fn.json_encode(_roots) }, store_path())
end

local function prune()
  -- Remove non-existent directories
  local valid = {}
  for _, r in ipairs(_roots) do
    if vim.fn.isdirectory(r) == 1 then valid[#valid + 1] = r end
  end
  _roots = valid
end

-- ── Core ──────────────────────────────────────────────────────────────────────

local function root_index(path)
  for i, r in ipairs(_roots) do
    if r == path then return i end
  end
  return nil
end

local function switch_to(path)
  if not _adapter then notify.warn("No adapter active"); return end
  if vim.fn.isdirectory(path) == 0 then notify.warn("Not a directory: " .. path); return end

  -- Save current session before switching
  local ok_sess, sess = require("filetree.features").load("session")
  if ok_sess and sess and type(sess.save) == "function" then
    pcall(sess.save)
  end

  -- Switch root
  if _adapter.set_root then
    pcall(_adapter.set_root, path)
  end
  vim.cmd("cd " .. vim.fn.fnameescape(path))

  -- Restore session for the new root
  if _cfg.session_restore and ok_sess and sess and type(sess.restore) == "function" then
    vim.schedule(function() pcall(sess.restore) end)
  end

  notify.info("Workspace: " .. vim.fn.fnamemodify(path, ":~"))
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Add a path to the workspace (default: cwd or current node's root).
---@param path? string
function M.add(path)
  if not path or path == "" then
    -- Try project_root, fall back to cwd
    local ok, pr = require("filetree.features").load("project_root")
    if ok and pr then
      local node = _adapter and _adapter.get_current_node()
      path = node and pr.find(node.path) or nil
    end
    path = path or vim.fn.getcwd()
  end
  path = vim.fn.fnamemodify(path, ":p"):gsub("[/\\]$", "")
  if vim.fn.isdirectory(path) == 0 then notify.warn("Not a directory: " .. path); return end
  if root_index(path) then notify.info("Already in workspace: " .. path); return end

  table.insert(_roots, 1, path)
  if #_roots > _cfg.max_roots then _roots[#_roots] = nil end
  save()
  notify.info("Added to workspace: " .. vim.fn.fnamemodify(path, ":~"))
end

---Remove a path from the workspace (default: cwd).
---@param path? string
function M.remove(path)
  path = path or vim.fn.getcwd()
  path = vim.fn.fnamemodify(path, ":p"):gsub("[/\\]$", "")
  local idx = root_index(path)
  if not idx then notify.info("Not in workspace: " .. path); return end
  table.remove(_roots, idx)
  save()
  notify.info("Removed from workspace: " .. vim.fn.fnamemodify(path, ":~"))
end

---Open a floating picker to switch workspace root.
function M.switch()
  prune()
  if #_roots == 0 then
    notify.info("Workspace is empty. Use :Filetree workspace add")
    return
  end

  local labels = vim.tbl_map(function(r)
    local cwd = vim.fn.getcwd()
    local display = vim.fn.fnamemodify(r, ":~")
    return r == cwd and (display .. "  ←") or display
  end, _roots)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, labels)
  vim.bo[buf].modifiable = false

  local width  = math.min(72, vim.o.columns - 4)
  local height = math.min(#labels, 15)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    width    = width,    height = height,
    row      = math.floor((vim.o.lines - height) / 2),
    col      = math.floor((vim.o.columns - width) / 2),
    title    = " Workspace ", title_pos = "center",
  })
  vim.wo[win].cursorline = true

  local function do_switch()
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    local path = _roots[idx]
    vim.api.nvim_win_close(win, true)
    if path then switch_to(path) end
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  map("n", "<CR>",  do_switch, opts)
  map("n", "q",     function() vim.api.nvim_win_close(win, true) end, opts)
  map("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, opts)
  map("n", "dd", function()
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    local path = _roots[idx]
    vim.api.nvim_win_close(win, true)
    if path then M.remove(path) end
  end, opts)
end

---List all workspace roots.
---@return string[]
function M.list()
  prune()
  return vim.list_slice(_roots)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeWorkspaceConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  load()

  if _cfg.auto_add then
    local cwd = vim.fn.getcwd()
    if not root_index(cwd) then
      _roots[#_roots + 1] = cwd
      save()
    end
  end

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_workspace", true)

  if _cfg.keymap_switch then
    au.acmd("FileType", {
      group   = _augroup,
      pattern = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap_switch, M.switch, {
            buffer = buf, silent = true, desc = "Filetree: workspace switcher",
          })
        end)
      end,
    })
  end
end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
