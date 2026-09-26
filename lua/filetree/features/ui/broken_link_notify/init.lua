---@module 'filetree.features.ui.broken_link_notify'
---@brief Warn when a just-opened buffer turned out to be a broken symlink.
---@description
--- Opening a dangling symlink's target (`<CR>` in the tree, `gf`, a plain
--- `:edit`, any of it) reads exactly like opening any other nonexistent
--- path to Neovim: it silently creates an empty `[New]` buffer, no error,
--- no hint. The symlink itself may have a sign in the tree (see Link
--- Marker), but once its target is actually open in an editor window, that
--- context is gone — an empty buffer with no further explanation.
---
--- `BufNewFile` fires exactly when Neovim could not read the path it was
--- asked to open, which is precisely the dangling-symlink case (Neovim
--- never resolves through the link itself; the buffer name IS the
--- symlink's own path). One global, backend-agnostic autocmd catches every
--- way a node ends up opened this way — neo-tree's own native `<CR>`,
--- `open_variants`' split/vsplit/tabnew, `open_replace`'s edit/swap — none
--- of which need to know about this feature at all.

local au = require("filetree.util.autocmd")
local symlink_util = require("filetree.util.symlink")
local notify = require("filetree.util.notify").create("[filetree.broken_link_notify]")

local M = {}

---Option schema (see `filetree.config.schema`): exactly what
---`features.broken_link_notify` accepts. Keep it in step with the keys this
---module reads; `TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {}

---@type integer?
local _augroup = nil

---@param _config FiletreeBrokenLinkNotifyConfig
function M.setup(_config)
  au.del_group(_augroup)
  _augroup = au.group("filetree_broken_link_notify", true)

  au.acmd("BufNewFile", {
    group = _augroup,
    pattern = "*",
    desc = "[filetree] Warn when the just-created empty buffer is a dangling symlink's target",
    callback = function(event)
      local path = vim.api.nvim_buf_get_name(event.buf)
      if path == "" then return end
      if symlink_util.is_broken(path) then
        notify.warn("Broken symlink — its target does not exist: " .. path)
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
