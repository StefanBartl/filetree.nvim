---@module 'filetree.features.fileops.buffer_save'
--- Force-save a buffer without leaving the tree window.
---
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
local bufutil = require("filetree.util.buffer")
local bind = require("filetree.util.bind")

local M = {}

---Option schema (see `filetree.config.schema`): exactly what
---`features.buffer_save` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {
  force = "boolean",
  keymap_adjacent = "keymap",
  keymap_node = "keymap",
}

---Seam for the name of a buffer that has none (`nil`: `ui.kit.input`, `vim.ui.input` as the fallback); specs replace it.
---`cb` gets the name, or `nil` when the prompt was dismissed.
---@type (fun(default: string, cb: fun(name: string|nil)))|nil
M.ask_name = nil

---@param default string
---@param cb fun(name: string|nil)
local function ask_name(default, cb)
  if M.ask_name then return M.ask_name(default, cb) end
  local prompt = "Save as: "
  local ok, kit = pcall(require, "ui.kit")
  if ok and type(kit) == "table" and type(kit.input) == "function" then
    local shown = pcall(kit.input, {
      prompt = prompt,
      default = default,
      completion = "file",
      on_submit = cb,
      on_cancel = function()
        cb(nil)
      end,
    })
    if shown then return end
  end
  vim.ui.input({ prompt = prompt, default = default, completion = "file" }, cb)
end

---@internal
---Save buffer `bufnr`.  Returns true on success; a buffer with no name asks for one and returns false (the save follows
---the answer).
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
    -- the name can be asked for right here; the file is written with a plain `:write`, which refuses to replace one
    ask_name(vim.fn.getcwd() .. "/", function(chosen)
      chosen = chosen and vim.trim(chosen) or ""
      if chosen == "" or chosen:sub(-1) == "/" then
        notify.info("Not saved: no file name given")
        return
      end
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      local wrote, werr = pcall(vim.api.nvim_buf_call, bufnr, function()
        vim.cmd("write " .. vim.fn.fnameescape(chosen))
      end)
      if wrote then
        notify.info("Saved: " .. vim.fn.fnamemodify(chosen, ":~:."))
      else
        notify.warn("Save failed: " .. tostring(werr))
      end
    end)
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

---@type FiletreeAdapter?
local _adapter = nil
---@type boolean
local _force = true

---Force-save the last-focused adjacent editor buffer.
function M.save_adjacent()
  local win = bufutil.find_editor_win(vim.api.nvim_get_current_win())
  if not win then
    notify.warn("No editor window found")
    return
  end
  save_buf(vim.api.nvim_win_get_buf(win), _force)
end

---Force-save the buffer whose path matches the node under the cursor.
function M.save_node()
  local node = _adapter and _adapter.get_current_node and _adapter.get_current_node()
  if not node or not node.path or node.path == "" then
    notify.warn("No file node under cursor")
    return
  end
  local bufnr = vim.fn.bufnr(node.path)
  if bufnr < 0 then
    notify.warn("File not loaded: " .. vim.fn.fnamemodify(node.path, ":~:."))
    return
  end
  save_buf(bufnr, _force)
end

---@param config FiletreeBufferSaveConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  _adapter = adapter
  _force = config.force ~= false -- default true

  bind.bind("buffer_save", config, {
    {
      name = "save_adjacent",
      field = "keymap_adjacent",
      default = "<C-s>",
      rhs = M.save_adjacent,
      desc = "force-save adjacent editor buffer",
    },
    {
      name = "save_node",
      field = "keymap_node",
      default = "<M-s>",
      rhs = M.save_node,
      desc = "force-save buffer matching node under cursor",
    },
  })
end

function M.teardown() end

return M
