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
---@return "telescope"|"fzf-lua"|"prompt"
local function detect_backend()
  local prefer = _cfg.prefer or "auto"
  if prefer == "telescope" then return "telescope" end
  if prefer == "fzf-lua"   then return "fzf-lua"   end
  if prefer == "prompt"    then return "prompt"     end

  -- auto: try pickers, fall back to prompt-based
  if pcall(require, "telescope") then return "telescope" end
  if pcall(require, "fzf-lua")   then return "fzf-lua"   end
  return "prompt"
end

---Run find_files in the given directory.
---@param dir string
local function run_find(dir)
  local backend = detect_backend()

  if backend == "telescope" then
    local ok, builtin = pcall(require, "telescope.builtin")
    if ok then pcall(builtin.find_files, { cwd = dir }); return end
  end

  if backend == "fzf-lua" then
    local ok, fzf = pcall(require, "fzf-lua")
    if ok then pcall(fzf.files, { cwd = dir }); return end
  end

  -- prompt fallback: glob all files, pick with vim.ui.select
  local files = vim.fn.globpath(dir, "**/*", false, true)
  files = vim.tbl_filter(function(f)
    return vim.fn.isdirectory(f) == 0
  end, files)
  if #files == 0 then
    notify.warn("No files found in " .. dir)
    return
  end
  local display = vim.tbl_map(function(f)
    return f:gsub("^" .. vim.pesc(dir:gsub("\\", "/"):gsub("/?$", "/")) , "")
  end, files)
  vim.ui.select(display, {
    prompt = "Find files in " .. vim.fn.fnamemodify(dir, ":~") .. ": ",
  }, function(choice, idx)
    if choice and idx then
      vim.cmd("edit " .. vim.fn.fnameescape(files[idx]))
    end
  end)
end

---Run live_grep in the given directory.
---@param dir string
local function run_grep(dir)
  local backend = detect_backend()

  if backend == "telescope" then
    local ok, builtin = pcall(require, "telescope.builtin")
    if ok then pcall(builtin.live_grep, { cwd = dir }); return end
  end

  if backend == "fzf-lua" then
    local ok, fzf = pcall(require, "fzf-lua")
    if ok then pcall(fzf.live_grep, { cwd = dir }); return end
  end

  -- prompt fallback: ask for pattern, use :vimgrep (cross-platform)
  vim.ui.input({
    prompt = "Grep in " .. vim.fn.fnamemodify(dir, ":~") .. ": ",
  }, function(pattern)
    if not pattern or pattern == "" then return end
    local glob = vim.fn.fnameescape(dir) .. "/**"
    local ok, err = pcall(vim.cmd, "silent! vimgrep /" .. vim.fn.escape(pattern, "/") .. "/gj " .. glob)
    local qf = vim.fn.getqflist()
    if #qf == 0 then
      notify.info("No matches for: " .. pattern)
    else
      vim.cmd("copen")
    end
    if not ok and err then
      -- vimgrep may error on "no matches" — that's handled above
      _ = err
    end
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
