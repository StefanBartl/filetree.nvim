---@module 'filetree.attach'
--- neo-tree specifics that are not a feature of their own.
---
--- This module used to inject filetree's keymaps into neo-tree's
--- `window.mappings` so they showed up in neo-tree's native `?` help. That list
--- was a hand-kept table that lagged the features (a rebound `D` was listed under
--- neo-tree's own action for it), and the injection had a second, worse effect:
--- it ran after neo-tree's own setup, so it was the last word and overruled a
--- user's `window.mappings` for a key they had switched off in one source.
---
--- Both are gone. filetree binds its keys itself, buffer-locally, through
--- `util.tree_attach` (which is what a keypress always reached), and its own `?`
--- cheatsheet (`features.ui.cheatsheet`) reads what is actually bound -- filetree's
--- keys and neo-tree's native ones -- so there is no second list to keep in step.

local au = require("filetree.util.autocmd")

local M = {}

---Kept so an existing config that calls `require("filetree").attach(opts, config)`
---before `neo-tree.setup(opts)` keeps working: there is nothing left to inject,
---so `opts` comes back untouched.
---@deprecated filetree binds its keys itself; the `?` cheatsheet lists them.
---@param opts table?
---@return table opts
function M.neotree(opts)
  return opts or {}
end

---@type integer?
local _popup_augroup = nil

---Restore native `/` search in neo-tree's help (`?`) popup.
---
---neo-tree's help screen maps *every* tree key inside the popup to run that
---command (so you can press a key to execute it). That means `/` runs the tree
---filter instead of searching the help text. This registers a `neo-tree-popup`
---FileType autocmd that removes the popup's buffer-local `/` (and `?`) maps, so
---they fall back to Neovim's built-in `/` search and native paging. `n`/`N` are
---not mapped by neo-tree, so they already page through matches natively.
---Only matters when neo-tree's own help is reachable (filetree's `?` cheatsheet
---replaces it by default).
---Idempotent — safe to call once at setup.
---@param keys string[]?  Keys to hand back to native behaviour (default { "/" }).
function M.native_search_in_help(keys)
  keys = keys or { "/" }
  if _popup_augroup then au.del_group(_popup_augroup) end
  _popup_augroup = au.group("filetree_neotree_popup_search", true)
  au.create("FileType", function(ev)
    local buf = ev.buf
    -- Defer past neo-tree's own popup:map() calls so our removal wins.
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      for _, key in ipairs(keys) do
        pcall(vim.keymap.del, "n", key, { buffer = buf })
      end
    end)
  end, {
    group = _popup_augroup,
    pattern = "neo-tree-popup",
    desc = "[filetree] Give `/` back its native search inside neo-tree's help popup",
  })
end

return M
