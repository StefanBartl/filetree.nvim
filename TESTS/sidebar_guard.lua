---@diagnostic disable: missing-fields
-- Test doubles here implement only what the unit under test calls — a full
-- FiletreeAdapter would be noise, not coverage.
-- sidebar_guard.lua — headless tests for the nav/sidebar_guard feature.
--
-- The feature pins the tree window with `winfixbuf` (neo-tree + Neovim 0.10+)
-- so a stray `:buffer` / tabline mouse-click cannot swap the tree's buffer out
-- of its window and make neo-tree reopen the sidebar on the wrong side.
--
-- No real neo-tree is involved: a window carrying a `neo-tree` filetype buffer
-- plus a stub adapter (`name = "neotree"`, `filetypes = { "neo-tree" }`) is the
-- exact seam the feature reads through (`filetree.util.buffer.is_tree_buffer`).
-- neo-tree's event module is stubbed via `package.loaded` so the source-switch
-- lift can be exercised too.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/sidebar_guard.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)

for _, env in ipairs({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" and vim.fn.isdirectory(v .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(v)
    break
  end
end
for _, c in ipairs({
  vim.fn.fnamemodify(root_dir, ":h") .. "/lib.nvim",
  vim.fn.stdpath("data") .. "/lazy/lib.nvim",
}) do
  if vim.fn.isdirectory(c .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(c)
    break
  end
end

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. (detail and ("  — " .. detail) or ""))
  end
end

-- ── winfixbuf availability ───────────────────────────────────────────────────
if vim.fn.exists("&winfixbuf") ~= 1 then
  print("SKIP: this Neovim build has no &winfixbuf (< 0.10)")
  vim.cmd("qa!")
end

-- ── Stub neo-tree events, captured for the lift test ─────────────────────────
local captured = {}
package.loaded["neo-tree.events"] = {
  NEO_TREE_WINDOW_BEFORE_OPEN = "neo_tree_window_before_open",
  NEO_TREE_WINDOW_AFTER_OPEN = "neo_tree_window_after_open",
  subscribe = function(h)
    captured[h.event] = h
  end,
  unsubscribe = function(h)
    if captured[h.event] == h or (captured[h.event] and captured[h.event].id == h.id) then
      captured[h.event] = nil
    end
  end,
}

-- ── Stub adapter that names itself neotree ───────────────────────────────────
local adapter = { name = "neotree", filetypes = { "neo-tree" } }

-- filetree.util.buffer.is_tree_buffer asks require("filetree").adapter(); make
-- that resolve to our stub.
package.loaded["filetree"] = package.loaded["filetree"] or {}
package.loaded["filetree"].adapter = function()
  return adapter
end

local guard = require("filetree.features.nav.sidebar_guard")

-- ── A fake tree window + a normal editor window ──────────────────────────────
vim.cmd("enew")
local editor_win = vim.api.nvim_get_current_win()
vim.cmd("vsplit")
local tree_win = vim.api.nvim_get_current_win()
local tree_buf = vim.api.nvim_create_buf(false, true)
vim.bo[tree_buf].filetype = "neo-tree"
vim.api.nvim_win_set_buf(tree_win, tree_buf)
-- back to the editor window, as the user would be after opening the sidebar
vim.api.nvim_set_current_win(editor_win)

-- ── setup pins the already-open sidebar ─────────────────────────────────────
guard.setup({ enabled = true, winfixbuf = true }, adapter)
vim.wait(50, function()
  return false
end)

check("setup pins the open tree window (winfixbuf = true)", vim.wo[tree_win].winfixbuf == true)
check(
  "the editor window is left untouched (winfixbuf = false)",
  vim.wo[editor_win].winfixbuf == false
)
check("BEFORE_OPEN handler was subscribed", captured["neo_tree_window_before_open"] ~= nil)
check("AFTER_OPEN handler was subscribed", captured["neo_tree_window_after_open"] ~= nil)

-- ── a stray :buffer in the tree window is refused ───────────────────────────
do
  vim.api.nvim_set_current_win(tree_win)
  local file_buf = vim.api.nvim_create_buf(true, false)
  local ok = pcall(vim.api.nvim_set_current_buf, file_buf)
  check("a stray nvim_set_current_buf in the pinned tree window is blocked", ok == false)
  check(
    "the tree buffer is still in the tree window",
    vim.api.nvim_win_get_buf(tree_win) == tree_buf
  )
  vim.api.nvim_set_current_win(editor_win)
end

-- ── the source-switch lift: BEFORE clears, AFTER re-sets ────────────────────
do
  -- BEFORE_OPEN carries no window info, so it infers the window undergoing
  -- the switch from whatever is focused right now -- exactly like a real
  -- winbar click, which necessarily focuses the sidebar first.
  vim.api.nvim_set_current_win(tree_win)
  captured["neo_tree_window_before_open"].handler()
  check(
    "BEFORE_OPEN lifts winfixbuf so neo-tree can reuse the window",
    vim.wo[tree_win].winfixbuf == false
  )
  vim.api.nvim_set_current_win(editor_win)

  -- during the lift a BufWinEnter must NOT re-pin
  vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = tree_buf })
  vim.wait(50, function()
    return false
  end)
  check(
    "a BufWinEnter during the lift does not re-pin (source switch not fought)",
    vim.wo[tree_win].winfixbuf == false
  )

  captured["neo_tree_window_after_open"].handler({ position = "left", winid = tree_win })
  check("AFTER_OPEN re-pins the tree window", vim.wo[tree_win].winfixbuf == true)
end

-- ── AFTER_OPEN leaves a float/current tree alone ────────────────────────────
do
  vim.wo[tree_win].winfixbuf = false
  captured["neo_tree_window_after_open"].handler({ position = "float", winid = tree_win })
  check("AFTER_OPEN does not pin a float-position tree", vim.wo[tree_win].winfixbuf == false)
end

-- ── a `position = "current"` tree is never pinned (it shares its window) ─────
do
  vim.wo[tree_win].winfixbuf = false
  vim.b[tree_buf].neo_tree_position = "current"
  vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = tree_buf })
  vim.wait(50, function()
    return false
  end)
  check("a current-position tree window is not pinned", vim.wo[tree_win].winfixbuf == false)
  vim.b[tree_buf].neo_tree_position = "left"
end

-- ── teardown unpins and unsubscribes ───────────────────────────────────────
do
  vim.wo[tree_win].winfixbuf = true
  guard.teardown()
  check("teardown unpins the tree window", vim.wo[tree_win].winfixbuf == false)
  check(
    "teardown unsubscribes the neo-tree event handlers",
    captured["neo_tree_window_before_open"] == nil and captured["neo_tree_window_after_open"] == nil
  )
end

-- ── The default strategy: redirect, not refuse ──────────────────────────────
-- `winfixbuf` (the block above) makes a foreign buffer switch FAIL. That is
-- fine for callers who check the flag and route around it, and an
-- `E1513: Cannot switch buffer` for callers who do not -- with the file then
-- not opening at all. Reposcope opening a README from its own picker, lazygit,
-- anything driving `:edit` from a callback: none of them know a tree is
-- focused, and none of them should have to.
--
-- The default therefore lets the switch happen and puts things right: the
-- intruder goes to an editor window, the tree goes back to its sidebar. Both
-- the hijack and an ordinary "open this file" want exactly that.
do
  guard.teardown()

  -- A tab of its own: the blocks after this one still use the windows created
  -- at the top of the file, so this must not close them.
  vim.cmd("tabnew")
  local rd_editor = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local rd_tree = vim.api.nvim_get_current_win()
  local rd_tree_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[rd_tree_buf].filetype = "neo-tree"
  vim.api.nvim_win_set_buf(rd_tree, rd_tree_buf)
  vim.api.nvim_set_current_win(rd_editor)

  -- No `winfixbuf` key at all: the default.
  guard.setup({ enabled = true }, adapter)
  vim.wait(50, function()
    return false
  end)

  check("default: the tree window is NOT hard-pinned", vim.wo[rd_tree].winfixbuf == false)

  -- The intruder, put in the tree window exactly as `:edit`/`:buffer` would.
  local file_buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(file_buf, "redirect-me.lua")
  vim.api.nvim_set_current_win(rd_tree)
  local ok_switch = pcall(vim.api.nvim_set_current_buf, file_buf)
  vim.wait(100, function()
    return false
  end)

  check("default: the switch is allowed, not refused", ok_switch)
  check(
    "default: the tree is back in its own window",
    vim.api.nvim_win_is_valid(rd_tree) and vim.api.nvim_win_get_buf(rd_tree) == rd_tree_buf,
    "sidebar holds buf " .. tostring(vim.api.nvim_win_get_buf(rd_tree))
  )
  check(
    "default: the intruder landed in the editor window",
    vim.api.nvim_win_is_valid(rd_editor) and vim.api.nvim_win_get_buf(rd_editor) == file_buf,
    "editor holds buf " .. tostring(vim.api.nvim_win_get_buf(rd_editor))
  )
  check(
    "default: focus followed the file out of the sidebar",
    vim.api.nvim_get_current_win() == rd_editor
  )

  -- A source switch swaps the buffer IN the sidebar on purpose, so the
  -- redirect has to stand down for it -- otherwise `filesystem -> git_status`
  -- would get thrown into an editor window. BEFORE_OPEN carries no window
  -- info and infers it from whatever is currently focused, so -- matching a
  -- real winbar click -- focus is put on `rd_tree` first (it was left on
  -- `rd_editor` by the redirect check just above).
  vim.api.nvim_set_current_win(rd_tree)
  captured["neo_tree_window_before_open"].handler()
  local other_source = vim.api.nvim_create_buf(false, true)
  vim.bo[other_source].filetype = "neo-tree"
  vim.api.nvim_win_set_buf(rd_tree, other_source)
  vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = other_source })
  vim.wait(100, function()
    return false
  end)
  check(
    "default: a source switch is left alone during the lift",
    vim.api.nvim_win_get_buf(rd_tree) == other_source,
    "sidebar holds buf " .. tostring(vim.api.nvim_win_get_buf(rd_tree))
  )

  guard.teardown()
  vim.cmd("tabclose")
end

-- ── The tree is the only window ────────────────────────────────────────────
-- There is nothing to redirect *into*, so the redirect has to make a window.
-- Getting the order wrong here loses the file outright: restore the sidebar
-- first, then fail to find or make a target, and the buffer is loaded and
-- displayed nowhere -- an `:edit` that looks like it worked and shows the
-- user their tree. The target is therefore acquired before anything moves.
do
  guard.teardown()

  vim.cmd("tabnew")
  local lone_tree = vim.api.nvim_get_current_win()
  local lone_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[lone_buf].filetype = "neo-tree"
  vim.api.nvim_win_set_buf(lone_tree, lone_buf)
  vim.cmd("only")

  guard.setup({ enabled = true }, adapter)
  vim.wait(50, function()
    return false
  end)
  local alone_tab = vim.api.nvim_get_current_tabpage()
  check(
    "alone: the lone tree window is the only one in this tab",
    #vim.api.nvim_tabpage_list_wins(0) == 1
  )

  local file_buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(file_buf, "alone-redirect.lua")
  vim.api.nvim_set_current_win(lone_tree)
  local ok_switch = pcall(vim.api.nvim_set_current_buf, file_buf)
  vim.wait(100, function()
    return false
  end)

  check("alone: the switch is allowed", ok_switch)
  check(
    "alone: a window was made for the file",
    #vim.api.nvim_tabpage_list_wins(0) == 2,
    "windows: " .. #vim.api.nvim_tabpage_list_wins(0)
  )
  check(
    "alone: the tree kept its window",
    vim.api.nvim_win_is_valid(lone_tree) and vim.api.nvim_win_get_buf(lone_tree) == lone_buf
  )

  local shown = false
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(w) == file_buf then shown = true end
  end
  check("alone: the file is visible somewhere — not loaded into nowhere", shown)
  -- Editor windows exist in OTHER tabs here. Picking one of those would open
  -- the file out of sight and drag the cursor into another tab; a sidebar is a
  -- per-tab thing and so is where its files belong.
  check(
    "alone: the redirect stayed in this tabpage",
    vim.api.nvim_get_current_tabpage() == alone_tab
  )

  guard.teardown()
  vim.cmd("tabclose")
end

-- ── No editor window can be found OR made: the tree still goes back ────────
-- The "alone" block above covers the case where no editor window exists but
-- one CAN be made. This is the narrower, worse case: none exists and none can
-- be made either (window.util.open_editor_window itself fails -- e.g. a
-- terminal too small to split either way). An earlier version of redirect()
-- bailed out entirely in this branch, leaving the intruding buffer sitting in
-- the tree window while `_sidebars` still tracked it as a sidebar -- so
-- `adapter.is_open()`/`get_bufnr()` (which trust whatever buffer currently
-- occupies the tracked window, with no is-it-really-a-tree check) would keep
-- reporting the tree as open, and any decoration feature refreshing on its
-- own schedule would write tree-node extmarks into what is actually the
-- user's real, unrelated file. The tree buffer must go back to the sidebar
-- window regardless of whether a target could be found.
do
  guard.teardown()

  vim.cmd("tabnew")
  local lone_tree2 = vim.api.nvim_get_current_win()
  local lone_buf2 = vim.api.nvim_create_buf(false, true)
  vim.bo[lone_buf2].filetype = "neo-tree"
  vim.api.nvim_win_set_buf(lone_tree2, lone_buf2)
  vim.cmd("only")

  guard.setup({ enabled = true }, adapter)
  vim.wait(50, function()
    return false
  end)

  -- Force the "nowhere to put it" branch deterministically, rather than
  -- relying on winminwidth/winminheight tricks that vary by machine: make
  -- open_editor_window itself report failure for the duration of this switch.
  local window_mod = require("filetree.util.window")
  local orig_open_editor_window = window_mod.open_editor_window
  ---@diagnostic disable-next-line: duplicate-set-field
  window_mod.open_editor_window = function()
    return nil
  end

  local file_buf2 = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(file_buf2, "nowhere-to-put-me.lua")
  vim.api.nvim_set_current_win(lone_tree2)
  local ok_switch2 = pcall(vim.api.nvim_set_current_buf, file_buf2)
  vim.wait(100, function()
    return false
  end)

  window_mod.open_editor_window = orig_open_editor_window

  check("no-target: the switch itself is still allowed", ok_switch2)
  check(
    "no-target: the tree window shows the tree buffer again, not the intruder",
    vim.api.nvim_win_is_valid(lone_tree2) and vim.api.nvim_win_get_buf(lone_tree2) == lone_buf2,
    "window holds buf " .. tostring(vim.api.nvim_win_get_buf(lone_tree2))
  )
  local visible_elsewhere = false
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == file_buf2 then visible_elsewhere = true end
  end
  check(
    "no-target: the intruder is not stuck displayed in the sidebar window",
    not visible_elsewhere
  )
  check(
    "no-target: the intruder buffer still exists (loaded, not lost)",
    vim.api.nvim_buf_is_valid(file_buf2)
  )

  guard.teardown()
  vim.cmd("tabclose")
end

-- ── A source switch in one tab must not disarm another tab's sidebar ───────
-- `_lift_until` used to be a single module-level scalar: a source switch in
-- ANY tab's sidebar (NEO_TREE_WINDOW_BEFORE_OPEN carries no window info)
-- lifted/unpinned every tree window across every tabpage, not just the one
-- being switched. Two tabs, each with its own tree + editor window: starting
-- a source switch in tab A's sidebar must leave tab B's hijack protection
-- fully armed.
do
  guard.teardown()

  vim.cmd("tabnew")
  local a_editor = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local a_tree = vim.api.nvim_get_current_win()
  local a_tree_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[a_tree_buf].filetype = "neo-tree"
  vim.api.nvim_win_set_buf(a_tree, a_tree_buf)

  vim.cmd("tabnew")
  local b_editor = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local b_tree = vim.api.nvim_get_current_win()
  local b_tree_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[b_tree_buf].filetype = "neo-tree"
  vim.api.nvim_win_set_buf(b_tree, b_tree_buf)

  guard.setup({ enabled = true }, adapter) -- default: redirect, not hard-pin
  vim.wait(50, function()
    return false
  end)

  -- Tab A's sidebar starts a source switch (focus there first, matching a
  -- real winbar click -- see the note on the block above).
  vim.api.nvim_set_current_win(a_tree)
  captured["neo_tree_window_before_open"].handler()

  -- An UNRELATED hijack in tab B, entirely independent of tab A's switch.
  local intruder = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(intruder, "cross-tab-hijack.lua")
  vim.api.nvim_set_current_win(b_tree)
  local ok_switch = pcall(vim.api.nvim_set_current_buf, intruder)
  vim.wait(100, function()
    return false
  end)

  check("cross-tab: tab B's switch is still allowed", ok_switch)
  check(
    "cross-tab: tab A's source switch did not suppress tab B's redirect",
    vim.api.nvim_win_is_valid(b_tree) and vim.api.nvim_win_get_buf(b_tree) == b_tree_buf,
    "tab B's sidebar holds buf " .. tostring(vim.api.nvim_win_get_buf(b_tree))
  )
  check(
    "cross-tab: the intruder landed in tab B's own editor window",
    vim.api.nvim_win_is_valid(b_editor) and vim.api.nvim_win_get_buf(b_editor) == intruder
  )
  check(
    "cross-tab: tab A's own windows were left alone by tab B's hijack",
    vim.api.nvim_win_is_valid(a_editor) and vim.api.nvim_win_get_buf(a_editor) ~= intruder
  )

  -- Finish tab A's switch and confirm it re-armed correctly for tab A too --
  -- the fix is about scoping the lift, not about disabling it.
  captured["neo_tree_window_after_open"].handler({ position = "left", winid = a_tree })

  guard.teardown()
  vim.cmd("tabclose")
  vim.cmd("tabclose")
end

-- ── Same cross-tab leak, hard-pin mode: AFTER_OPEN must not leave another ───
-- ── tab's window permanently unpinned ───────────────────────────────────────
-- With `winfixbuf = true`, BEFORE_OPEN unpins the switching tab's window and
-- AFTER_OPEN re-pins only `args.winid` -- the one window neo-tree names. If
-- BEFORE_OPEN had unpinned every tab's tree window (the same bug as above),
-- every OTHER tab's window would come out of this permanently unpinned, with
-- nothing to ever re-pin it again.
do
  guard.teardown()

  vim.cmd("tabnew")
  vim.cmd("vsplit")
  local hp_a_tree = vim.api.nvim_get_current_win()
  local hp_a_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[hp_a_buf].filetype = "neo-tree"
  vim.api.nvim_win_set_buf(hp_a_tree, hp_a_buf)

  vim.cmd("tabnew")
  vim.cmd("vsplit")
  local hp_b_tree = vim.api.nvim_get_current_win()
  local hp_b_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[hp_b_buf].filetype = "neo-tree"
  vim.api.nvim_win_set_buf(hp_b_tree, hp_b_buf)

  guard.setup({ enabled = true, winfixbuf = true }, adapter)
  vim.wait(50, function()
    return false
  end)
  check("hard-pin cross-tab: both tabs start pinned", vim.wo[hp_a_tree].winfixbuf == true)
  check(
    "hard-pin cross-tab: ...both of them",
    vim.wo[hp_b_tree].winfixbuf == true,
    tostring(vim.wo[hp_b_tree].winfixbuf)
  )

  vim.api.nvim_set_current_win(hp_a_tree)
  captured["neo_tree_window_before_open"].handler()
  check(
    "hard-pin cross-tab: tab B stays pinned while tab A's switch is in flight",
    vim.wo[hp_b_tree].winfixbuf == true,
    tostring(vim.wo[hp_b_tree].winfixbuf)
  )

  captured["neo_tree_window_after_open"].handler({ position = "left", winid = hp_a_tree })
  check(
    "hard-pin cross-tab: tab A re-pins after its own switch completes",
    vim.wo[hp_a_tree].winfixbuf == true
  )
  check(
    "hard-pin cross-tab: tab B was never touched, still pinned",
    vim.wo[hp_b_tree].winfixbuf == true,
    tostring(vim.wo[hp_b_tree].winfixbuf)
  )

  guard.teardown()
  vim.cmd("tabclose")
  vim.cmd("tabclose")
end

-- ── A record that no longer points at a tree must not fire the redirect ────
-- A closed tree leaves its window in `_sidebars`. Neovim does not reuse window
-- ids, so that entry cannot currently address a different window -- but the
-- redirect validates what the record points at anyway, rather than depending
-- on an undocumented property of the handle allocator.
do
  guard.teardown()

  vim.cmd("tabnew")
  local w_editor = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local w_tree = vim.api.nvim_get_current_win()
  local b_tree = vim.api.nvim_create_buf(false, true)
  vim.bo[b_tree].filetype = "neo-tree"
  vim.api.nvim_win_set_buf(w_tree, b_tree)
  vim.api.nvim_set_current_win(w_editor)

  guard.setup({ enabled = true }, adapter)
  vim.wait(50, function()
    return false
  end)

  -- The recorded buffer stops being a tree, with no window churn to confuse
  -- the issue: exactly the state the validation is there for.
  vim.bo[b_tree].filetype = "lua"

  local later = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(later, "not-a-hijack.lua")
  vim.api.nvim_set_current_win(w_tree)
  local ok_switch = pcall(vim.api.nvim_set_current_buf, later)
  vim.wait(100, function()
    return false
  end)

  check("stale: the switch is allowed", ok_switch)
  check(
    "stale: the buffer stays where it was put, no phantom redirect",
    vim.api.nvim_win_is_valid(w_tree) and vim.api.nvim_win_get_buf(w_tree) == later,
    "window holds buf " .. tostring(vim.api.nvim_win_get_buf(w_tree))
  )

  guard.teardown()
  vim.cmd("tabclose")
end

-- ── no-op for a non-neotree adapter ────────────────────────────────────────
do
  vim.wo[tree_win].winfixbuf = false
  guard.setup({ enabled = true }, { name = "nvimtree", filetypes = { "NvimTree" } })
  vim.wait(50, function()
    return false
  end)
  check(
    "no-op for a non-neotree adapter (tree window stays unpinned)",
    vim.wo[tree_win].winfixbuf == false
  )
  guard.teardown()
end

print(("\nsidebar_guard: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
