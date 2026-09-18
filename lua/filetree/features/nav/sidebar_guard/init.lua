---@module 'filetree.features.nav.sidebar_guard'
---@brief Pin the tree window to its side so a stray `:buffer` / mouse click
---       can't hijack it and make it reopen on the wrong side.
---@description
--- Neither neo-tree nor nvim-tree marks its sidebar window `winfixbuf`, so any
--- code that runs `nvim_set_current_buf()` / `:buffer N` while the cursor is in
--- the tree window swaps the tree's buffer out of it. neo-tree then tries to
--- recover in its `buffer_enter_event`, but it hands the restore helper a state
--- table that has `window.position` set and `current_position` unset — so
--- `neo-tree.utils.force_new_split` falls through to a bare `:vsplit`, which
--- with the default `splitright = false` inserts the file window to the LEFT of
--- the tree and shoves the sidebar to the right.
---
--- The classic repro: filetree open on the left, click a buffer in a tabline
--- (NvChad's tabufline, bufferline, …) while focus is in the tree — and the
--- tree "reopens" on the other side.
---
--- Fix: when a foreign buffer lands in the sidebar, put it where it belongs --
--- an editor window -- and hand the sidebar its tree back. Both the hijack above
--- and an ordinary "open this file" end up doing the same right thing, because
--- they ARE the same thing at the API level: the only difference is what the
--- caller meant, and both meant "show this file", never "show it in the
--- sidebar".
---
--- This replaces a `winfixbuf` pin, which refused the switch instead of
--- redirecting it. That was fine for callers who check the flag (NvChad's
--- `goto_buf`, neo-tree's own `open_file`) and route around it -- and an
--- `E1513: Cannot switch buffer` for every caller who does not, with the file
--- then not opening at all. A plugin opening a README from its own picker has
--- no reason to know a tree is focused, so "harmless error" was wrong: it broke
--- reposcope, lazygit and anything else driving `:edit` from a callback.
---
--- `winfixbuf = true` brings the old pin back for anyone who prefers a refusal
--- to a redirect; it is off by default and the two do not combine, since a
--- refused switch never reaches the redirect.
---
--- `winfixbuf` is lifted for the one case where neo-tree legitimately swaps the
--- buffer *in* the sidebar window: switching source via the `source_selector`
--- winbar (filesystem → buffers → git_status …), which reuses the window
--- through `nvim_win_set_buf`. neo-tree brackets that with its
--- `NEO_TREE_WINDOW_BEFORE_OPEN` / `_AFTER_OPEN` events, so this feature clears
--- the flag on BEFORE_OPEN (plus a short grace window for the BufWinEnter that
--- the swap fires) and re-sets it on AFTER_OPEN.
---
--- neo-tree only — it is the adapter that needs it and the one with the event
--- hooks. A no-op for nvim-tree/oil/netrw/mini.files, and on Neovim builds
--- without `&winfixbuf` (< 0.10).

local au = require("filetree.util.autocmd")
local ftbuf = require("filetree.util.buffer")

local M = {}

---Positions where the tree is a real split that can be hijacked. "float" has no
---hijack path and "current" is *meant* to share its window, so both are left
---unpinned.
local SPLIT_POSITIONS = { left = true, right = true, top = true, bottom = true }

---How long after a BEFORE_OPEN to keep the BufWinEnter re-assert quiet, so a
---source switch's own `nvim_win_set_buf` (which fires BufWinEnter between the
---two events) is not fought. AFTER_OPEN normally clears the grace earlier.
local LIFT_GRACE_MS = 1500

---@type integer?
local _augroup = nil
---@type integer  monotonic ms; the BufWinEnter re-assert is suppressed until then
local _lift_until = 0
---@type table[]  neo-tree event handlers, kept for teardown / idempotent re-setup
local _subs = {}
---Windows that currently hold, or last held, a tree sidebar -> the tree buffer
---they held. A hijack replaces the buffer, so "is this a tree window" cannot be
---answered from the window's *current* buffer once it has already happened.
---@type table<integer, integer>
local _sidebars = {}
---True while the redirect is rearranging windows, so the BufWinEnter it fires
---does not re-enter it.
local _redirecting = false
---Whether to pin with `winfixbuf` instead of redirecting (opt-in).
local _hard_pin = false

---@return integer
local function now_ms()
  return (vim.uv or vim.loop).now()
end

---Whether this Neovim build has `&winfixbuf` (0.10+).
---@return boolean
local function has_winfixbuf()
  return vim.fn.exists("&winfixbuf") == 1
end

---@param winid integer
---@param value boolean
local function set_fix(winid, value)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then return end
  pcall(function()
    vim.wo[winid].winfixbuf = value
  end)
end

---Every non-floating window currently showing a tree buffer.
---@return integer[]
local function tree_windows()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      if ftbuf.is_tree_buffer(vim.api.nvim_win_get_buf(w)) then out[#out + 1] = w end
    end
  end
  return out
end

---Whether a tree window is a real, hijackable side dock — not a `position =
---"current"` tree (meant to share its window) or a stray float. neo-tree
---stamps `b:neo_tree_position` on the tree buffer for every position.
---@param winid integer
---@return boolean
local function is_pinnable(winid)
  local ok, pos = pcall(function()
    return vim.b[vim.api.nvim_win_get_buf(winid)].neo_tree_position
  end)
  if ok and (pos == "current" or pos == "float") then return false end
  return true
end

---Record every open tree sidebar, and pin it when the hard pin is on.
---
---The record is what makes the redirect possible at all: once a foreign buffer
---has replaced the tree's, the window no longer looks like a tree window, so
---the only way to recognise it is to have seen it earlier.
local function pin_open_trees()
  if now_ms() < _lift_until then return end
  for _, w in ipairs(tree_windows()) do
    if is_pinnable(w) then
      _sidebars[w] = vim.api.nvim_win_get_buf(w)
      if _hard_pin then set_fix(w, true) end
    end
  end
  for w in pairs(_sidebars) do
    if not vim.api.nvim_win_is_valid(w) then _sidebars[w] = nil end
  end
end

---@internal
---Send `bufnr` to an editor window and give the sidebar its tree back.
---
---Ordering matters: the tree goes back FIRST, so neo-tree's own
---`buffer_enter_event` recovery -- the one that reparents the sidebar to the
---wrong side, which is the bug this whole feature exists for -- finds nothing
---to recover by the time it looks.
---@param win integer     The sidebar window the buffer landed in.
---@param tree_buf integer
---@param bufnr integer   The intruding buffer.
local function redirect(win, tree_buf, bufnr)
  _redirecting = true
  local ok = pcall(function()
    if vim.api.nvim_buf_is_valid(tree_buf) then vim.api.nvim_win_set_buf(win, tree_buf) end

    local target = ftbuf.find_editor_win(win)
    if not target then
      -- No editor window at all (tree opened alone): make one on the side the
      -- tree is not on, rather than splitting the sidebar.
      local ok_w, window = pcall(require, "filetree.util.window")
      if ok_w and type(window.open_editor_window) == "function" then
        local ok_open, made = pcall(window.open_editor_window, nil, {})
        if ok_open and made then target = made end
      end
    end
    if not target or not vim.api.nvim_win_is_valid(target) then return end

    vim.api.nvim_win_set_buf(target, bufnr)
    vim.api.nvim_set_current_win(target)
  end)
  _redirecting = false
  return ok
end

---@param config FiletreeSidebarGuardConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  if not adapter or adapter.name ~= "neotree" then return end

  -- The hard pin needs &winfixbuf (0.10+); the redirect does not, so the
  -- feature is useful on older builds too now.
  _hard_pin = config.winfixbuf == true and has_winfixbuf()

  M.teardown()

  _augroup = au.group("filetree_sidebar_guard", true)

  -- Pin the sidebar whenever a tree buffer lands in a window: the first open, a
  -- re-open, and (harmlessly, after the fact) a source switch. Gated on the
  -- event buffer actually being a tree buffer so this stays quiet on ordinary
  -- editing; scheduled so it runs once the window/buffer have settled.
  au.acmd("BufWinEnter", {
    group = _augroup,
    desc = "[filetree] Keep the tree in its sidebar; send foreign buffers to an editor window",
    callback = function(ev)
      if ftbuf.is_tree_buffer(ev.buf) then
        vim.schedule(pin_open_trees)
        return
      end
      if _redirecting or _hard_pin or now_ms() < _lift_until then return end

      -- A non-tree buffer in a window we know as a sidebar: the hijack. Handled
      -- inline rather than scheduled -- a deferred fix lets neo-tree's own
      -- recovery run first, which is what reparents the sidebar.
      local win = vim.api.nvim_get_current_win()
      local tree_buf = _sidebars[win]
      if not tree_buf then return end
      if vim.api.nvim_win_get_buf(win) ~= ev.buf then return end
      redirect(win, tree_buf, ev.buf)
    end,
  })

  -- …and once now, for a tree already open when setup() ran (event="VeryLazy"
  -- fires after neo-tree's own config).
  vim.schedule(pin_open_trees)

  -- The lift. neo-tree may not be loaded yet at setup() time (cmd-lazy), so
  -- retry the subscription a few times, mirroring handle_guard's deferred
  -- install. The autocmd above already covers the first real open regardless.
  local function install_event_hooks()
    local ok, events = pcall(require, "neo-tree.events")
    if not ok then return false end

    local before = {
      event = events.NEO_TREE_WINDOW_BEFORE_OPEN,
      id = "filetree_sidebar_guard_before",
      handler = function()
        -- A source switch (filesystem -> buffers -> git_status) legitimately
        -- swaps the buffer IN the sidebar window, so both strategies stand
        -- down for it: the pin is lifted, and the grace window keeps the
        -- redirect from treating the new source's buffer as an intruder.
        _lift_until = now_ms() + LIFT_GRACE_MS
        for _, w in ipairs(tree_windows()) do
          set_fix(w, false)
        end
      end,
    }
    local after = {
      event = events.NEO_TREE_WINDOW_AFTER_OPEN,
      id = "filetree_sidebar_guard_after",
      handler = function(args)
        _lift_until = 0
        if type(args) ~= "table" then return pin_open_trees() end
        -- Only guard a real, hijackable split; leave float/current alone.
        if args.position and not SPLIT_POSITIONS[args.position] then return end
        if args.winid and vim.api.nvim_win_is_valid(args.winid) then
          _sidebars[args.winid] = vim.api.nvim_win_get_buf(args.winid)
          if _hard_pin then set_fix(args.winid, true) end
        else
          pin_open_trees()
        end
      end,
    }
    pcall(events.unsubscribe, before)
    pcall(events.unsubscribe, after)
    pcall(events.subscribe, before)
    pcall(events.subscribe, after)
    _subs = { before, after }
    return true
  end

  if not install_event_hooks() then
    local tries = 0
    local function retry()
      tries = tries + 1
      if install_event_hooks() or tries >= 20 then return end
      vim.defer_fn(retry, 150)
    end
    vim.defer_fn(retry, 150)
  end
end

function M.teardown()
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
  local ok, events = pcall(require, "neo-tree.events")
  if ok then
    for _, s in ipairs(_subs) do
      pcall(events.unsubscribe, s)
    end
  end
  _subs = {}
  _lift_until = 0
  _redirecting = false
  _sidebars = {}
  for _, w in ipairs(tree_windows()) do
    set_fix(w, false)
  end
end

return M
