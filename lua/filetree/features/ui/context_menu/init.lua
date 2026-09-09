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
---
--- Two extras, both kit-renderer only (lib.nvim.contextmenu has no
--- equivalent hook for nvzone/menu, so they no-op there):
---  * the clicked node's line is highlighted for as long as the menu stays
---    open, so it is never ambiguous which node an entry would act on;
---  * with the tree docked left/right, the menu opens beside the tree
---    window instead of at the click -- which would otherwise sit on top
---    of, and often fully hide, the very row it is highlighting.

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

---@type FiletreeAdapter?
local _adapter = nil

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

-- ── Clicked-node highlight, for the life of the menu ────────────────────────

local NODE_HL = "FiletreeContextMenuNode"
local _hl_ensured = false
---@type string?
local _highlighted_path = nil
---@type integer?
local _hl_augroup = nil

---@internal
local function ensure_node_hl()
  if _hl_ensured then return end
  _hl_ensured = true
  -- `default = true`: a colorscheme or the user's own config may already
  -- define this group (or link it elsewhere); this only supplies a sensible
  -- fallback, never overrides one already set. Linked rather than a fixed
  -- hex color so it matches whatever theme is active, the same way the kit
  -- menu's own selection highlight does.
  pcall(vim.api.nvim_set_hl, 0, NODE_HL, { link = "Visual", default = true })
end

---@internal
local function clear_node_highlight()
  if _highlighted_path and _adapter and _adapter.unhighlight_node then
    pcall(_adapter.unhighlight_node, _highlighted_path)
  end
  _highlighted_path = nil
end

---@internal
--- Highlight the node the menu is about to act on. A one-shot fallback
--- (the next time the cursor actually moves within the tree buffer) also
--- clears it, in case the renderer never gives back a close hook to do it
--- promptly (nvzone/menu has none) or the menu fails to open at all.
---
--- Deliberately `CursorMoved` only, NOT `BufLeave`: opening the menu itself
--- moves focus to its own window (kit's float is `enter = true`; nvzone/menu
--- likely does the same), which fires `BufLeave` on the tree buffer as a
--- pure side effect of the menu appearing -- before the user has even seen
--- it. That cleared the highlight instantly on every click, which is a
--- silent no-op from the user's perspective: indistinguishable from the
--- highlight never having been applied at all. `CursorMoved` only fires
--- from an actual cursor move while the tree buffer is the one being
--- edited, which cannot happen while a floating menu holds focus.
local function highlight_current_node()
  if not _adapter or not _adapter.get_current_node or not _adapter.highlight_node then
    notify.warn(
      "context_menu: adapter is missing get_current_node/highlight_node -- cannot highlight"
    )
    return
  end
  local node = _adapter.get_current_node()
  if not node or not node.path then
    -- Diagnostic, not silence: a report of "no highlight" with nothing here
    -- means this branch, not a rendering problem -- get_current_node() (or
    -- the cursor move that precedes it) is the thing to look at next.
    notify.warn("context_menu: adapter.get_current_node() returned nothing to highlight")
    return
  end

  ensure_node_hl()
  clear_node_highlight() -- in case a previous click's highlight is still up
  local hl_ok = _adapter.highlight_node(node.path, NODE_HL)
  if hl_ok then
    _highlighted_path = node.path
  else
    notify.warn("context_menu: adapter.highlight_node() failed for " .. node.path)
  end

  local buf = vim.api.nvim_get_current_buf()
  _hl_augroup = vim.api.nvim_create_augroup("FiletreeContextMenuHlFallback", { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = _hl_augroup,
    buffer = buf,
    once = true,
    callback = clear_node_highlight,
  })
end

-- ── Positioning beside the tree, when it is docked left/right ───────────────

---@internal
--- Extra `lib.nvim.contextmenu.open` opts that anchor the menu just outside
--- the tree window (`relative = "win"`, offset from ITS top-left corner) so
--- it never overlaps the tree itself -- and so never the highlighted row
--- from `highlight_current_node` either. `{}` (fall back to the default
--- mouse anchor) whenever the tree's side isn't left/right: "float"/
--- "current" have no fixed edge to dock the menu against, and covering the
--- tree briefly there is the accepted tradeoff -- the row is still marked,
--- just not necessarily visible the whole time the menu is open.
---@return table
local function beside_tree_opts()
  if not _adapter or not _adapter.get_winid or not _adapter.get_position then return {} end
  local winid = _adapter.get_winid()
  if not winid or not vim.api.nvim_win_is_valid(winid) then return {} end
  local pos = _adapter.get_position()
  if pos ~= "left" and pos ~= "right" then return {} end

  local row = 0
  local ok_cur, cur = pcall(vim.api.nvim_win_get_cursor, winid)
  if ok_cur then row = math.max(0, cur[1] - 1) end

  if pos == "left" then
    -- Float's top-left corner sits at the tree window's own right edge.
    return {
      relative = "win",
      win = winid,
      anchor = "NW",
      row = row,
      col = vim.api.nvim_win_get_width(winid),
    }
  end
  -- "right": float's top-RIGHT corner sits at the tree window's left edge
  -- (col = 0) -- extends leftward, away from the tree, without needing to
  -- know the float's own width up front.
  return { relative = "win", win = winid, anchor = "NE", row = row, col = 0 }
end

local function open_menu()
  move_to_click()
  highlight_current_node()

  local ok_items, items_mod = pcall(require, "filetree.integrations.menu")
  local items = ok_items and items_mod.items() or {}
  if #items == 0 then
    clear_node_highlight()
    return -- nothing enabled/available to show
  end

  local ok_cm, contextmenu = pcall(require, "lib.nvim.contextmenu")
  if not ok_cm or type(contextmenu.open) ~= "function" then
    clear_node_highlight()
    if not _warned_missing then
      notify.info(
        "lib.nvim.contextmenu unavailable — context_menu has nothing to open (update lib.nvim, or set features.context_menu.enabled = false)"
      )
      _warned_missing = true
    end
    return
  end

  local open_opts = vim.tbl_extend("force", { mouse = true }, beside_tree_opts())
  local surf = contextmenu.open(items, open_opts)
  -- Kit renderer: clear promptly when the menu actually closes, on top of
  -- the CursorMoved/BufLeave fallback above. nvzone/menu (surf is nil here)
  -- has no close hook to offer, so the fallback is all it gets.
  if surf and surf.on_close then surf:on_close(clear_node_highlight) end
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
  _adapter = adapter

  if not _cfg.keymap then return end

  bind.bind("context_menu", _cfg, {
    { name = "open", field = "keymap", rhs = open_menu, desc = "right-click context menu" },
  })
end

function M.teardown()
  _warned_missing = false
  clear_node_highlight()
  if _hl_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _hl_augroup)
    _hl_augroup = nil
  end
  _adapter = nil
end

return M
