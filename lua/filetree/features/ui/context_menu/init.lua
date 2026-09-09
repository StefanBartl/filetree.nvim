---@module 'filetree.features.context_menu'
---@brief Right-click context menu in the tree, via lib.nvim.contextmenu.
---@description
--- Binds a mouse trigger (default `<RightMouse>`) inside the tree buffer.
--- On click: moves the cursor to the clicked node first (so the menu acts on
--- what was actually clicked, not wherever the cursor happened to be), then
--- opens the menu through `lib.nvim.contextmenu`, populated with
--- `filetree.integrations.menu.items()` — the SAME curated, self-gating entry
--- list a host config could already wire up by hand. This feature only adds
--- the trigger; which entries appear is still controlled entirely by the
--- top-level `menu` config (group-level opt-out — see @types/config.lua).
---
--- `lib.nvim.contextmenu` resolves its own renderer -- nvzone/menu when it is
--- installed, `lib.nvim.ui.kit.menu` (no third-party dependency) otherwise --
--- so this feature needs neither directly. It is never require()d until the
--- first click. On by default (opt-out); degrades to a single notify, not an
--- error, only if lib.nvim itself predates `lib.nvim.contextmenu`.

local notify = require("filetree.util.notify").create("[filetree.context_menu]")
local bind = require("filetree.util.bind")

local M = {}

---@type FiletreeContextMenuConfig
local _cfg = {
  enabled = true,
  keymap = "<RightMouse>",
}

---@type boolean
local _warned_missing = false

---Move the tree cursor to the node under the mouse pointer, best-effort.
---Neovim already repositions the cursor for a plain buffer-local mouse
---mapping under the default 'mousemodel' (extend), but this is done
---explicitly too so the menu targets the right node even if the user has
---'mousemodel' set to "popup" or something else non-default.
local function move_to_click()
  local ok, pos = pcall(vim.fn.getmousepos)
  if not ok or not pos or pos.winid == 0 then return end
  if pos.winid ~= vim.api.nvim_get_current_win() then return end
  pcall(
    vim.api.nvim_win_set_cursor,
    pos.winid,
    { math.max(1, pos.line), math.max(0, pos.column - 1) }
  )
end

local function open_menu()
  move_to_click()

  local ok_items, items_mod = pcall(require, "filetree.integrations.menu")
  local items = ok_items and items_mod.items() or {}
  if #items == 0 then return end -- nothing enabled/available to show

  local ok_cm, contextmenu = pcall(require, "lib.nvim.contextmenu")
  if not ok_cm or type(contextmenu.open) ~= "function" then
    if not _warned_missing then
      notify.info(
        "lib.nvim.contextmenu unavailable — context_menu has nothing to open (update lib.nvim, or set features.context_menu.enabled = false)"
      )
      _warned_missing = true
    end
    return
  end

  contextmenu.open(items, { mouse = true })
end

---@param config FiletreeContextMenuConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  -- Merge onto _cfg's own defaults, not a bare overwrite: filetree/init.lua's
  -- setup loop only guarantees `enabled` is set on the incoming table — a user
  -- who never configures features.context_menu at all still needs the default
  -- keymap to survive, not get wiped out by `config` not mentioning it.
  _cfg = vim.tbl_deep_extend("force", _cfg, config)

  if not _cfg.keymap then return end

  bind.bind("context_menu", _cfg, {
    { name = "open", field = "keymap", rhs = open_menu, desc = "right-click context menu" },
  })
end

function M.teardown()
  _warned_missing = false
end

return M
