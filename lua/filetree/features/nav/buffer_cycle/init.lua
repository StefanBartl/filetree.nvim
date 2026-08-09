---@module 'filetree.features.nav.buffer_cycle'
--- Cycle the adjacent editor buffer without leaving the tree window.
---
--- Two keymaps (both active while focus is in a tree buffer):
---
---   <S-Tab>  — next buffer in the adjacent editor window     (like `:bnext`)
---   <M-Tab>  — previous buffer in the adjacent editor window (like `:bprevious`)
---
--- Mirrors pressing Tab/Shift-Tab from inside that editor window: the cycle
--- happens there, not in the tree, and the tree keeps focus throughout.
---
--- Config:
---   enabled       boolean
---   keymap_next   string?   Next buffer in adjacent window (default "<S-Tab>").
---   keymap_prev   string?   Previous buffer in adjacent window (default "<M-Tab>").

local notify  = require("filetree.util.notify").create("[filetree.buffer_cycle]")
local bufutil = require("filetree.util.buffer")

local map = require("filetree.util.map")
local tree_attach = require("filetree.util.tree_attach")
local M = {}

---@internal
---Run `cmd` ("bnext"/"bprevious") in the adjacent editor window without
---moving focus away from the tree.
---@param cmd string
local function cycle(cmd)
  local win = bufutil.find_editor_win(vim.api.nvim_get_current_win())
  if not win then
    notify.warn("No editor window found")
    return
  end
  local ok, err = pcall(vim.api.nvim_win_call, win, function()
    vim.cmd(cmd)
  end)
  if not ok then
    notify.warn("Buffer cycle failed: " .. tostring(err))
  end
end

---Switch the adjacent editor window to the next buffer.
function M.next()
  cycle("bnext")
end

---Switch the adjacent editor window to the previous buffer.
function M.prev()
  cycle("bprevious")
end

---@param config FiletreeBufferCycleConfig
function M.setup(config, _adapter)
  if not config.enabled then return end

  local keymap_next = config.keymap_next or "<S-Tab>"
  local keymap_prev = config.keymap_prev or "<M-Tab>"

  tree_attach.on_attach(function(buf)
    if keymap_next then
      map("n", keymap_next, M.next, {
        buffer = buf,
        silent = true,
        desc   = "Filetree: next buffer in adjacent editor window",
      })
    end

    if keymap_prev then
      map("n", keymap_prev, M.prev, {
        buffer = buf,
        silent = true,
        desc   = "Filetree: previous buffer in adjacent editor window",
      })
    end
  end)
end

function M.teardown()
end

return M
