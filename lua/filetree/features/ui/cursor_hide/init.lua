---@module 'filetree.features.cursor_hide'
---@brief Hide the block cursor while the tree window is focused.
---@description
--- Creates a window-local highlight override (winhighlight) so the cursor
--- disappears when focus is inside a tree buffer, and reappears on leave.
--- Uses a dedicated `FiletreeCursorHidden` hl group with blend=100 so the
--- global Cursor group is never touched.
---
--- Config:
---   enabled  boolean

local au  = require("filetree.util.autocmd")
local M = {}

local _TREE_FT = { ["neo-tree"] = true, ["NvimTree"] = true,
                   ["netrw"] = true, ["oil"] = true, ["minifiles"] = true }

---@type integer?
local _augroup = nil

---@param config FiletreeCursorHideConfig
function M.setup(config, _adapter)
  if not config.enabled then return end

  vim.api.nvim_set_hl(0, "FiletreeCursorHidden", { blend = 100, nocombine = true })

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_cursor_hide", true)

  au.acmd({ "BufEnter", "WinEnter" }, {
    group = _augroup,
    callback = function(ev)
      if _TREE_FT[vim.bo[ev.buf].filetype] then
        local win = vim.api.nvim_get_current_win()
        pcall(vim.api.nvim_set_option_value, "winhighlight",
          "Cursor:FiletreeCursorHidden", { win = win })
      end
    end,
  })

  au.acmd({ "BufLeave", "WinLeave" }, {
    group = _augroup,
    callback = function(ev)
      if _TREE_FT[vim.bo[ev.buf].filetype] then
        local win = vim.api.nvim_get_current_win()
        -- Strip our override; leave any other winhighlight entries intact.
        local ok, cur = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = win })
        if not ok then return end
        local cleaned = cur:gsub(",?Cursor:FiletreeCursorHidden,?", ""):gsub("^,", ""):gsub(",$", "")
        pcall(vim.api.nvim_set_option_value, "winhighlight", cleaned, { win = win })
      end
    end,
  })
end

function M.teardown()
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
