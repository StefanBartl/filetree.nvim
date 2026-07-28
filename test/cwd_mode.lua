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

-- A separate monorepo tree for `nearest`: one .git at the top, packages below.
local mono = normkey(vim.fn.tempname())

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

-- ── nearest: package boundary instead of the VCS root ─────────────────────────
do
  -- A monorepo: one .git at the top, two packages below it.
  vim.fn.mkdir(mono .. "/.git", "p")
  vim.fn.mkdir(mono .. "/packages/app/src", "p")
  vim.fn.mkdir(mono .. "/packages/lib", "p")
  for _, rel in ipairs({ ".git/HEAD", "package.json", "packages/app/package.json",
                         "packages/app/src/main.ts", "packages/lib/package.json" }) do
    local h = assert(io.open(mono .. "/" .. rel, "w"), "could not create " .. rel)
    h:write("x")
    h:close()
  end

  cwd_mode.setup(vim.deepcopy(silent), stub_adapter(nil))
  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(mono .. "/packages/app"))

  cwd_mode.set_mode("project")
  local d = cwd_mode.decide(mono .. "/packages/app/src/main.ts")
  eq("project: the repository is the root", d.root, mono)

  -- Back into the package first: a mode seeds from where you *are*, and project
  -- mode just moved the cwd up to the repository root.
  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(mono .. "/packages/app"))
  cwd_mode.set_mode("nearest")
  eq("nearest seeds from the package, not the repo", cwd_mode.root(), mono .. "/packages/app")
  d = cwd_mode.decide(mono .. "/packages/app/src/main.ts")
  eq("nearest: the owning package is the root", d.root, mono .. "/packages/app")

  d = cwd_mode.decide(mono .. "/packages/lib/package.json")
  eq("nearest: a sibling package switches the root", d.root, mono .. "/packages/lib")

  -- A file that belongs to no package falls back to the repo (".git" is the
  -- last-resort marker), not to the filesystem root.
  local h = io.open(mono .. "/README.md", "w"); h:write("x"); h:close()
  d = cwd_mode.decide(mono .. "/README.md")
  eq("nearest: a file outside any package lands on the repo", d.root, mono)

  cwd_mode.teardown()
end

-- ── tree_leads: the tree decides, not the buffer ──────────────────────────────
do
  local tree_root = base .. "/proj_a"
  local adapter = stub_adapter(nil)
  adapter.get_root_path = function() return tree_root end

  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(base .. "/loose"))
  cwd_mode.setup(vim.deepcopy(silent), adapter)
  cwd_mode.set_mode("tree_leads")
  eq("tree_leads seeds from the tree root", cwd_mode.root(), tree_root)
  eq("tree_leads moved the cwd to the tree root", normkey(vim.fn.getcwd()), tree_root)

  -- Buffer switches move nothing: that is the entire point of the reversal.
  local d = cwd_mode.decide(base .. "/proj_b/three.lua")
  eq("tree_leads: a buffer elsewhere does not move the root", d.root, tree_root)
  check("tree_leads: no chdir on a buffer switch", d.chdir == false)
  check("tree_leads: a file outside the tree root is not revealed", d.reveal == false)

  d = cwd_mode.decide(base .. "/proj_a/src/one.lua")
  check("tree_leads: still no chdir for a file inside", d.chdir == false)
  check("tree_leads: a file inside the tree root is revealed", d.reveal == true)

  -- Re-rooting the tree is what moves the cwd here.
  cwd_mode.notify_manual_root(base .. "/proj_b")
  eq("tree_leads: a re-root moves the root", cwd_mode.root(), base .. "/proj_b")
  eq("tree_leads: the cwd followed the tree", normkey(vim.fn.getcwd()), base .. "/proj_b")

  cwd_mode.teardown()
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

-- ── scope: global / tab / win ─────────────────────────────────────────────────
do
  local function global_cwd() return normkey(vim.fn.getcwd(-1, -1)) end
  local function win_cwd()    return normkey(vim.fn.getcwd(0, 0)) end

  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(base .. "/loose"))
  cwd_mode.setup(
    vim.tbl_deep_extend("force", vim.deepcopy(silent), { scope = "win" }),
    stub_adapter(nil))
  eq("scope is reported", cwd_mode.scope(), "win")

  cwd_mode.lock(base .. "/proj_a")
  eq("win scope: the window cwd moved", win_cwd(), base .. "/proj_a")
  eq("win scope: the global cwd is untouched", global_cwd(), base .. "/loose")

  -- The guard watches the scope it holds, so a window-local change is what it
  -- reverts here.
  vim.cmd("lcd " .. vim.fn.fnameescape(base .. "/proj_b"))
  eq("win scope: the guard reverts a foreign :lcd", win_cwd(), base .. "/proj_a")

  -- Switching scope re-anchors the held root in the new one.
  cwd_mode.set_scope("global")
  eq("scope switch is reported", cwd_mode.scope(), "global")
  eq("scope switch re-applies the pin globally", global_cwd(), base .. "/proj_a")
  check("scope switch keeps the lock", cwd_mode.mode() == "lock")
  vim.cmd("cd " .. vim.fn.fnameescape(base .. "/proj_b"))
  eq("the re-anchored guard still enforces", global_cwd(), base .. "/proj_a")

  check("an unknown scope is rejected", cwd_mode.set_scope("nope") == false)
  eq("a rejected scope changes nothing", cwd_mode.scope(), "global")

  cwd_mode.teardown()
  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(base))
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

-- ── persistence ───────────────────────────────────────────────────────────────
do
  -- store.project keys by the project of the directory Neovim started in, which
  -- cwd_mode captures at setup(). Sitting in proj_b for the whole block makes
  -- that key stable while the lock moves the cwd elsewhere.
  local function fresh(extra)
    vim.cmd("noautocmd cd " .. vim.fn.fnameescape(base .. "/proj_b"))
    cwd_mode.setup(
      vim.tbl_deep_extend("force", vim.deepcopy(silent), { persist = true }, extra or {}),
      stub_adapter(nil))
  end

  fresh()
  cwd_mode.forget() -- a leftover entry from an earlier run must not decide this
  cwd_mode.lock(base .. "/proj_a")

  -- A fresh setup() is what a restart looks like from the feature's side.
  fresh()
  eq("nothing is restored synchronously", cwd_mode.mode(), "follow")
  vim.wait(200, function() return cwd_mode.mode() == "lock" end)
  eq("the saved lock is restored", cwd_mode.mode(), "lock")
  eq("the saved pin is restored", cwd_mode.root(), base .. "/proj_a")

  -- The saved policy outranks a configured mode: it is the later, explicit
  -- choice of the same user.
  fresh({ mode = "project" })
  vim.wait(200, function() return cwd_mode.mode() ~= "follow" end)
  eq("a saved policy wins over the configured mode", cwd_mode.mode(), "lock")

  -- A lock whose directory disappeared must not take the session hostage.
  vim.fn.mkdir(base .. "/gone_soon", "p")
  cwd_mode.lock(base .. "/gone_soon")
  eq("locked onto the doomed directory", cwd_mode.root(), base .. "/gone_soon")
  -- teardown() releases the guard without persisting, so the saved lock stays
  -- while the directory it points at goes away underneath it.
  cwd_mode.teardown()
  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(base))
  vim.fn.delete(base .. "/gone_soon", "d")
  fresh({ mode = "project" })
  vim.wait(200, function() return cwd_mode.mode() ~= "follow" end)
  eq("a stale lock is declined, the configured mode applies", cwd_mode.mode(), "project")

  -- Scope round-trips too.
  cwd_mode.set_mode("follow")
  cwd_mode.set_scope("tab")
  fresh()
  vim.wait(200, function() return cwd_mode.scope() == "tab" end)
  eq("the saved scope is restored", cwd_mode.scope(), "tab")
  cwd_mode.set_scope("global")

  -- forget() drops the entry; the next start falls back to the config.
  cwd_mode.lock(base .. "/proj_a")
  cwd_mode.forget()
  fresh({ mode = "manual" })
  vim.wait(200, function() return cwd_mode.mode() ~= "follow" end)
  eq("after forget the configured mode applies", cwd_mode.mode(), "manual")
  cwd_mode.forget()

  -- With persist = false nothing is written at all.
  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(base .. "/proj_b"))
  cwd_mode.setup(vim.deepcopy(silent), stub_adapter(nil))
  cwd_mode.lock(base .. "/proj_a")
  cwd_mode.setup(vim.deepcopy(silent), stub_adapter(nil))
  vim.wait(100)
  eq("persist=false leaves no trace", cwd_mode.mode(), "follow")

  cwd_mode.teardown()
  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(base))
end

-- ── util.root: the shared resolver every project-scoped feature asks ─────────
do
  local util_root = require("filetree.util.root")
  cwd_mode.setup(vim.deepcopy(silent), stub_adapter(nil))

  -- follow mode: no held root, so the buffer's own project root decides —
  -- exactly the behaviour that existed before cwd_mode.
  vim.cmd("noautocmd edit " .. vim.fn.fnameescape(base .. "/proj_b/three.lua"))
  eq("follow: util.root resolves from the buffer",
    normkey(util_root.find()), base .. "/proj_b")
  eq("follow: an explicit path wins over the buffer",
    normkey(util_root.find(base .. "/proj_a/src/one.lua")), base .. "/proj_a")

  -- locked: the held root wins even though the focused buffer belongs to
  -- another project. This is the case find_files/grep/git_status got wrong.
  cwd_mode.lock(base .. "/proj_a")
  eq("locked: util.root returns the lock, not the buffer's project",
    normkey(util_root.find()), base .. "/proj_a")
  eq("locked: an explicit path does not escape the lock either",
    normkey(util_root.find(base .. "/proj_b/three.lua")), base .. "/proj_a")

  cwd_mode.unlock()
  eq("after unlock: back to the buffer's project",
    normkey(util_root.find()), base .. "/proj_b")

  -- One walk governs both the cwd and anything project-scoped. project_root's
  -- broader marker set would answer "the package" here; cwd_mode's VCS set
  -- answers "the repository", and that is what the cwd is anchored to too.
  eq("follow: a vendored file resolves past node_modules",
    normkey(util_root.find(mono .. "/packages/app/src/main.ts")), mono)

  cwd_mode.teardown()

  -- With cwd_mode torn down, resolve() declines and the old chain applies —
  -- project_root's own walk, which stops at the package.json.
  eq("without cwd_mode: project_root decides again",
    normkey(util_root.find(mono .. "/packages/app/src/main.ts")),
    mono .. "/packages/app")

  vim.cmd("noautocmd enew")
end

-- ── badge(): the object a hand-rolled/heirline-style statusline consumes ─────
do
  vim.cmd("vsplit")
  local tree_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd p")
  local adapter = stub_adapter(tree_win)

  -- indicator.enabled = false is the whole point of this API: the internal
  -- badge stays off, but badge()/component() and the change event must still
  -- work — otherwise there would be no way to consume the mode externally
  -- without the tree window also showing it. show_path is covered by its own
  -- test above; kept off here so the text assertions are just the label.
  cwd_mode.setup(
    { enabled = true, indicator = { enabled = false, show_path = "never" } },
    adapter)

  local b = cwd_mode.badge()
  eq("badge(): follow has no text", b.text, "")
  eq("badge(): follow mode is reported", b.mode, "follow")
  eq("badge(): follow has no root", b.root, nil)

  cwd_mode.lock(base .. "/proj_a")
  b = cwd_mode.badge()
  eq("badge(): text matches the internal label", b.text, "LOCK")
  eq("badge(): hl matches the configured group", b.hl, "DiagnosticWarn")
  eq("badge(): mode is reported", b.mode, "lock")
  eq("badge(): root is reported", b.root, base .. "/proj_a")

  eq("component() still returns text only", cwd_mode.component(), "LOCK")

  -- No internal badge was ever attached with indicator.enabled = false.
  local has_float = false
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then has_float = true end
  end
  check("indicator.enabled=false attaches no float", not has_float)
  check("indicator.enabled=false sets no tree statusline",
    vim.api.nvim_get_option_value("statusline", { win = tree_win, scope = "local" }) == "")

  cwd_mode.teardown()
end

-- ── FiletreeCwdModeChanged: the event an external statusline hooks ───────────
do
  local fires = 0
  local group = vim.api.nvim_create_augroup("cwd_mode_test_change_event", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "FiletreeCwdModeChanged",
    callback = function() fires = fires + 1 end,
  })

  cwd_mode.setup({ enabled = true, indicator = { enabled = false } }, stub_adapter(nil))
  local after_setup = fires

  cwd_mode.lock(base .. "/proj_a")
  check("locking fires the change event", fires > after_setup)
  local after_lock = fires

  -- A window-lifecycle refresh with no state change must not re-fire it —
  -- otherwise a busy tab-switching session would spam a plugin's refresh().
  cwd_mode.refresh_indicator()
  cwd_mode.refresh_indicator()
  eq("an unchanged refresh does not re-fire the event", fires, after_lock)

  cwd_mode.set_mode("follow")
  check("leaving lock (text changes to empty) fires again", fires > after_lock)

  vim.api.nvim_del_augroup_by_id(group)
  cwd_mode.teardown()
end

-- ── warning when project/nearest cannot actually follow buffer switches ──────
do
  -- cwd_sync is disabled in this whole suite's process (never set up), so
  -- switching into project/nearest must warn every time; lock/tree_leads/
  -- manual/follow must never warn, since they do not depend on it.
  -- cwd_mode's notifier ultimately calls vim.notify, so intercept there
  -- rather than trying to reach the module-local notifier instance.
  local captured = {}
  local orig_vim_notify = vim.notify
  vim.notify = function(msg, level, opts)
    captured[#captured + 1] = msg
    return orig_vim_notify(msg, level, opts)
  end

  cwd_mode.setup(vim.deepcopy(silent), stub_adapter(nil))

  local function warned_about(mode)
    for _, msg in ipairs(captured) do
      if msg:find(mode .. " mode needs", 1, true) then return true end
    end
    return false
  end

  captured = {}
  cwd_mode.set_mode("project")
  check("project without cwd_sync warns", warned_about("project"))

  captured = {}
  cwd_mode.set_mode("nearest")
  check("nearest without cwd_sync warns", warned_about("nearest"))

  captured = {}
  cwd_mode.lock(base .. "/proj_a")
  check("lock never warns about cwd_sync", not warned_about("lock"))

  captured = {}
  cwd_mode.set_mode("tree_leads")
  check("tree_leads never warns about cwd_sync", not warned_about("tree_leads"))

  captured = {}
  cwd_mode.set_mode("manual")
  check("manual never warns", #captured == 0)

  captured = {}
  cwd_mode.set_mode("follow")
  check("follow never warns", #captured == 0)

  -- The positive case: a real filetree.setup() with cwd_sync genuinely
  -- enabled must not warn. This is the case the fix above hinges on —
  -- `filetree.feature("cwd_sync")` only returns non-nil once setup() actually
  -- ran it, unlike the registry check that motivated the bug in the first
  -- place (requiring the module file always "succeeds").
  local real_ft = require("filetree")
  real_ft.register_adapter(setmetatable({
    name = "cwd-mode-warn-stub",
    is_available = function() return true end,
  }, { __index = function() return function() return false end end }))

  captured = {}
  real_ft.setup({
    adapter = "cwd-mode-warn-stub",
    features = { cwd_sync = { enabled = true } },
  })
  check("cwd_sync is genuinely active via filetree.feature()",
    real_ft.feature("cwd_sync") ~= nil)

  captured = {}
  real_ft.feature("cwd_mode").set_mode("project")
  check("project with cwd_sync truly enabled does not warn", not warned_about("project"))

  vim.notify = orig_vim_notify
  cwd_mode.teardown()
end

-- ── command wiring ────────────────────────────────────────────────────────────
do
  local commands = require("filetree.commands")
  local paths = table.concat(commands.command_paths(), "\n")
  for _, want in ipairs({ "cwd mode", "cwd scope", "cwd lock", "cwd here",
                          "cwd unlock", "cwd toggle", "cwd status", "cwd forget" }) do
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
