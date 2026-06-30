---@module 'filetree.features.node_info'
---@brief Toggleable hover window showing filesystem metadata for the current tree node.

local M = {}

---@type FiletreeNodeInfoConfig
local _cfg = {}
---@type FiletreeAdapter?
local _adapter = nil

local _win = nil
local _last_path = nil
local _ns = nil

local function ns()
  if not _ns then _ns = vim.api.nvim_create_namespace("filetree_node_info") end
  return _ns
end

local function close_win()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  _win = nil
  _last_path = nil
end

---Format bytes into human-readable string.
---@param bytes integer
---@return string
local function fmt_bytes(bytes)
  if bytes < 1024 then
    return bytes .. " B"
  elseif bytes < 1024 * 1024 then
    return string.format("%.1f KiB", bytes / 1024)
  else
    return string.format("%.2f MiB", bytes / (1024 * 1024))
  end
end

---Convert stat mode bits to rwxrwxrwx string.
---@param mode integer
---@return string
local function fmt_permissions(mode)
  local bits = { "r", "w", "x", "r", "w", "x", "r", "w", "x" }
  local result = {}
  for i = 8, 0, -1 do
    local bit = math.floor(mode / (2 ^ i)) % 2
    result[#result + 1] = bit == 1 and bits[9 - i] or "-"
  end
  return table.concat(result)
end

---Build content lines for the hover window.
---@param path string
---@return string[]
local function build_lines(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return { "  No stat info for:", "  " .. path }
  end

  local lines = {}
  lines[#lines + 1] = "  Path:     " .. path
  lines[#lines + 1] = "  Type:     " .. (stat.type or "unknown")
  lines[#lines + 1] = "  Size:     " .. fmt_bytes(stat.size)

  -- Permissions (POSIX mode bits, lower 9 bits)
  if stat.mode then
    lines[#lines + 1] = "  Mode:     " .. fmt_permissions(stat.mode)
  end

  -- Modified time
  if stat.mtime then
    local t = stat.mtime.sec
    lines[#lines + 1] = "  Modified: " .. os.date("%Y-%m-%d %H:%M:%S", t)
  end

  -- Line count for files
  if _cfg.show_lines and stat.type == "file" then
    local max = _cfg.max_lines_size or (5 * 1024 * 1024)
    if stat.size <= max then
      local ok, content = pcall(vim.fn.readfile, path)
      if ok and type(content) == "table" then
        lines[#lines + 1] = "  Lines:    " .. #content
      end
    else
      lines[#lines + 1] = "  Lines:    (file too large)"
    end
  end

  return lines
end

---Show or toggle the hover window for the current node.
function M.show_current()
  if not _adapter then return end

  local node = _adapter.get_current_node()
  if not node or not node.path then
    vim.notify("[filetree] node_info: no current node", vim.log.levels.WARN)
    return
  end

  -- Toggle: same path closes the window
  if _last_path == node.path then
    close_win()
    return
  end

  -- Close any existing window first
  close_win()

  local lines = build_lines(node.path)

  -- Compute width
  local width = 20
  for _, l in ipairs(lines) do
    if #l > width then width = #l end
  end
  width = width + 2

  local height = #lines

  -- Open floating window relative to editor
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "filetree_node_info"

  local win_w = vim.o.columns
  local win_h = vim.o.lines
  local row = math.max(1, math.floor((win_h - height) / 2))
  local col = math.max(1, math.floor((win_w - width) / 2))

  _win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row      = row,
    col      = col,
    width    = width,
    height   = height,
    border   = "rounded",
    style    = "minimal",
    title    = " Node Info ",
    title_pos = "center",
  })

  _last_path = node.path

  -- Keymaps to close
  local close_fn = function()
    close_win()
  end
  vim.keymap.set("n", "q",     close_fn, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close_fn, { buffer = bufnr, nowait = true, silent = true })

  -- Auto-close when leaving
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    buffer  = bufnr,
    once    = true,
    callback = function()
      vim.schedule(close_win)
    end,
  })
end

---Close any open node_info hover window.
function M.close()
  close_win()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param cfg FiletreeNodeInfoConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg     = cfg
  _adapter = adapter

  if cfg.keymap then
    local winid = adapter.get_winid and adapter.get_winid()
    if winid then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      vim.keymap.set("n", cfg.keymap, function() M.show_current() end,
        { buffer = bufnr, desc = "filetree: node info", silent = true })
    else
      -- Fallback: set up autocmd to set keymap when tree opens
      vim.api.nvim_create_autocmd("FileType", {
        pattern  = { "neo-tree", "NvimTree" },
        callback = function(ev)
          vim.keymap.set("n", cfg.keymap, function() M.show_current() end,
            { buffer = ev.buf, desc = "filetree: node info", silent = true })
        end,
      })
    end
  end
end

function M.teardown()
  close_win()
  _adapter = nil
end

return M
