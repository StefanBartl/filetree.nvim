-- cwd_mode.lua — headless tests for the cwd/root policy feature.
--
-- Covers the decision logic every mode produces for cwd_sync, the lock's
-- enforcement against foreign `:cd`, manual re-rooting, the mode cycle, the
-- command wiring, and the tree-window badge in both drawing strategies.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l test/cwd_mode.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)
-- $FILETREE_LIB_NVIM overrides the sibling checkout, so this suite can be run
-- against a lib.nvim worktree/branch before it is merged — this feature is the
-- first consumer of several lib.nvim modules, and they land there first.
local sibling_lib = vim.env.FILETREE_LIB_NVIM
if not sibling_lib or sibling_lib == "" then
  sibling_lib = vim.fn.fnamemodify(root_dir, ":h") .. "/lib.nvim"
end
if vim.fn.isdirectory(sibling_lib) == 1 then vim.opt.rtp:prepend(sibling_lib) end

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1; print("  ok   " .. name)
  else failed = failed + 1; print("  FAIL " .. name .. (detail and ("  — " .. detail) or "")) end
end
local function eq(name, got, want)
  check(name, got == want, ("got %q want %q"):format(tostring(got), tostring(want)))
end

local normkey = require("lib.nvim.fs.normkey")
local cwd_mode = require("filetree.features.nav.cwd_mode")

-- Two independent projects plus a directory with no root marker at all.
local base = normkey(vim.fn.tempname())
vim.fn.mkdir(base .. "/proj_a/.git", "p")
vim.fn.mkdir(base .. "/proj_a/src", "p")
vim.fn.mkdir(base .. "/proj_b/.git", "p")
vim.fn.mkdir(base .. "/loose", "p")
for _, rel in ipairs({ "proj_a/src/one.lua", "proj_b/three.lua", "loose/four.md" }) do
  local h = io.open(base .. "/" .. rel, "w")
  h:write("x")
  h:close()
end

---Minimal adapter: cwd_mode only needs the window (badge) and the node
---(lock_here). Everything else stays untouched by this feature.
---@param winid integer?
local function stub_adapter(winid)
  return {
    name = "cwd-mode-stub",
    get_winid = function()
      return (winid and vim.api.nvim_win_is_valid(winid)) and winid or nil
    end,
    get_current_node = function() return nil end,
    get_root_path = function() return base end,
  }
end

local silent = { enabled = true, indicator = { enabled = false } }

-- ── follow: no policy at all ──────────────────────────────────────────────────
do
  cwd_mode.setup(vim.deepcopy(silent), stub_adapter(nil))
  eq("starts in follow mode", cwd_mode.mode(), "follow")
  check("follow returns no decision (cwd_sync keeps its own resolution)",
    cwd_mode.decide(base .. "/proj_a/src/one.lua") == nil)
end

-- ── project ───────────────────────────────────────────────────────────────────
do
  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(base .. "/proj_a"))
  cwd_mode.set_mode("project")
  eq("project seeds its root from the current buffer/cwd", cwd_mode.root(), base .. "/proj_a")

  local d = cwd_mode.decide(base .. "/proj_a/src/one.lua")
  eq("inside the project: root holds", d.root, base .. "/proj_a")
  check("inside: chdir allowed", d.chdir == true)
  check("inside: reveal allowed", d.reveal == true)

  d = cwd_mode.decide(base .. "/loose/four.md")
  eq("sticky: a rootless file does not move the root", d.root, base .. "/proj_a")
  check("sticky: an outside file is not revealed (reveal_outside=skip)", d.reveal == false)

  d = cwd_mode.decide(base .. "/proj_b/three.lua")
  eq("a file in another project switches the root", d.root, base .. "/proj_b")
  eq("root() follows the switch", cwd_mode.root(), base .. "/proj_b")

  cwd_mode.setup(
    vim.tbl_deep_extend("force", vim.deepcopy(silent), { project = { sticky = false } }),
    stub_adapter(nil))
  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(base .. "/proj_a"))
  cwd_mode.set_mode("project")
  d = cwd_mode.decide(base .. "/loose/four.md")
  eq("sticky=false: a rootless file roots at its own directory", d.root, base .. "/loose")
end

-- ── lock ──────────────────────────────────────────────────────────────────────
do
  cwd_mode.setup(vim.deepcopy(silent), stub_adapter(nil))
  cwd_mode.lock(base .. "/proj_a")
  eq("lock mode active", cwd_mode.mode(), "lock")
  eq("lock pins the root", cwd_mode.root(), base .. "/proj_a")
  eq("lock changed the cwd", normkey(vim.fn.getcwd()), base .. "/proj_a")

  local d = cwd_mode.decide(base .. "/proj_a/src/one.lua")
  eq("locked: a file inside keeps the pin", d.root, base .. "/proj_a")
  check("locked: a file inside is revealed", d.reveal == true)

  d = cwd_mode.decide(base .. "/proj_b/three.lua")
  eq("locked: a file outside does NOT move the root", d.root, base .. "/proj_a")
  check("locked: a file outside is not revealed", d.reveal == false)

  vim.cmd("cd " .. vim.fn.fnameescape(base .. "/proj_b"))
  eq("the guard reverts a foreign :cd", normkey(vim.fn.getcwd()), base .. "/proj_a")

  cwd_mode.notify_manual_root(base .. "/proj_b")
  eq("a manual re-root moves the lock instead of being reverted",
    cwd_mode.root(), base .. "/proj_b")
  eq("the cwd follows the manual re-root", normkey(vim.fn.getcwd()), base .. "/proj_b")

  cwd_mode.unlock()
  eq("unlock returns to the previous mode", cwd_mode.mode(), "follow")
  vim.cmd("cd " .. vim.fn.fnameescape(base .. "/loose"))
  eq("the guard is released after unlock", normkey(vim.fn.getcwd()), base .. "/loose")

  -- enforce = false still pins the root, it just stops reverting.
  cwd_mode.setup(
    vim.tbl_deep_extend("force", vim.deepcopy(silent), { lock = { enforce = false } }),
    stub_adapter(nil))
  cwd_mode.lock(base .. "/proj_a")
  vim.cmd("cd " .. vim.fn.fnameescape(base .. "/proj_b"))
  eq("enforce=false: a foreign :cd stands", normkey(vim.fn.getcwd()), base .. "/proj_b")
  eq("enforce=false: the pinned root is unchanged", cwd_mode.root(), base .. "/proj_a")
end

-- ── manual ────────────────────────────────────────────────────────────────────
do
  cwd_mode.setup(vim.deepcopy(silent), stub_adapter(nil))
  cwd_mode.set_mode("manual")
  local d = cwd_mode.decide(base .. "/proj_a/src/one.lua")
  check("manual: no chdir", d.chdir == false)
  check("manual: no reveal", d.reveal == false)
end

-- ── cycle ─────────────────────────────────────────────────────────────────────
do
  cwd_mode.setup(vim.deepcopy(silent), stub_adapter(nil))
  cwd_mode.cycle(); eq("cycle: follow → project", cwd_mode.mode(), "project")
  cwd_mode.cycle(); eq("cycle: project → lock", cwd_mode.mode(), "lock")
  cwd_mode.cycle(); eq("cycle wraps back to follow", cwd_mode.mode(), "follow")
  cwd_mode.teardown()
end

-- ── indicator ─────────────────────────────────────────────────────────────────
do
  vim.cmd("vsplit")
  local tree_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd p")
  local adapter = stub_adapter(tree_win)

  local function stl()
    return vim.api.nvim_get_option_value("statusline", { win = tree_win, scope = "local" })
  end
  local function float_count()
    local n = 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then n = n + 1 end
    end
    return n
  end

  local original_laststatus = vim.o.laststatus
  vim.o.laststatus = 2
  cwd_mode.setup({ enabled = true, indicator = { mode = "statusline", show_path = "never" } }, adapter)

  cwd_mode.set_mode("project")
  eq("badge: PROJECT", stl(), "%#DiagnosticInfo#PROJECT%*")
  cwd_mode.lock(base .. "/proj_a")
  eq("badge: LOCK", stl(), "%#DiagnosticWarn#LOCK%*")
  cwd_mode.set_mode("manual")
  eq("badge: MANUAL", stl(), "%#Comment#MANUAL%*")
  cwd_mode.set_mode("follow")
  eq("badge: follow shows nothing", stl(), "")

  cwd_mode.setup({ enabled = true, indicator = { mode = "statusline", show_path = "lock" } }, adapter)
  cwd_mode.lock(base .. "/proj_a")
  check("badge: show_path appends the pinned directory",
    stl():find("LOCK", 1, true) ~= nil and stl():find("proj_a", 1, true) ~= nil, stl())
  check("component() exposes the badge text", cwd_mode.component():find("LOCK", 1, true) == 1)

  cwd_mode.teardown()
  eq("teardown restores the statusline", stl(), "")

  vim.o.laststatus = 3
  cwd_mode.setup({ enabled = true, indicator = { mode = "auto", show_path = "never" } }, adapter)
  eq("no float before a mode is set", float_count(), 0)
  cwd_mode.lock(base .. "/proj_a")
  eq("auto falls back to a float under laststatus=3", float_count(), 1)
  cwd_mode.set_mode("follow")
  eq("follow closes the float", float_count(), 0)
  cwd_mode.teardown()
  eq("teardown closes any float", float_count(), 0)

  vim.o.laststatus = original_laststatus
end

-- ── command wiring ────────────────────────────────────────────────────────────
do
  local commands = require("filetree.commands")
  local paths = table.concat(commands.command_paths(), "\n")
  for _, want in ipairs({ "cwd mode", "cwd lock", "cwd here", "cwd unlock", "cwd toggle", "cwd status" }) do
    check("command path registered: :Filetree " .. want, paths:find(want, 1, true) ~= nil)
  end

  commands.setup()
  local completions = vim.fn.getcompletion("Filetree cwd mode ", "cmdline")
  check("`:Filetree cwd mode` completes its enum",
    vim.tbl_contains(completions, "project") and vim.tbl_contains(completions, "manual"),
    vim.inspect(completions))
end

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nfiletree.nvim cwd_mode: %d passed, %d failed"):format(passed, failed))
if failed > 0 then vim.cmd("cq") else vim.cmd("qa!") end
