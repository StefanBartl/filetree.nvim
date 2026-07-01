---@module 'filetree.features.open_replace'
---@brief Open file under cursor and replace the current editor buffer.
---@description
--- Binds a key (default `O`) in the tree buffer.  On activation it:
---
---   1. Finds the most-recently-focused non-tree window.
---   2. Opens the node's file there with `:edit` (replaces that buffer in-place,
---      no new split or tab).
---   3. Optionally closes the tree (config.close_tree, default true).
---
--- Only acts on file nodes; silently ignores directories.
---
--- Config:
---   enabled     boolean
---   keymap      string?   Key in tree buffer (default "O").
---   close_tree  boolean   Close the tree after opening (default true).

local notify = require("filetree.util.notify").create("[filetree.open_replace]")

local M = {}

local _TREE_FT = { ["neo-tree"] = true, ["NvimTree"] = true,
                   ["netrw"] = true, ["oil"] = true, ["minifiles"] = true }

---Return the last-focused non-tree window, or nil.
local function find_editor_win()
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  if prev and prev ~= 0 and vim.api.nvim_win_is_valid(prev) then
    if not _TREE_FT[vim.bo[vim.api.nvim_win_get_buf(prev)].filetype] then
      return prev
    end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not _TREE_FT[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
      return win
    end
  end
  return nil
end

---@type integer?
local _augroup = nil
---@type FiletreeAdapter?
local _adapter = nil
---@type boolean
local _close_tree = true

---Open the file under the cursor, replacing the current editor buffer.
function M.open_replace()
  local adapter = _adapter
  if not adapter then return end
  local node = adapter.get_current_node and adapter.get_current_node()
  if not node or node.type == "directory" then return end
  local path = node.path
  if not path or path == "" then return end

  local ewin = find_editor_win()
  if ewin then
    vim.api.nvim_set_current_win(ewin)
  else
    -- No editor window open yet; let the close+edit flow create one.
  end

  local ok = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(path))
  if not ok then
    notify.warn("Could not open: " .. path)
    return
  end

  if _close_tree and type(adapter.close) == "function" then
    pcall(adapter.close)
  end
end

---@param config FiletreeOpenReplaceConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local keymap    = config.keymap     or "O"
  _adapter    = adapter
  _close_tree = config.close_tree ~= false

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_open_replace", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.keymap.set("n", keymap, M.open_replace, {
          buffer = buf,
          silent = true,
          desc   = "Filetree: open file replacing current editor buffer",
        })
      end)
    end,
  })
end

function M.teardown()
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
