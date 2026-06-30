---@module 'filetree.features.git_actions'
---@brief Lightweight git operations (stage, unstage, stash, log) from the tree.
---@description
--- Complements git_status (which shows indicators) with actual git operations
--- on the current tree node. All operations use vim.system() for async exec.
---
--- Operations:
---   stage_current()   — git add <path>
---   unstage_current() — git restore --staged <path>
---   stash()           — git stash (working tree stash)
---   stash_pop()       — git stash pop
---   log_current()     — git log --oneline <path> → quickfix list
---
--- Config:
---   enabled             boolean
---   keymap_stage        string?  Key inside tree (default "gs").
---   keymap_unstage      string?  Key inside tree (default "gS").
---   keymap_log          string?  Key inside tree (default "gl").
---
--- Commands (via :Filetree dispatcher):
---   :Filetree git stage
---   :Filetree git unstage
---   :Filetree git stash
---   :Filetree git stash-pop
---   :Filetree git log

local notify = require("filetree.util.notify").create("[filetree.git_actions]")

local M = {}

---@type FiletreeGitActionsConfig
local _cfg = {
  enabled        = false,
  keymap_stage   = "gs",
  keymap_unstage = "gS",
  keymap_log     = "gl",
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function current_path()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()
  return node and node.path or nil
end

local function git_root(path)
  if not path then return nil end
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
  local result = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if result.code == 0 then
    return vim.trim(result.stdout or "")
  end
  return nil
end

local function run_git(args, on_done)
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      on_done(result)
      if _adapter and _adapter.refresh then _adapter.refresh() end
    end)
  end)
end

-- ── Operations ────────────────────────────────────────────────────────────────

function M.stage_current()
  local path = current_path()
  if not path then notify.warn("No node under cursor"); return end
  run_git({ "git", "add", "--", path }, function(r)
    if r.code == 0 then
      notify.info("Staged: " .. vim.fn.fnamemodify(path, ":t"))
    else
      notify.error("git add failed: " .. (r.stderr or ""))
    end
  end)
end

function M.unstage_current()
  local path = current_path()
  if not path then notify.warn("No node under cursor"); return end
  run_git({ "git", "restore", "--staged", "--", path }, function(r)
    if r.code == 0 then
      notify.info("Unstaged: " .. vim.fn.fnamemodify(path, ":t"))
    else
      notify.error("git restore --staged failed: " .. (r.stderr or ""))
    end
  end)
end

function M.stash()
  local path = current_path()
  local root = git_root(path) or vim.fn.getcwd()
  run_git({ "git", "-C", root, "stash" }, function(r)
    if r.code == 0 then
      local msg = vim.trim(r.stdout or ""):match("^([^\n]+)") or "stash created"
      notify.info(msg)
    else
      notify.error("git stash failed: " .. (r.stderr or ""))
    end
  end)
end

function M.stash_pop()
  local path = current_path()
  local root = git_root(path) or vim.fn.getcwd()
  run_git({ "git", "-C", root, "stash", "pop" }, function(r)
    if r.code == 0 then
      notify.info("Stash popped")
    else
      notify.error("git stash pop failed: " .. (r.stderr or ""))
    end
  end)
end

function M.log_current()
  local path = current_path()
  if not path then notify.warn("No node under cursor"); return end
  vim.system(
    { "git", "log", "--oneline", "--follow", "--", path },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          notify.error("git log failed: " .. (result.stderr or ""))
          return
        end
        local lines = vim.split(vim.trim(result.stdout or ""), "\n", { plain = true })
        if #lines == 0 or (lines[1] == "") then
          notify.info("No commits for " .. vim.fn.fnamemodify(path, ":t"))
          return
        end
        local qf = {}
        for _, line in ipairs(lines) do
          if line ~= "" then
            local hash, msg = line:match("^(%x+) (.+)$")
            qf[#qf + 1] = { text = line, col = 0, lnum = 1,
              filename = hash and "" or "" }
          end
        end
        vim.fn.setqflist({}, "r", {
          title = "git log: " .. vim.fn.fnamemodify(path, ":t"),
          items = vim.tbl_map(function(l)
            return { text = l, lnum = 1, col = 1, filename = "" }
          end, lines),
        })
        vim.cmd("copen")
      end)
    end
  )
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeGitActionsConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_git_actions", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if _cfg.keymap_stage then
          vim.keymap.set("n", _cfg.keymap_stage, M.stage_current, {
            buffer = buf, silent = true, desc = "Filetree: git stage current node",
          })
        end
        if _cfg.keymap_unstage then
          vim.keymap.set("n", _cfg.keymap_unstage, M.unstage_current, {
            buffer = buf, silent = true, desc = "Filetree: git unstage current node",
          })
        end
        if _cfg.keymap_log then
          vim.keymap.set("n", _cfg.keymap_log, M.log_current, {
            buffer = buf, silent = true, desc = "Filetree: git log for current node",
          })
        end
      end)
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
