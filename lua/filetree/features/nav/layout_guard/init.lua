---@module 'filetree.features.nav.layout_guard'
--- Ensure an editor window always exists when the tree is the only window.
---
--- When the user closes all editor windows but leaves the tree open, this
--- feature automatically opens a new empty window so the user is never
--- trapped inside the tree with no place to edit files.

local au = require("filetree.util.autocmd")
local window = require("filetree.util.window")

local M = {}

---@type integer?
local _augroup = nil

---Create an empty editor window next to the tree — on the side AWAY from it.
---@param adapter FiletreeAdapter
local function ensure_editor(adapter)
  -- Count normal (non-tree) windows
  local tree_winid = adapter.get_winid()
  local normal_wins = 0
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if winid ~= tree_winid then
      local cfg = vim.api.nvim_win_get_config(winid)
      if cfg.relative == "" then -- not a floating window
        normal_wins = normal_wins + 1
      end
    end
  end

  if normal_wins > 0 then return end

  -- Pinned to the edge opposite the tree. A bare `:vsplit` here would follow
  -- 'splitright' relative to the (now full-width) tree window, so with the
  -- default `splitright = false` the new window landed on the tree's LEFT —
  -- leaving a left sidebar sitting on the right of the screen afterwards. The
  -- guard fires from BufDelete/WinClosed, which routinely happens while a
  -- picker float is up, so this looked like "the tree jumps sides now and then
  -- after using a picker".
  window.open_editor_window(adapter, { empty = true })
end

---@param config FiletreeLayoutGuardConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local delay = config.delay_ms or 50

  au.del_group(_augroup)
  _augroup = au.group("filetree_layout_guard", true)

  au.acmd({ "BufDelete", "BufWipeout", "WinClosed" }, {
    group = _augroup,
    callback = function()
      vim.defer_fn(function()
        if not adapter.is_open() then return end
        ensure_editor(adapter)
      end, delay)
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
