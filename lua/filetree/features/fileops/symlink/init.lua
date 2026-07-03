---@module 'filetree.features.symlink'
---@brief Symlink creation, resolution, and tree decorations.
---@description
--- Features:
---   - Extmark indicator on symlink nodes showing the target path.
---   - M.create(target, link_dir)  Create a symlink in link_dir → target.
---   - M.follow()                  Open the real target of the symlink under cursor.
---   - M.show_target()             Display the target in a notification.
---   - M.create_current()          Interactive: create symlink for the current node.
---
--- Platform:
---   Windows: mklink (requires elevated or Developer Mode; warns if unavailable)
---   POSIX:   ln -s
---
--- Keymaps (in tree buffer):
---   sl  show target / follow symlink
---   sL  create symlink pointing to current node
---
--- User commands:
---   :FiletreeSymlinkFollow
---   :FiletreeSymlinkCreate

local notify   = require("filetree.util.notify").create("[filetree.symlink]")
local platform = require("filetree.util.platform")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeSymlinkConfig
local _cfg = {
  enabled          = false,
  keymap_follow    = "sl",
  keymap_create    = "sL",
  show_target_eol  = true,   -- Show target path as eol extmark
  hl_group         = "Comment",
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace
local _ns = -1

-- ── Symlink resolution ────────────────────────────────────────────────────────

---Resolve the target of a symlink. Returns nil when path is not a symlink.
---@param path string
---@return string?
local function resolve(path)
  local uv = vim.uv or vim.loop
  local stat = uv.fs_lstat(path)
  if not stat or stat.type ~= "link" then return nil end
  local target = uv.fs_readlink(path)
  return target
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

function M._render()
  if not _cfg.show_target_eol then return end
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not _adapter.get_node_at_line then return end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for linenr = 0, line_count - 1 do
    local node = _adapter.get_node_at_line(bufnr, linenr)
    if node and node.path then
      local target = resolve(node.path)
      if target then
        local display = " → " .. target
        pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, -1, {
          virt_text     = { { display, _cfg.hl_group } },
          virt_text_pos = "eol",
          priority      = 45,
        })
      end
    end
  end
end

-- ── Creation ──────────────────────────────────────────────────────────────────

---Create a symlink `link_dir/<link_name>` → `target`.
---@param target   string  Absolute path to the target.
---@param link_dir string  Directory where the link will be created.
---@param link_name? string  Link filename. Defaults to target's basename.
---@return boolean ok
function M.create(target, link_dir, link_name)
  link_name = link_name or vim.fn.fnamemodify(target, ":t")
  local link_path = link_dir .. "/" .. link_name

  if vim.fn.filereadable(link_path) == 1 or vim.fn.isdirectory(link_path) == 1 then
    notify.error("Already exists: " .. link_path)
    return false
  end

  local ok, err
  if platform.is_windows() then
    -- mklink requires special privileges on Windows
    local flag = vim.fn.isdirectory(target) == 1 and "/D " or ""
    local cmd  = string.format(
      'cmd /c mklink %s"%s" "%s"', flag, link_path, target)
    local out = vim.fn.system(cmd)
    ok = vim.v.shell_error == 0
    if not ok then err = out end
  else
    local result = vim.system({ "ln", "-s", target, link_path }):wait()
    ok  = result.code == 0
    err = result.stderr
  end

  if ok then
    notify.info("Symlink created: " .. link_name .. " → " .. target)
    if _adapter and _adapter.refresh then pcall(_adapter.refresh) end
    M._render()
  else
    notify.error("Failed to create symlink: " .. (err or "unknown error"))
  end
  return ok
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Show the target of the symlink under the cursor.
function M.show_target()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node then notify.warn("no node under cursor"); return end
  local target = resolve(node.path)
  if target then
    notify.info(vim.fn.fnamemodify(node.path, ":t") .. " → " .. target)
  else
    notify.info("Not a symlink: " .. node.path)
  end
end

---Follow the symlink under the cursor (open its real target).
function M.follow()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node then notify.warn("no node under cursor"); return end
  local target = resolve(node.path)
  if not target then
    notify.info("Not a symlink — opening normally")
    if vim.fn.filereadable(node.path) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(node.path))
    end
    return
  end
  -- Make absolute if relative
  if not vim.fn.fnamemodify(target, ":p") == target then
    target = vim.fn.fnamemodify(node.path, ":h") .. "/" .. target
  end
  if vim.fn.filereadable(target) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(target))
  elseif vim.fn.isdirectory(target) == 1 then
    if _adapter.reveal then _adapter.reveal(target) end
  else
    notify.warn("Target not accessible: " .. target)
  end
end

---Interactive: create a symlink pointing to the node under the cursor.
function M.create_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node then notify.warn("no node under cursor"); return end

  local link_dir = vim.fn.input("Create symlink in directory: ", vim.fn.getcwd(), "dir")
  if link_dir == "" then return end
  link_dir = vim.fn.expand(link_dir)

  if vim.fn.isdirectory(link_dir) == 0 then
    notify.error("Not a directory: " .. link_dir)
    return
  end

  local link_name = vim.fn.input(
    "Link name: ", vim.fn.fnamemodify(node.path, ":t"))
  if link_name == "" then return end

  M.create(node.path, link_dir, link_name)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeSymlinkConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter
  _ns      = vim.api.nvim_create_namespace("filetree_symlink")

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_symlink", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = "neo-tree,NvimTree",
    callback = function(ev)
      M._render()
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local function bind(key, fn, desc)
          if key then
            map("n", key, fn, { buffer = buf, silent = true, desc = "Filetree: " .. desc })
          end
        end
        bind(_cfg.keymap_follow, M.follow,         "follow symlink")
        bind(_cfg.keymap_create, M.create_current, "create symlink")
      end)
    end,
  })

  au.acmd("BufEnter", {
    group   = _augroup,
    pattern = "*",
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft == "neo-tree" or ft == "NvimTree" then M._render() end
    end,
  })

end

function M.teardown()
  if _adapter then
    local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
    if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
    end
  end
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
