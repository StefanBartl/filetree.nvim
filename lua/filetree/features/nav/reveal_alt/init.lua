---@module 'filetree.features.reveal_alt'
---@brief Reveal the alternate buffer (#) in the tree.
---@description
--- Binds a key (default `B`) in the tree buffer.  On activation it resolves
--- the alternate buffer path (`vim.fn.expand("#:p")`), validates that the file
--- is readable, and calls `adapter.open_reveal()` to navigate the tree to it —
--- adjusting the root if the file is outside the current tree root.
---
--- Mirrors the `B` mapping in the user's neotree config (analog to `:e #`).
---
--- Config:
---   enabled  boolean
---   keymap   string?   Key in tree buffer (default "B").

local notify = require("filetree.util.notify").create("[filetree.reveal_alt]")

local M = {}

---@type integer?
local _augroup = nil

---@param config FiletreeRevealAltConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local keymap = config.keymap or "B"

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_reveal_alt", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.keymap.set("n", keymap, function()
          local alt = vim.fn.expand("#:p")
          if not alt or alt == "" then
            notify.warn("No alternate buffer")
            return
          end
          if vim.fn.filereadable(alt) ~= 1 then
            notify.warn("Alternate buffer is not a readable file: " .. alt)
            return
          end
          if type(adapter.open_reveal) == "function" then
            local ok, err = pcall(adapter.open_reveal, alt, 0)
            if not ok then notify.warn("Reveal failed: " .. tostring(err)) end
          else
            notify.warn("Adapter does not support open_reveal")
          end
        end, {
          buffer = buf,
          silent = true,
          desc   = "Filetree: reveal alternate buffer in tree",
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
