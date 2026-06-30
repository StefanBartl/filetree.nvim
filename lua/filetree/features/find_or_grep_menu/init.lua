---@module 'filetree.features.find_or_grep_menu'
---@brief Mini-picker to choose between find_files and live_grep for the node directory.

local M = {}

---@type FiletreeFindOrGrepMenuConfig
local _cfg = {}
---@type FiletreeAdapter?
local _adapter = nil

local notify = require("filetree.util.notify").create("[filetree.find_or_grep_menu]")

---Resolve directory from current node.
---@return string
local function resolve_dir()
  local dir = vim.fn.getcwd()
  if not _adapter then return dir end

  local node = _adapter.get_current_node()
  if not node then return dir end

  if node.type == "directory" then
    return node.path
  elseif node.path then
    return vim.fn.fnamemodify(node.path, ":h")
  end
  return dir
end

---Detect preferred backend.
---@return "telescope"|"fzf-lua"|"builtin"
local function detect_backend()
  local prefer = _cfg.prefer or "auto"
  if prefer == "telescope" then return "telescope" end
  if prefer == "fzf-lua"   then return "fzf-lua"   end

  -- auto
  if pcall(require, "telescope") then return "telescope" end
  if pcall(require, "fzf-lua")   then return "fzf-lua"   end
  return "builtin"
end

---Run find_files in the given directory.
---@param dir string
local function run_find(dir)
  local backend = detect_backend()
  if backend == "telescope" then
    local ok, builtin = pcall(require, "telescope.builtin")
    if ok then pcall(builtin.find_files, { cwd = dir }); return end
  elseif backend == "fzf-lua" then
    local ok, fzf = pcall(require, "fzf-lua")
    if ok then pcall(fzf.files, { cwd = dir }); return end
  end
  -- builtin fallback
  vim.ui.select(
    vim.fn.systemlist("find " .. vim.fn.shellescape(dir) .. " -type f 2>/dev/null"),
    { prompt = "Find files in " .. dir },
    function(choice)
      if choice then vim.cmd("edit " .. vim.fn.fnameescape(choice)) end
    end
  )
end

---Run live_grep in the given directory.
---@param dir string
local function run_grep(dir)
  local backend = detect_backend()
  if backend == "telescope" then
    local ok, builtin = pcall(require, "telescope.builtin")
    if ok then pcall(builtin.live_grep, { cwd = dir }); return end
  elseif backend == "fzf-lua" then
    local ok, fzf = pcall(require, "fzf-lua")
    if ok then pcall(fzf.live_grep, { cwd = dir }); return end
  end
  -- builtin fallback: grep prompt
  vim.ui.input({ prompt = "Grep pattern in " .. dir .. ": " }, function(pattern)
    if not pattern or pattern == "" then return end
    local results = vim.fn.systemlist("grep -r --include='*.lua' -l " .. vim.fn.shellescape(pattern) .. " " .. vim.fn.shellescape(dir))
    if #results == 0 then
      notify.info("No matches found")
      return
    end
    vim.fn.setqflist({}, "r", {
      title = "grep: " .. pattern,
      lines = results,
    })
    vim.cmd("copen")
  end)
end

---Open the find/grep picker.
function M.open()
  local dir = resolve_dir()

  local choices = {
    { label = "find_files", fn = function() run_find(dir) end },
    { label = "live_grep",  fn = function() run_grep(dir) end },
  }

  vim.ui.select(
    vim.tbl_map(function(c) return c.label end, choices),
    { prompt = "Search in " .. vim.fn.fnamemodify(dir, ":~") .. " :" },
    function(choice)
      if not choice then return end
      for _, c in ipairs(choices) do
        if c.label == choice then c.fn(); break end
      end
    end
  )
end

---Run find_files directly.
function M.find()
  run_find(resolve_dir())
end

---Run live_grep directly.
function M.grep()
  run_grep(resolve_dir())
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param cfg FiletreeFindOrGrepMenuConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg     = cfg
  _adapter = adapter

  if cfg.keymap then
    local function set_km(buf)
      vim.keymap.set("n", cfg.keymap, function() M.open() end,
        { buffer = buf, desc = "filetree: find or grep menu", silent = true })
    end

    local winid = adapter.get_winid and adapter.get_winid()
    if winid then
      set_km(vim.api.nvim_win_get_buf(winid))
    else
      vim.api.nvim_create_autocmd("FileType", {
        pattern  = { "neo-tree", "NvimTree" },
        callback = function(ev)
          local buf = ev.buf
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then return end
            set_km(buf)
          end)
        end,
      })
    end
  end
end

function M.teardown()
  _adapter = nil
end

return M
