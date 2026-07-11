---@module 'filetree.features.node_info'
---@brief Toggleable hover window showing filesystem metadata for the current tree node.

local line_count = require("filetree.util.line_count")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
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

---Recursively walk a directory, counting files/subdirs and summing file sizes.
---Bounded by `max_entries` so pressing `I` on a huge tree cannot freeze Neovim;
---if the cap is hit, the result is flagged as truncated.
---@param root string
---@param max_entries integer
---@return { files: integer, dirs: integer, bytes: integer, truncated: boolean }
local function scan_dir(root, max_entries)
  local uv = vim.uv or vim.loop
  local files, dirs, bytes = 0, 0, 0
  local visited = 0
  local truncated = false
  local stack = { root }

  while #stack > 0 do
    local dir = table.remove(stack)
    local fd = uv.fs_scandir(dir)
    if fd then
      while true do
        local name, typ = uv.fs_scandir_next(fd)
        if not name then break end

        visited = visited + 1
        if visited > max_entries then
          truncated = true
          break
        end

        local full = dir .. "/" .. name
        if typ == nil then
          local st = uv.fs_stat(full)
          typ = st and st.type or nil
        end

        if typ == "directory" then
          dirs = dirs + 1
          stack[#stack + 1] = full
        else
          -- files, symlinks and other entries count toward the file total
          files = files + 1
          local st = uv.fs_stat(full)
          if st and st.size then bytes = bytes + st.size end
        end
      end
    end
    if truncated then break end
  end

  return { files = files, dirs = dirs, bytes = bytes, truncated = truncated }
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

---Build human-readable metadata lines for a path (Path/Type/Size/Mode/Modified,
---plus item counts for a directory and a line count for a file). Public so other
---features (e.g. the trash confirm popup) can show the same info without
---duplicating the formatting. Works standalone — no setup() required.
---@param path string
---@return string[]
function M.info_lines(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return { "  No stat info for:", "  " .. path }
  end

  local lines = {}
  lines[#lines + 1] = "  Path:     " .. path
  lines[#lines + 1] = "  Type:     " .. (stat.type or "unknown")

  if stat.type == "directory" then
    -- vim.uv.fs_stat().size is only the directory entry itself (0 on Windows),
    -- so aggregate the real contents instead of showing a misleading size.
    local info = scan_dir(path, _cfg.max_entries or 100000)
    local plus = info.truncated and "+" or ""
    lines[#lines + 1] = string.format(
      "  Items:    %d file%s, %d folder%s%s",
      info.files, info.files == 1 and "" or "s",
      info.dirs,  info.dirs  == 1 and "" or "s",
      info.truncated and "  (truncated)" or "")
    lines[#lines + 1] = "  Size:     " .. fmt_bytes(info.bytes) .. plus
  else
    lines[#lines + 1] = "  Size:     " .. fmt_bytes(stat.size)
  end

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
  if _cfg.show_lines ~= false and stat.type == "file" then
    local e     = path:match("%.([^.]+)$") or ""
    local count = line_count.count(path, e)
    if count then
      lines[#lines + 1] = "  Lines:    " .. line_count.format(count)
    elseif stat.size > 5 * 1024 * 1024 then
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

  local lines = M.info_lines(node.path)

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
  map("n", "q",     close_fn, { buffer = bufnr, nowait = true, silent = true })
  map("n", "<Esc>", close_fn, { buffer = bufnr, nowait = true, silent = true })

  -- Auto-close when leaving
  au.acmd({ "BufLeave", "WinLeave" }, {
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

---@type FiletreeNodeInfoConfig
local DEFAULTS = {
  keymap      = "I",
  show_lines  = true,
  max_entries = 100000, -- cap for the recursive directory scan behind Items/Size
}

---@param cfg FiletreeNodeInfoConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg     = vim.tbl_extend("force", DEFAULTS, cfg or {})
  cfg      = _cfg
  _adapter = adapter

  if cfg.keymap then
    local winid = adapter.get_winid and adapter.get_winid()
    if winid then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      map("n", cfg.keymap, function() M.show_current() end,
        { buffer = bufnr, desc = "filetree: node info", silent = true })
    else
      -- Fallback: set up autocmd to set keymap when tree opens
      au.acmd("FileType", {
        pattern  = { "neo-tree", "NvimTree" },
        callback = function(ev)
          local buf = ev.buf
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then return end
            map("n", cfg.keymap, function() M.show_current() end,
              { buffer = buf, desc = "filetree: node info", silent = true })
          end)
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
