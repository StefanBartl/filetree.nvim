---@module 'filetree.features.git_status'
---@brief Decorate tree nodes with git status indicators via extmarks.
---@description
--- Runs `git status --porcelain` in the nearest project root and maps each
--- changed path to its status code. The adapter's highlight_node() is NOT
--- used here — instead we render directly into the tree buffer via extmarks
--- (virtual text at end-of-line) so we stay adapter-agnostic.
---
--- Indicators:
---   M  modified (working tree)   ●
---   A  added / staged             +
---   D  deleted                    -
---   R  renamed                    »
---   ?  untracked                  ?
---   !  ignored                    ·
---   C  conflict                   ✗
---
--- Updates on: BufEnter (tree buffer), BufWritePost (any buffer), FocusGained.

local notify   = require("filetree.util.notify").create("[filetree.git_status]")
local platform = require("filetree.util.platform")

local M = {}

---@type FiletreeGitStatusConfig
local _cfg = {
  enabled      = false,
  debounce_ms  = 300,
  show_ignored = false,
  signs = {
    modified  = { text = "●", hl = "DiagnosticWarn"  },
    added     = { text = "+", hl = "DiagnosticOk"    },
    deleted   = { text = "-", hl = "DiagnosticError" },
    renamed   = { text = "»", hl = "DiagnosticHint"  },
    untracked = { text = "?", hl = "Comment"         },
    ignored   = { text = "·", hl = "Comment"         },
    conflict  = { text = "✗", hl = "DiagnosticError" },
  },
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace id
local _ns = -1

---@type table<string, string>  abs_path → status_code ("M","A","D","R","?","!","C")
local _status_map = {}

---@type any?  uv timer for debouncing
local _timer = nil

-- ── Git query ─────────────────────────────────────────────────────────────────

---@param root string  git repo root directory
local function run_git(root)
  local args = { "git", "-C", root, "status", "--porcelain", "-u" }
  if _cfg.show_ignored then
    args[#args + 1] = "--ignored"
  end

  vim.system(args, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then return end
    local new_map = {}
    for line in (result.stdout or ""):gmatch("[^\n]+") do
      if #line >= 4 then
        local xy   = line:sub(1, 2)
        local path = line:sub(4):gsub('"', "")
        -- handle rename "old -> new"
        local rename_target = path:match("^.+ %-> (.+)$")
        if rename_target then path = rename_target end
        local abs = root .. "/" .. path
        abs = abs:gsub("\\", "/")

        local code
        if xy:find("U") or xy == "AA" or xy == "DD" then
          code = "C"
        elseif xy:sub(1,1) == "?" then
          code = "?"
        elseif xy:sub(1,1) == "!" then
          code = "!"
        elseif xy:sub(1,1) == "R" or xy:sub(2,2) == "R" then
          code = "R"
        elseif xy:sub(1,1) == "A" or xy:sub(2,2) == "A" then
          code = "A"
        elseif xy:sub(1,1) == "D" or xy:sub(2,2) == "D" then
          code = "D"
        else
          code = "M"
        end
        new_map[abs] = code
      end
    end
    _status_map = new_map
    M._render()
  end))
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

local _sign_map = {
  M = "modified",
  A = "added",
  D = "deleted",
  R = "renamed",
  ["?"] = "untracked",
  ["!"] = "ignored",
  C = "conflict",
}

function M._render()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if not bufnr or bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for linenr = 0, line_count - 1 do
    local node = _adapter.get_node_at_line and _adapter.get_node_at_line(bufnr, linenr)
    if node and node.path then
      local abs = node.path:gsub("\\", "/")
      local code = _status_map[abs]
      if code then
        local sign_key = _sign_map[code]
        local sign = sign_key and _cfg.signs[sign_key]
        if sign then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, -1, {
            virt_text       = { { " " .. sign.text, sign.hl } },
            virt_text_pos   = "eol",
            priority        = 50,
          })
        end
      end
    end
  end
end

-- ── Refresh ───────────────────────────────────────────────────────────────────

local function debounce_refresh()
  local uv = vim.uv or vim.loop
  if _timer then
    pcall(function() _timer:stop() end)
  else
    _timer = uv.new_timer()
  end
  _timer:start(_cfg.debounce_ms, 0, vim.schedule_wrap(function()
    M.refresh()
  end))
end

---Refresh git status for the current adapter root.
function M.refresh()
  if not _adapter then return end

  -- Try project_root first, fall back to cwd
  local root_path
  local ok_pr, pr = require("filetree.features").load("project_root")
  if ok_pr and type(pr.find) == "function" then
    local cur_buf = vim.api.nvim_get_current_buf()
    local bname = vim.api.nvim_buf_get_name(cur_buf)
    root_path = pr.find(bname ~= "" and bname or vim.fn.getcwd())
  else
    root_path = vim.fn.getcwd()
  end

  -- Verify it is actually a git repo
  local git_dir = root_path .. "/.git"
  if vim.fn.isdirectory(git_dir) == 0 and vim.fn.filereadable(git_dir) == 0 then
    return
  end

  run_git(root_path)
end

---Clear all git status decorations.
function M.clear()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  end
  _status_map = {}
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeGitStatusConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter
  _ns      = vim.api.nvim_create_namespace("filetree_git_status")

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_git_status", { clear = true })

  -- Re-render when entering the tree buffer
  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = "neo-tree,NvimTree",
    callback = function() debounce_refresh() end,
  })

  -- Re-query on file save or focus return
  vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained" }, {
    group    = _augroup,
    callback = function() debounce_refresh() end,
  })

  -- Re-render when tree buffer is redrawn (cursor moves inside tree)
  vim.api.nvim_create_autocmd("CursorMoved", {
    group   = _augroup,
    pattern = "*",
    callback = function()
      local ft = vim.bo.filetype
      if ft == "neo-tree" or ft == "NvimTree" then
        M._render()
      end
    end,
  })

  M.refresh()
end

function M.teardown()
  M.clear()
  _adapter = nil
  if _timer then
    pcall(function() _timer:stop(); _timer:close() end)
    _timer = nil
  end
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
