---@module 'filetree.features.buffer_save'
---@brief Force-save a buffer without leaving the tree window.
---@description
--- Two keymaps (both active while focus is in a tree buffer):
---
---   <C-s>  — save the last-focused adjacent editor buffer (analog to the
---             user pressing <C-s> while editing that file).
---   <M-s>  — save the buffer whose path matches the node under the cursor;
---             useful for saving a background buffer you can see in the tree
---             without switching to it first.
---
--- Both use `write!` (force-write) by default.  Set `force = false` to use
--- `update` instead (no-op when buffer is unmodified; never overwrites
--- read-only files).
---
--- Config:
---   enabled          boolean
---   keymap_adjacent  string?   Save adjacent editor buffer (default "<C-s>").
---   keymap_node      string?   Save buffer for node under cursor (default "<M-s>").
---   force            boolean   Use write! instead of update (default true).

local notify = require("filetree.util.notify").create("[filetree.buffer_save]")

local M = {}

local _TREE_FT = {
  ["neo-tree"] = true, ["NvimTree"] = true,
  ["netrw"]    = true, ["oil"]      = true, ["minifiles"] = true,
}

---Return the last-focused non-tree window, or nil.
local function find_adjacent_win()
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

---Save buffer `bufnr`.  Returns true on success.
---@param bufnr  integer
---@param force  boolean  true → write!   false → update
---@return boolean
local function save_buf(bufnr, force)
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    notify.warn("No valid buffer to save")
    return false
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    notify.warn("Buffer has no file name — use :w to name it first")
    return false
  end

  local cmd = force and "write!" or "update"
  local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd(cmd)
  end)

  if ok then
    notify.info("Saved: " .. vim.fn.fnamemodify(name, ":~:."))
    return true
  else
    notify.warn("Save failed: " .. tostring(err))
    return false
  end
end

---@type integer?
local _augroup = nil

---@param config FiletreeBufferSaveConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local keymap_adj  = config.keymap_adjacent or "<C-s>"
  local keymap_node = config.keymap_node     or "<M-s>"
  local force       = config.force ~= false  -- default true

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_buffer_save", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end

        -- <C-s>: save the last adjacent editor buffer
        if keymap_adj then
          vim.keymap.set("n", keymap_adj, function()
            local win = find_adjacent_win()
            if not win then
              notify.warn("No editor window found")
              return
            end
            save_buf(vim.api.nvim_win_get_buf(win), force)
          end, {
            buffer = buf,
            silent = true,
            desc   = "Filetree: force-save adjacent editor buffer",
          })
        end

        -- <M-s>: save the buffer whose path matches the node under cursor
        if keymap_node then
          vim.keymap.set("n", keymap_node, function()
            local node = adapter.get_current_node and adapter.get_current_node()
            if not node or not node.path or node.path == "" then
              notify.warn("No file node under cursor")
              return
            end
            local bufnr = vim.fn.bufnr(node.path)
            if bufnr < 0 then
              notify.warn("File not loaded: " .. vim.fn.fnamemodify(node.path, ":~:."))
              return
            end
            save_buf(bufnr, force)
          end, {
            buffer = buf,
            silent = true,
            desc   = "Filetree: force-save buffer matching node under cursor",
          })
        end
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
