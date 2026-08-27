---@module 'filetree.features.nav.buffer_cycle'
--- Cycle the adjacent editor buffer without leaving the tree window.
---
--- Two keymaps (both active while focus is in a tree buffer):
---
---   <C-n>  — next buffer in the adjacent editor window     (like `:bnext`)
---   <C-p>  — previous buffer in the adjacent editor window (like `:bprevious`)
---
--- Mirrors switching buffers from inside that editor window: the cycle
--- happens there, not in the tree, and the tree keeps focus throughout.
---
--- Both keys are unbound in neo-tree's own default window.mappings (unlike
--- <C-f>/<C-b>, which neo-tree's defaults.lua claims natively for
--- scroll_preview — verified live via nvim_buf_get_keymap() against a real
--- neo-tree tree buffer, not just a source read).
---
--- Config:
---   enabled       boolean
---   keymap_next   string?   Next buffer in adjacent window (default "<C-n>").
---   keymap_prev   string?   Previous buffer in adjacent window (default "<C-p>").

local notify = require("filetree.util.notify").create("[filetree.buffer_cycle]")
local bufutil = require("filetree.util.buffer")
local bind = require("filetree.util.bind")

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
  if not ok then notify.warn("Buffer cycle failed: " .. tostring(err)) end
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

  bind.bind("buffer_cycle", config, {
    {
      name = "next",
      field = "keymap_next",
      default = "<C-n>",
      rhs = M.next,
      desc = "next buffer in adjacent editor window",
    },
    {
      name = "prev",
      field = "keymap_prev",
      default = "<C-p>",
      rhs = M.prev,
      desc = "previous buffer in adjacent editor window",
    },
  })
end

function M.teardown() end

return M
