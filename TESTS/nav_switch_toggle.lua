-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- nav_switch_toggle.lua — headless tests for the two features that came out
-- of a host's neo-tree config: `source_switcher` (pick / cycle / display
-- names for neo-tree's sources) and `tree_toggle` (position-aware global
-- toggle keys), plus the neo-tree adapter's E95 self-heal in `toggle_at`.
--
-- neo-tree itself is stubbed at `neo-tree` / `neo-tree.command`, so what is
-- asserted is what the features hand neo-tree and how they react to what it
-- answers -- never neo-tree's own behaviour.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/nav_switch_toggle.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)
local lib_candidates = {}
for _, env in ipairs({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" then lib_candidates[#lib_candidates + 1] = v end
end
lib_candidates[#lib_candidates + 1] = vim.fn.fnamemodify(root_dir, ":h") .. "/lib.nvim"
lib_candidates[#lib_candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"
for _, candidate in ipairs(lib_candidates) do
  if vim.fn.isdirectory(candidate .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(candidate)
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
local function eq(name, got, want)
  check(name, got == want, ("got %q want %q"):format(tostring(got), tostring(want)))
end

-- ── The neo-tree stub ─────────────────────────────────────────────────────────

---@type table[]  every `execute` call, in order
local executed = {}
---@type string|nil  error to raise on the next `execute`, once
local fail_next = nil
local stub_neotree = { config = { sources = { "filesystem", "buffers", "git_status" } } }
local stub_command = {
  execute = function(opts)
    executed[#executed + 1] = vim.deepcopy(opts)
    if fail_next then
      local err = fail_next
      fail_next = nil
      error(err)
    end
  end,
}
package.preload["neo-tree"] = function()
  return stub_neotree
end
package.preload["neo-tree.command"] = function()
  return stub_command
end
package.loaded["neo-tree"] = stub_neotree
package.loaded["neo-tree.command"] = stub_command

local function last()
  return executed[#executed]
end

-- ── source_switcher: the pure half ────────────────────────────────────────────

local sw = require("filetree.features.nav.source_switcher")
do
  eq("display_name: nerd v1 long", sw.display_name("buffers"), "  Buffers")
  eq(
    "display_name: common short",
    sw.display_name("git_status", { family = "common", length = "short" }),
    " [GIT] GIT"
  )
  eq("display_name: unknown source falls back to its name", sw.display_name("foo"), " foo")
  eq(
    "display_name: netman module path maps to its icon key",
    sw.display_name("netman.ui.neo-tree", { family = "common" }),
    " [NET] Network"
  )
  eq(
    "display_name: unknown family falls back to nerd",
    sw.display_name("tests", { family = "nope" }),
    sw.display_name("tests")
  )
  local list = sw.display_names({ "filesystem", "tests" }, { family = "common", variant = "v2" })
  eq("display_names: keeps order", list[2].source, "tests")
  eq("display_names: formats each", list[1].display_name, " [F] File System")
  eq("icon: glyph only", sw.icon("filesystem", { family = "common" }), "[DIR]")
end

-- ── source_switcher: with a stub adapter ──────────────────────────────────────

local stub_adapter = {
  name = "neotree",
  get_position = function()
    return "right"
  end,
  toggle_at = function() end,
}
do
  sw.setup({ enabled = true }, stub_adapter)
  local list = sw.sources()
  eq("sources come from neo-tree's config", #list, 3)
  eq("...in its order", list[3], "git_status")

  sw.setup({ enabled = true, sources = { "buffers", "filesystem" } }, stub_adapter)
  eq("a configured source list wins", #sw.sources(), 2)
  eq("...and is copied, not aliased", sw.sources()[1], "buffers")

  -- A list that names document_symbols, so its loadability -- not its
  -- membership -- is what the two checks below exercise.
  sw.setup(
    { enabled = true, sources = { "buffers", "filesystem", "document_symbols" } },
    stub_adapter
  )
  local ok, why = sw.loadable("document_symbols")
  check("document_symbols without an LSP client is not loadable", ok == false and why ~= nil, why)
  check("filesystem is always loadable", sw.loadable("filesystem"))

  executed = {}
  local ok_sw, err = sw.switch("filesystem")
  check("switch to a known source succeeds", ok_sw, err)
  eq("...asks neo-tree to show it", last().source, "filesystem")
  eq("...at the adapter's position when called outside a tree", last().position, "right")
  eq("...without a reveal", last().reveal, false)

  local ok_unknown, err_unknown = sw.switch("nope")
  check(
    "an unknown source is refused",
    ok_unknown == false and err_unknown:find("unknown source") ~= nil,
    err_unknown
  )
  local ok_ds, err_ds = sw.switch("document_symbols")
  check(
    "a source that cannot load is refused with the reason",
    ok_ds == false and err_ds:find("cannot show") ~= nil,
    err_ds
  )

  -- Cycling from outside a tree starts at filesystem.
  sw.setup({ enabled = true }, stub_adapter)
  executed = {}
  sw.next()
  eq("next from outside a tree: filesystem -> buffers", last().source, "buffers")
  executed = {}
  sw.prev()
  eq("prev from outside a tree wraps: filesystem -> git_status", last().source, "git_status")

  -- Inside a tree buffer: the window's own position is kept via "current".
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "neo-tree"
  vim.b[buf].neo_tree_source = "buffers"
  vim.api.nvim_set_current_buf(buf)
  eq("current() reads the tree's source", sw.current(), "buffers")
  executed = {}
  sw.next()
  eq("next inside the tree: buffers -> git_status", last().source, "git_status")
  eq("...replacing the tree window in place", last().position, "current")
  vim.wait(50, function()
    return false
  end)
  local switched_focus = vim.api.nvim_get_current_buf() == buf and 1 or 0
  eq("...and focus stays in the tree window", switched_focus, 1)

  local info = sw.info()
  eq("info names where the list came from", info.source_list_from, "neo-tree")
  eq("info carries the loadability map", info.loadable.filesystem, "ok")

  -- A non-neo-tree adapter binds nothing and switches nothing.
  local other = { name = "nvimtree" }
  local ok_setup = pcall(sw.setup, { enabled = true }, other)
  check("setup on another adapter is a silent no-op", ok_setup)
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
end

-- ── tree_toggle ───────────────────────────────────────────────────────────────

local tt = require("filetree.features.nav.tree_toggle")
do
  local calls = {}
  local adapter = {
    name = "neotree",
    toggle_at = function(position, opts)
      calls[#calls + 1] = { position = position, opts = opts }
      return true
    end,
  }
  local file = vim.fn.tempname() .. ".lua"
  vim.fn.writefile({ "x" }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))

  tt.setup({ enabled = true }, adapter)
  local ok, err = tt.toggle("left")
  check("toggle left succeeds", ok, err)
  eq("...with the position", calls[1].position, "left")
  eq("...revealing the current file", calls[1].opts.file, vim.api.nvim_buf_get_name(0))
  check("...reveal on", calls[1].opts.reveal == true)
  check("...reveal_force_cwd on by default", calls[1].opts.reveal_force_cwd == true)

  tt.setup({ enabled = true, reveal = false }, adapter)
  tt.toggle("float")
  check(
    "reveal = false: no reveal, no file",
    calls[2].opts.reveal == false and calls[2].opts.file == nil
  )

  local ok_bad, err_bad = tt.toggle("bottom")
  check(
    "an unknown position is refused",
    ok_bad == false and err_bad:find("unknown position") ~= nil,
    err_bad
  )

  eq("the four global keys are bound", vim.fn.maparg("<M-l>", "n") ~= "", true)
  eq(
    "...all of them",
    vim.fn.maparg("<M-c>", "n") ~= ""
      and vim.fn.maparg("<M-f>", "n") ~= ""
      and vim.fn.maparg("<M-r>", "n") ~= "",
    true
  )

  tt.teardown()
  eq("teardown unbinds them", vim.fn.maparg("<M-l>", "n"), "")

  local no_toggle = { name = "netrw" }
  tt.setup({ enabled = true }, no_toggle)
  local ok_np, err_np = tt.toggle("left")
  check(
    "an adapter without toggle_at is refused",
    ok_np == false and err_np:find("cannot place") ~= nil,
    err_np
  )
  eq("...and binds nothing", vim.fn.maparg("<M-l>", "n"), "")

  tt.setup({ enabled = false }, adapter)
  eq("disabled: nothing bound", vim.fn.maparg("<M-l>", "n"), "")
  os.remove(file)
end

-- ── neo-tree adapter: toggle_at and the E95 self-heal ─────────────────────────

do
  package.loaded["filetree.adapter.neotree"] = nil
  local nt = require("filetree.adapter.neotree")
  executed = {}
  check(
    "toggle_at succeeds against the stub",
    nt.toggle_at("left", { reveal = true, file = "/x.lua", reveal_force_cwd = true })
  )
  eq("...as a focus+toggle", last().action, "focus")
  check("...toggle set", last().toggle == true)
  eq("...reveal_file passed", last().reveal_file, "/x.lua")
  check("...reveal_force_cwd passed", last().reveal_force_cwd == true)

  executed = {}
  nt.toggle_at("left", { reveal = false, reveal_force_cwd = true })
  check("reveal_force_cwd needs reveal", last().reveal_force_cwd == false)

  -- A dead, never-rendered neo-tree window is what E95 leaves behind.
  local dead = vim.api.nvim_create_buf(false, true)
  vim.bo[dead].filetype = "neo-tree"
  vim.cmd("vsplit")
  local dead_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(dead_win, dead)
  vim.cmd("wincmd p")

  executed = {}
  fail_next = "Vim:E95: Buffer with this name already exists"
  local ok_heal = nt.toggle_at("left", {})
  check("first execute fails, the retry succeeds", ok_heal)
  eq("...two executes in total", #executed, 2)
  check(
    "...the unnamed neo-tree window was closed in between",
    not vim.api.nvim_win_is_valid(dead_win)
  )

  executed = {}
  fail_next = "Vim:E95: still"
  -- Both attempts fail: the second error is reported, false returned.
  local orig_exec = stub_command.execute
  stub_command.execute = function(opts)
    executed[#executed + 1] = opts
    error("Vim:E95: again")
  end
  local ok_twice = nt.toggle_at("left", {})
  stub_command.execute = orig_exec
  fail_next = nil
  check("both attempts failing returns false", ok_twice == false)
  eq("...after exactly one retry", #executed, 2)
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
