---@module 'filetree.features.grep_in_dir'
---@brief Grep/ripgrep in the directory of the current tree node.
---@description
--- Detects available backends in order:
---   1. telescope.nvim  live_grep / grep_string
---   2. fzf-lua         live_grep / grep
---   3. vim.fn.system   ripgrep → grep fallback → quickfix list
---
--- The search root is the directory of the node under the cursor (or cwd).
--- After selection the file is opened and the match line is jumped to.
---
--- Keymaps (in tree buffer, default):
---   gr  grep with prompt
--- (keymap_cword, "grep word under cursor", has no default keymap — set one
--- explicitly via config if wanted.)
---
--- User commands:
---   :FiletreeGrepInDir [pattern]

local notify = require("filetree.util.notify").create("[filetree.grep_in_dir]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

-- Optional: shows a "searching…" indicator around the builtin backend's
-- blocking rg/grep process, which can take a while under a large directory.
-- No-op (returns nil) when lib.nvim isn't installed.
local ok_progress, progress_mod = pcall(require, "lib.nvim.progress")
local function new_progress()
  if not ok_progress then return nil end
  return progress_mod.create({ title = "[filetree.grep_in_dir]" })
end

---@type FiletreeGrepInDirConfig
local _cfg = {
  enabled          = false,
  keymap           = "gr",
  keymap_cword     = nil,
  keymap_telescope = "tg",
  prefer           = "auto",   -- "auto"|"telescope"|"fzf-lua"|"builtin"
  hidden           = false,
  extra_args       = {},
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Root ──────────────────────────────────────────────────────────────────────

local function get_dir()
  if not _adapter then return vim.fn.getcwd() end
  local node = _adapter.get_current_node()
  if not node then return vim.fn.getcwd() end
  return node.type == "directory"
    and node.path
    or vim.fn.fnamemodify(node.path, ":h")
end

-- ── Backends ──────────────────────────────────────────────────────────────────

local function via_telescope(dir, pattern)
  local ok, tel = pcall(require, "telescope.builtin")
  if not ok then return false end
  local opts = {
    cwd            = dir,
    search         = pattern or nil,
    hidden         = _cfg.hidden,
    additional_args = _cfg.extra_args,
  }
  if pattern and pattern ~= "" then
    tel.grep_string(vim.tbl_extend("force", opts, { word_match = false }))
  else
    tel.live_grep(opts)
  end
  return true
end

local function via_fzflua(dir, pattern)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return false end
  local opts = {
    cwd    = dir,
    hidden = _cfg.hidden,
  }
  if pattern and pattern ~= "" then
    opts.search = pattern
    fzf.grep(opts)
  else
    fzf.live_grep(opts)
  end
  return true
end

local function via_builtin(dir, pattern)
  if not pattern or pattern == "" then
    pattern = vim.fn.input("Grep pattern: ")
    if pattern == "" then return true end
  end

  -- Prefer rg, then grep
  local has_rg = vim.fn.executable("rg") == 1
  local output, exit_code

  local prog = new_progress()
  if prog then prog:update({ text = "searching " .. dir .. "…" }) end

  if has_rg then
    -- vim.system with an argv list (not a shell string) on purpose: it execs
    -- rg directly with no shell in between, so there's nothing to quote/escape
    -- and no dependency on &shell being cmd.exe-compatible (e.g. Git Bash as
    -- &shell on Windows mishandles a hand-built quoted command string passed
    -- through vim.fn.system/systemlist).
    local args = { "rg", "--vimgrep", "--color=never" }
    if _cfg.hidden then args[#args + 1] = "--hidden" end
    for _, a in ipairs(_cfg.extra_args) do args[#args + 1] = a end
    args[#args + 1] = "--"
    args[#args + 1] = pattern
    args[#args + 1] = dir

    local result = vim.system(args, { text = true }):wait()
    output = vim.split(result.stdout or "", "\n", { trimempty = true })
    exit_code = result.code
  else
    local cmd = string.format('grep -rn -- %s %s', vim.fn.shellescape(pattern), vim.fn.shellescape(dir))
    output = vim.fn.systemlist(cmd)
    exit_code = vim.v.shell_error
  end

  if prog then prog:finish(string.format("%d line(s) matched", #output)) end

  if exit_code ~= 0 and #output == 0 then
    notify.info("No matches for: " .. pattern)
    return true
  end

  -- Populate quickfix
  local qf_items = {}
  for _, line in ipairs(output) do
    -- rg/grep --vimgrep format: file:line:col:text
    local file, lnum, col, text = line:match("^(.+):(%d+):(%d+):(.*)")
    if file then
      qf_items[#qf_items + 1] = {
        filename = file,
        lnum     = tonumber(lnum),
        col      = tonumber(col),
        text     = text,
      }
    end
  end

  if #qf_items == 0 then
    notify.info("No matches for: " .. pattern)
    return true
  end

  vim.fn.setqflist(qf_items, "r")
  vim.fn.setqflist({}, "a", { title = "grep: " .. pattern .. " [" .. dir .. "]" })
  vim.cmd("copen")
  notify.info(string.format("Found %d match(es) in %s", #qf_items, vim.fn.fnamemodify(dir, ":t")))
  return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Run grep in `dir` for `pattern`.
---@param dir?     string
---@param pattern? string  If nil, a prompt is shown (telescope/fzf do their own input).
function M.grep(dir, pattern)
  dir = dir or get_dir()
  local prefer = _cfg.prefer or "auto"

  if prefer == "telescope" then via_telescope(dir, pattern); return end
  if prefer == "fzf-lua"   then via_fzflua(dir, pattern);   return end
  if prefer == "builtin"   then via_builtin(dir, pattern);   return end

  if not via_telescope(dir, pattern) and not via_fzflua(dir, pattern) then
    via_builtin(dir, pattern)
  end
end

---Grep the word under the cursor in the current node's directory.
function M.grep_cword()
  M.grep(get_dir(), vim.fn.expand("<cword>"))
end

---Force telescope specifically, regardless of the configured `prefer` backend.
---@param dir?     string
---@param pattern? string
function M.grep_telescope(dir, pattern)
  dir = dir or get_dir()
  if not via_telescope(dir, pattern) then
    notify.warn("telescope.nvim not available")
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeGrepInDirConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_grep_in_dir", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = "neo-tree,NvimTree",
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if _cfg.keymap then
          map("n", _cfg.keymap, M.grep, {
            buffer = buf, silent = true, desc = "Filetree: grep in node directory",
          })
        end
        if _cfg.keymap_cword then
          map("n", _cfg.keymap_cword, M.grep_cword, {
            buffer = buf, silent = true, desc = "Filetree: grep cword in node directory",
          })
        end
        if _cfg.keymap_telescope then
          map("n", _cfg.keymap_telescope, M.grep_telescope, {
            buffer = buf, silent = true, desc = "Filetree: grep via telescope specifically",
          })
        end
      end)
    end,
  })

end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
