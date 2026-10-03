---@diagnostic disable: need-check-nil, missing-fields, duplicate-set-field
-- marks_auto_clear.lua — headless tests for `marks.auto_clear_ms`, the idle
-- timeout that clears every mark after a while without mark activity
-- (`filetree.features.org.marks`).
--
-- Two halves, because they pin different things:
--
--   1. Wiring, deterministic: `lib.nvim.debounce` is replaced by a recording
--      double, so "does this keymap re-arm the countdown?" is a counter, not
--      a race. Covers touch() on every mark-facing handler, the read-only
--      checks that must NOT touch, clear_all/teardown cancelling, the
--      re-setup guard, and what the fired callback does.
--   2. Timing, real timer: the real `lib.nvim.debounce` with a short
--      `auto_clear_ms`, so the whole path (touch -> libuv timer -> clear ->
--      notify) is exercised once end to end. Assertions compare timestamps
--      taken by the test instead of fixed sleeps, so a slow machine only
--      makes the run longer, not flaky.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/marks_auto_clear.lua
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

local uv = vim.uv or vim.loop

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
local function eq(name, got, want)
  check(name, got == want, ("got %q want %q"):format(tostring(got), tostring(want)))
end

local function now_ms()
  return uv.hrtime() / 1e6
end

-- ── shared doubles ────────────────────────────────────────────────────────────

-- Every notification the marks module emits, as { msg, level }.
local notes = {}
vim.notify = function(msg, level)
  notes[#notes + 1] = { msg = tostring(msg), level = level }
end
local function auto_clear_notes()
  local n = 0
  for _, e in ipairs(notes) do
    if e.msg:find("auto-cleared", 1, true) then n = n + 1 end
  end
  return n
end

-- `ui.kit` is only used by `show()` for the floating summary.
local viewer_calls = 0
package.loaded["ui.kit"] = {
  viewer = function()
    viewer_calls = viewer_calls + 1
  end,
}

-- A tree buffer with four rows, so mark_visual / goto have real lines.
local TREE_BUF = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(TREE_BUF, 0, -1, false, { "a.lua", "b.lua", "c.lua", "d.lua" })
vim.api.nvim_set_current_buf(TREE_BUF)

local NODES = {}
for i, name in ipairs({ "a.lua", "b.lua", "c.lua", "d.lua" }) do
  NODES[i] = { path = "/proj/" .. name, line_number = i }
end

local cursor_idx = 1
local adapter = {
  name = "stub",
  is_open = function()
    return true, TREE_BUF
  end,
  get_visible_nodes = function()
    return NODES
  end,
  get_current_node = function()
    return NODES[cursor_idx]
  end,
}

---Load a pristine marks module. `debounce` (optional) replaces
---`lib.nvim.debounce` for the module's lifetime; `bind` (optional) replaces
---`filetree.util.bind` so the keymap specs can be driven directly.
local function fresh_marks(debounce, bind)
  package.loaded["filetree.features.org.marks"] = nil
  package.loaded["lib.nvim.debounce"] = debounce
  package.loaded["filetree.util.bind"] = bind
  return require("filetree.features.org.marks")
end

-- ── 1. wiring: recording debounce double ─────────────────────────────────────

---@class TestHandle
---@field calls integer
---@field cancels integer
---@field ms integer
---@field fn function

local handles = {} ---@type TestHandle[]
local fake_debounce = {
  new = function(fn, ms)
    local h = { calls = 0, cancels = 0, ms = ms, fn = fn }
    handles[#handles + 1] = h
    return {
      call = function()
        h.calls = h.calls + 1
      end,
      cancel = function()
        h.cancels = h.cancels + 1
      end,
    }
  end,
}

-- Captured keymap specs, by action name.
local bound ---@type table<string, table>
local fake_bind = {
  bind = function(_, _, specs)
    bound = {}
    for _, s in ipairs(specs) do
      bound[s.name] = s
    end
  end,
}

---Run `fn` and return how often the (single) live handle was re-armed by it.
local function touches(h, fn)
  local before = h.calls
  fn()
  return h.calls - before
end

do
  print("\n-- wiring: touch() on the right entry points --")
  handles = {}
  local M = fresh_marks(fake_debounce, fake_bind)

  M.setup({ enabled = true, auto_clear_ms = 5000 }, adapter)
  eq("one debounce handle is built for auto_clear_ms > 0", #handles, 1)
  local h = handles[1]
  eq("...with the configured delay", h.ms, 5000)
  eq("setup itself does not arm the countdown", h.calls, 0)

  eq(
    "toggle re-arms",
    touches(h, function()
      M.toggle("/proj/a.lua")
    end),
    1
  )
  eq("toggle marked the path", M.is_marked("/proj/a.lua"), true)
  eq(
    "toggle (unmark) re-arms too",
    touches(h, function()
      M.toggle("/proj/a.lua")
    end),
    1
  )
  eq(
    "mark_all_visible re-arms",
    touches(h, function()
      M.mark_all_visible()
    end),
    1
  )
  eq("...and marked all four", M.count(), 4)
  eq(
    "unmark_all_visible re-arms",
    touches(h, function()
      M.unmark_all_visible()
    end),
    1
  )
  eq("...and cleared all four", M.count(), 0)

  M.toggle("/proj/b.lua")
  M.toggle("/proj/c.lua")

  -- The internal "is anything marked?" checks run for every trash / move /
  -- copy_move / path_copy call whether or not anything is marked; if they
  -- re-armed the timer it would never expire.
  eq(
    "is_marked does not re-arm",
    touches(h, function()
      M.is_marked("/proj/b.lua")
    end),
    0
  )
  eq(
    "get_marked does not re-arm",
    touches(h, function()
      M.get_marked()
    end),
    0
  )
  eq(
    "count does not re-arm",
    touches(h, function()
      M.count()
    end),
    0
  )

  eq(
    "show (with marks) re-arms",
    touches(h, function()
      M.show()
    end),
    1
  )
  eq("...and opened the viewer", viewer_calls, 1)
  eq(
    "goto_mark re-arms",
    touches(h, function()
      M.goto_mark(1)
    end),
    1
  )
  eq(
    "goto_adjacent_mark (next) re-arms",
    touches(h, function()
      M.goto_adjacent_mark(1)
    end),
    1
  )
  eq(
    "goto_adjacent_mark (prev) re-arms",
    touches(h, function()
      M.goto_adjacent_mark(-1)
    end),
    1
  )

  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  M.clear_all()
  eq(
    "mark_visual re-arms",
    touches(h, function()
      M.mark_visual(false)
    end),
    1
  )
  eq("...and marked the selected node", M.is_marked("/proj/b.lua"), true)
  eq("...and only it", M.count(), 1)
  eq(
    "mark_visual (unmark) re-arms",
    touches(h, function()
      M.mark_visual(true)
    end),
    1
  )
  eq("...and unmarked the selected node (regression: it used to mark)", M.count(), 0)

  -- No marks: nothing to keep alive, so nothing re-arms.
  M.toggle("/proj/a.lua")
  h.cancels = 0
  eq(
    "clear_all does not re-arm",
    touches(h, function()
      M.clear_all()
    end),
    0
  )
  eq("...but cancels the countdown, once", h.cancels, 1)
  eq("...and empties the set", M.count(), 0)
  local calls_before = h.calls
  M.show()
  M.goto_mark(1)
  M.goto_adjacent_mark(1)
  eq("show / goto with nothing marked do not re-arm", h.calls - calls_before, 0)

  print("\n-- wiring: every keymap handler goes through touch() --")
  bound = {}
  M.teardown()
  handles = {}
  M.setup({ enabled = true, auto_clear_ms = 5000 }, adapter)
  h = handles[1]
  local names = {}
  for k in pairs(bound) do
    names[#names + 1] = k
  end
  table.sort(names)
  eq(
    "the bound actions",
    table.concat(names, ","),
    "clear,goto,mark_all,next,prev,show,toggle,unmark_all"
  )

  M.toggle("/proj/a.lua") -- something for the navigation actions to land on
  h.calls = 0

  local function run_bind(spec, mode)
    local fn
    if spec.binds then
      for _, b in ipairs(spec.binds) do
        if b.mode == mode then fn = b.rhs end
      end
    else
      fn = spec.rhs
    end
    assert(fn, "no rhs for " .. spec.name .. "/" .. tostring(mode))
    return touches(h, fn)
  end

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  eq("toggle <n>", run_bind(bound.toggle, "n"), 1)
  eq("toggle <x>", run_bind(bound.toggle, "x"), 1)
  eq("mark_all", run_bind(bound.mark_all, "n"), 1)
  eq("unmark_all <n>", run_bind(bound.unmark_all, "n"), 1)
  eq("unmark_all <x>", run_bind(bound.unmark_all, "x"), 1)
  M.toggle("/proj/a.lua") -- the actions above may have left nothing marked
  h.calls = 0
  eq("show", run_bind(bound.show, "n"), 1)
  eq("goto", run_bind(bound["goto"], "n"), 1)
  eq("next", run_bind(bound.next, "n"), 1)
  eq("prev", run_bind(bound.prev, "n"), 1)
  h.cancels = 0
  run_bind(bound.clear, "n")
  eq("clear cancels", h.cancels, 1)

  M.teardown()
end

do
  print("\n-- wiring: the fired callback --")
  handles = {}
  notes = {}
  local M = fresh_marks(fake_debounce, fake_bind)
  M.setup({ enabled = true, auto_clear_ms = 90000 }, adapter)
  local h = handles[1]

  M.toggle("/proj/a.lua")
  M.toggle("/proj/b.lua")
  h.fn()
  eq("firing clears every mark", M.count(), 0)
  eq("...with exactly one notification", auto_clear_notes(), 1)
  check(
    "...that names the idle time",
    notes[#notes] and notes[#notes].msg:find("after 90s idle", 1, true) ~= nil,
    notes[#notes] and notes[#notes].msg
  )
  eq("...at info level", notes[#notes] and notes[#notes].level, vim.log.levels.INFO)

  notes = {}
  h.fn()
  eq("firing on an already-empty set stays silent", auto_clear_notes(), 0)
  M.teardown()
end

do
  print("\n-- wiring: disabled / re-setup / teardown --")
  handles = {}
  local M = fresh_marks(fake_debounce, fake_bind)

  M.setup({ enabled = true, auto_clear_ms = 0 }, adapter)
  eq("auto_clear_ms = 0 builds no handle", #handles, 0)
  M.toggle("/proj/a.lua")
  eq("...and marking still works without one", M.count(), 1)
  M.teardown()

  handles = {}
  M = fresh_marks(fake_debounce, fake_bind)
  M.setup({ enabled = true, auto_clear_ms = 4000 }, adapter)
  eq("default-config module builds its handle", #handles, 1)
  M.setup({ enabled = true, auto_clear_ms = 7000 }, adapter)
  eq("a second setup() builds a second handle", #handles, 2)
  eq("...cancelling the first one (no orphaned timer)", handles[1].cancels, 1)
  eq("...with the new delay", handles[2].ms, 7000)
  eq("...and the second is not cancelled", handles[2].cancels, 0)
  M.toggle("/proj/a.lua")
  eq("later activity arms the new handle", handles[2].calls, 1)
  eq("...and not the old one", handles[1].calls, 0)
  M.teardown()
  eq("teardown cancels the live handle", handles[2].cancels, 1)
  eq("teardown empties the set", M.count(), 0)
  M.toggle("/proj/a.lua")
  eq("after teardown, activity arms nothing", handles[2].calls, 1)
  M.teardown()
  eq("a second teardown is harmless", handles[2].cancels, 1)

  handles = {}
  M = fresh_marks(fake_debounce, fake_bind)
  M.setup({ enabled = false, auto_clear_ms = 100 }, adapter)
  eq("a disabled feature builds no handle", #handles, 0)
end

-- ── 2. timing: the real lib.nvim.debounce ────────────────────────────────────

do
  print("\n-- timing: real timer --")
  local MS = 300

  local function real_marks()
    local M = fresh_marks(nil, fake_bind)
    -- libuv schedules a timer relative to its cached loop time, which is only
    -- refreshed once per loop iteration; after the long synchronous stretch
    -- above that cache is stale and a fresh timer would fire early. Not
    -- something that happens in a live session, where the loop keeps turning.
    uv.update_time()
    return M
  end
  ---Wait until `cond()` holds (polling the main loop), at most `limit` ms.
  local function wait_for(limit, cond)
    return vim.wait(limit, cond, 10)
  end

  -- Idle: the marks go, once, and the polling itself (count() on every tick)
  -- must not postpone it.
  do
    notes = {}
    local M = real_marks()
    M.setup({ enabled = true, auto_clear_ms = MS }, adapter)
    local t0 = now_ms()
    M.toggle("/proj/a.lua")
    M.toggle("/proj/b.lua")
    local cleared = wait_for(MS * 10, function()
      return M.count() == 0
    end)
    local elapsed = now_ms() - t0
    check("idle marks are cleared", cleared)
    check(
      "...not before the delay has passed",
      elapsed >= MS * 0.9,
      ("cleared after %.0fms of %dms"):format(elapsed, MS)
    )
    check(
      "...and despite count() being polled throughout (read-only checks don't re-arm)",
      elapsed < MS * 5,
      ("took %.0fms"):format(elapsed)
    )
    eq("one notification", auto_clear_notes(), 1)
    vim.wait(MS * 2)
    eq("...and it does not fire again", auto_clear_notes(), 1)
    M.teardown()
  end

  -- Activity: a second toggle part-way through pushes the clear a full delay
  -- past *that* toggle, not past the first one.
  do
    notes = {}
    local M = real_marks()
    M.setup({ enabled = true, auto_clear_ms = MS }, adapter)
    M.toggle("/proj/a.lua")
    vim.wait(math.floor(MS * 0.6))
    local t_touch = now_ms()
    M.toggle("/proj/b.lua")
    local cleared = wait_for(MS * 10, function()
      return M.count() == 0
    end)
    local since_touch = now_ms() - t_touch
    check("re-armed marks are still cleared eventually", cleared)
    check(
      "a toggle part-way through restarts the full delay",
      since_touch >= MS * 0.85,
      ("cleared %.0fms after the last toggle, delay %dms"):format(since_touch, MS)
    )
    eq("...with a single notification", auto_clear_notes(), 1)
    M.teardown()
  end

  -- clear_all: nothing left to expire, so nothing is announced later.
  do
    notes = {}
    local M = real_marks()
    M.setup({ enabled = true, auto_clear_ms = MS }, adapter)
    M.toggle("/proj/a.lua")
    M.clear_all()
    vim.wait(MS * 2)
    eq("a manual clear leaves no countdown behind", auto_clear_notes(), 0)
    M.toggle("/proj/a.lua")
    check(
      "...and later marks are still counted",
      wait_for(MS * 10, function()
        return M.count() == 0
      end)
    )
    eq("...and still expire", auto_clear_notes(), 1)
    M.teardown()
  end

  -- Re-setup without teardown: the first handle's timer is cancelled, not
  -- orphaned (an orphan would fire later against the live mark set).
  do
    notes = {}
    local M = real_marks()
    M.setup({ enabled = true, auto_clear_ms = MS }, adapter)
    M.toggle("/proj/a.lua") -- arms handle #1
    M.setup({ enabled = true, auto_clear_ms = MS }, adapter) -- replaces it
    vim.wait(MS * 2)
    eq("a replaced handle's pending timer never fires", auto_clear_notes(), 0)
    eq("...so the mark survives", M.count(), 1)
    M.toggle("/proj/b.lua") -- arms handle #2
    check(
      "the new handle works",
      wait_for(MS * 10, function()
        return M.count() == 0
      end)
    )
    eq("...and fires exactly once", auto_clear_notes(), 1)
    M.teardown()
  end

  -- Teardown: a pending countdown dies with the feature.
  do
    notes = {}
    local M = real_marks()
    M.setup({ enabled = true, auto_clear_ms = MS }, adapter)
    M.toggle("/proj/a.lua")
    M.teardown()
    vim.wait(MS * 2)
    eq("teardown stops a pending countdown", auto_clear_notes(), 0)
  end

  -- Opt-out: 0 keeps marks forever (the old behaviour).
  do
    notes = {}
    local M = real_marks()
    M.setup({ enabled = true, auto_clear_ms = 0 }, adapter)
    M.toggle("/proj/a.lua")
    vim.wait(MS)
    eq("auto_clear_ms = 0 never clears", M.count(), 1)
    eq("...and never notifies", auto_clear_notes(), 0)
    M.teardown()
  end
end

package.loaded["filetree.util.bind"] = nil
package.loaded["lib.nvim.debounce"] = nil
package.loaded["filetree.features.org.marks"] = nil

print(("\nfiletree.nvim marks_auto_clear: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
