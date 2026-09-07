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
  captured["neo_tree_window_before_open"].handler()
  check(
    "BEFORE_OPEN lifts winfixbuf so neo-tree can reuse the window",
    vim.wo[tree_win].winfixbuf == false
  )

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
