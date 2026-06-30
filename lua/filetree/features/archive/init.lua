---@module 'filetree.features.archive'
---@brief Create zip/tar archives from tree nodes and extract archives.
---@description
--- Works on the current node or on all marked nodes (integrates with marks).
--- Platform-aware compression:
---   Windows: PowerShell Compress-Archive (zip), tar.exe (tar.gz)
---   POSIX:   zip + tar
---
--- Config:
---   enabled     boolean
---   prefer      "auto"|"zip"|"tar"  Default archive format (default "auto").
---   keymap_zip  string?             Key inside tree for zip (default "az").
---   keymap_tar  string?             Key inside tree for tar (default "at").
---
--- Commands (via :Filetree dispatcher):
---   :Filetree archive zip     — zip current/marked node(s)
---   :Filetree archive tar     — tar.gz current/marked node(s)
---   :Filetree archive extract — extract archive under cursor

local notify  = require("filetree.util.notify").create("[filetree.archive]")
local platform = require("filetree.util.platform")

local M = {}

---@type FiletreeArchiveConfig
local _cfg = {
  enabled    = false,
  prefer     = "auto",
  keymap_zip = "az",
  keymap_tar = "at",
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function get_targets()
  local paths = {}
  -- Prefer marks if any
  local ok, marks = pcall(require, "filetree.features.marks")
  if ok and marks then
    local marked = marks.get_all()
    if marked and #marked > 0 then
      for _, p in ipairs(marked) do paths[#paths + 1] = p end
      return paths
    end
  end
  -- Fall back to current node
  if _adapter then
    local node = _adapter.get_current_node()
    if node and node.path then paths[#paths + 1] = node.path end
  end
  return paths
end

local function dest_dir(paths)
  if #paths == 0 then return vim.fn.getcwd() end
  local first = paths[1]
  if vim.fn.isdirectory(first) == 1 then return first end
  return vim.fn.fnamemodify(first, ":h")
end

local function stem(paths)
  if #paths == 1 then
    return vim.fn.fnamemodify(paths[1], ":t:r")
  end
  return "archive"
end

-- ── Zip ───────────────────────────────────────────────────────────────────────

function M.zip_current()
  local targets = get_targets()
  if #targets == 0 then notify.warn("No nodes selected"); return end

  local out_name = stem(targets) .. ".zip"
  local out_dir  = dest_dir(targets)
  vim.ui.input({ prompt = "Archive name: ", default = out_name }, function(name)
    if not name or name == "" then return end
    local dest = out_dir .. "/" .. name

    local cmd
    if platform.is_windows() then
      -- PowerShell Compress-Archive
      local joined = table.concat(
        vim.tbl_map(function(p) return string.format('"%s"', p) end, targets), ","
      )
      cmd = { "powershell", "-NoProfile", "-Command",
        string.format("Compress-Archive -Path %s -DestinationPath '%s' -Force", joined, dest) }
    else
      cmd = { "zip", "-r", dest }
      for _, p in ipairs(targets) do cmd[#cmd + 1] = p end
    end

    vim.system(cmd, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          notify.info("Created: " .. vim.fn.fnamemodify(dest, ":t"))
          if _adapter and _adapter.refresh then _adapter.refresh() end
        else
          notify.error("zip failed: " .. (result.stderr or ""))
        end
      end)
    end)
  end)
end

-- ── Tar ───────────────────────────────────────────────────────────────────────

function M.tar_current()
  local targets = get_targets()
  if #targets == 0 then notify.warn("No nodes selected"); return end

  local out_name = stem(targets) .. ".tar.gz"
  local out_dir  = dest_dir(targets)
  vim.ui.input({ prompt = "Archive name: ", default = out_name }, function(name)
    if not name or name == "" then return end
    local dest = out_dir .. "/" .. name

    local cmd = { "tar", "-czf", dest }
    for _, p in ipairs(targets) do cmd[#cmd + 1] = p end

    -- Windows 10+ ships tar.exe, so same command works
    vim.system(cmd, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          notify.info("Created: " .. vim.fn.fnamemodify(dest, ":t"))
          if _adapter and _adapter.refresh then _adapter.refresh() end
        else
          notify.error("tar failed: " .. (result.stderr or ""))
        end
      end)
    end)
  end)
end

-- ── Extract ───────────────────────────────────────────────────────────────────

local function detect_ext(path)
  local lower = path:lower()
  if lower:match("%.zip$")          then return "zip"
  elseif lower:match("%.tar%.gz$")  then return "tar.gz"
  elseif lower:match("%.tar%.bz2$") then return "tar.bz2"
  elseif lower:match("%.tar%.xz$")  then return "tar.xz"
  elseif lower:match("%.tgz$")      then return "tar.gz"
  elseif lower:match("%.tar$")      then return "tar"
  end
  return nil
end

function M.extract_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end

  local archive = node.path
  local ext = detect_ext(archive)
  if not ext then
    notify.warn("Not a recognised archive: " .. vim.fn.fnamemodify(archive, ":t"))
    return
  end

  local out_dir = vim.fn.fnamemodify(archive, ":h")
  vim.ui.input({ prompt = "Extract to: ", default = out_dir }, function(dest)
    if not dest or dest == "" then return end
    vim.fn.mkdir(dest, "p")

    local cmd
    if ext == "zip" then
      if platform.is_windows() then
        cmd = { "powershell", "-NoProfile", "-Command",
          string.format("Expand-Archive -Path '%s' -DestinationPath '%s' -Force", archive, dest) }
      else
        cmd = { "unzip", "-o", archive, "-d", dest }
      end
    else
      cmd = { "tar", "-xf", archive, "-C", dest }
    end

    vim.system(cmd, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          notify.info("Extracted to " .. dest)
          if _adapter and _adapter.refresh then _adapter.refresh() end
        else
          notify.error("extract failed: " .. (result.stderr or ""))
        end
      end)
    end)
  end)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeArchiveConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_archive", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      if _cfg.keymap_zip then
        vim.keymap.set("n", _cfg.keymap_zip, M.zip_current, {
          buffer = buf, silent = true, desc = "Filetree: zip current/marked",
        })
      end
      if _cfg.keymap_tar then
        vim.keymap.set("n", _cfg.keymap_tar, M.tar_current, {
          buffer = buf, silent = true, desc = "Filetree: tar.gz current/marked",
        })
      end
    end,
  })
end

function M.teardown()
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
