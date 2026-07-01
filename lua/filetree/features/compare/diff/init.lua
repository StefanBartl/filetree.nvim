---@module 'filetree.features.diff'
---@brief Side-by-side file diff triggered from the tree.
---@description
--- Two workflows:
---   1. Mark two files via the marks feature, then call M.diff_marked().
---   2. Call M.stage(path) on a first file, then M.diff_current() on a second.
---
--- Uses Neovim's built-in :diffthis. Files open in vertical splits by default.

local notify = require("filetree.util.notify").create("[filetree.diff]")

local M = {}

---@type FiletreeDiffConfig
local _cfg = {
  enabled = false,
  split   = "vsplit",
  keymap  = "D",
}

---@type FiletreeAdapter?
local _adapter = nil

---@type string?  first file staged for diffing
local _staged = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function open_diff(path_a, path_b)
  if vim.fn.filereadable(path_a) == 0 then
    notify.error("not readable: " .. path_a)
    return false
  end
  if vim.fn.filereadable(path_b) == 0 then
    notify.error("not readable: " .. path_b)
    return false
  end

  -- Close existing diff windows
  vim.cmd("diffoff!")

  local split = _cfg.split or "vsplit"
  vim.cmd(split .. " " .. vim.fn.fnameescape(path_a))
  vim.cmd("diffthis")

  vim.cmd(split .. " " .. vim.fn.fnameescape(path_b))
  vim.cmd("diffthis")

  vim.cmd("wincmd =") -- equalize window sizes
  return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Stage a file as the first half of a diff.
---@param path string
function M.stage(path)
  if vim.fn.filereadable(path) == 0 then
    notify.warn("not a readable file: " .. path)
    return
  end
  _staged = path
  notify.info("Staged for diff: " .. vim.fn.fnamemodify(path, ":t"))
end

---Return the currently staged path.
---@return string?
function M.staged()
  return _staged
end

---Clear the staged file.
function M.clear_stage()
  _staged = nil
  notify.info("Diff stage cleared")
end

---Diff the staged file against `path`.
---@param path string
---@return boolean ok
function M.diff(path)
  if not _staged then
    notify.warn("No file staged. Call M.stage(path) first or use M.diff_marked().")
    return false
  end
  local ok = open_diff(_staged, path)
  if ok then _staged = nil end
  return ok
end

---Stage or diff the current node depending on whether a file is already staged.
---First call: stages the current node.
---Second call: diffs staged file against the current node.
function M.stage_or_diff_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or node.type ~= "file" then
    notify.warn("cursor is not on a file")
    return
  end
  if not _staged then
    M.stage(node.path)
  else
    M.diff(node.path)
  end
end

---Diff the two marked files (requires marks feature with exactly 2 marks).
---@return boolean ok
function M.diff_marked()
  local ok_marks, marks = require("filetree.features").load("marks")
  if not ok_marks then
    notify.error("marks feature not loaded")
    return false
  end
  local marked = marks.get_marked()
  if #marked ~= 2 then
    notify.warn(string.format("Need exactly 2 marked files to diff (have %d)", #marked))
    return false
  end
  local ok = open_diff(marked[1], marked[2])
  if ok then marks.clear_all() end
  return ok
end

---Close all diff windows and turn off diff mode.
function M.close()
  vim.cmd("diffoff!")
  _staged = nil
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeDiffConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_diff", { clear = true })

  if _cfg.keymap then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.keymap.set("n", _cfg.keymap, M.stage_or_diff_current, {
            buffer = buf,
            silent = true,
            desc   = "Filetree: stage/diff current file",
          })
        end)
      end,
    })
  end

end

function M.teardown()
  _staged   = nil
  _adapter  = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
