-- units.lua — headless unit tests for filetree.nvim's util layer + adapter helpers.
--
-- Complements test/smoke.lua (which is an integration test over the registry and
-- setup). This file exercises the reusable primitives directly.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l test/units.lua
--
-- Exit 0 = all passed, 1 = a check failed.

-- ":p" resolves to absolute *before* walking up two levels, so `root` stays
-- correct even if a test later changes Neovim's cwd (":h:h" alone would give a
-- path relative to invocation-time cwd, e.g. "." when run as `-l test/units.lua`,
-- which breaks require() after any vim.fn.chdir()).
local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root)
-- $FILETREE_LIB_NVIM overrides the sibling checkout, so this suite can run
-- against a lib.nvim worktree/branch before it is merged.
local sibling_lib = vim.env.FILETREE_LIB_NVIM
if not sibling_lib or sibling_lib == "" then
  sibling_lib = vim.fn.fnamemodify(root, ":h") .. "/lib.nvim"
end
if vim.fn.isdirectory(sibling_lib) == 1 then vim.opt.rtp:prepend(sibling_lib) end

-- Cross-platform scratch-dir root for the many `tmp = TMP_ROOT .. "/units-*"`
-- fixtures below. $TEMP is Windows-only; POSIX runners (incl. CI) don't set
-- it, which previously hard-errored ("attempt to concatenate a nil value").
local TMP_ROOT = vim.env.TEMP or vim.env.TMPDIR or vim.env.TMP or "/tmp"

-- Headless CI runners (no X11/Wayland session) commonly have no clipboard
-- provider at all; without one, "+"/"*" register writes/reads don't
-- round-trip even in-memory. Probe once so clipboard-dependent fixtures
-- below can skip their content assertions rather than fail on an
-- environment limitation unrelated to the feature's own logic.
local _clip_probe = "__filetree_units_clipboard_probe__"
vim.fn.setreg("+", _clip_probe)
local HAS_CLIPBOARD = vim.fn.getreg("+") == _clip_probe
vim.fn.setreg("+", "")
if not HAS_CLIPBOARD then
  print("  note no clipboard provider available — skipping clipboard-content assertions")
end

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1; print("  ok   " .. name)
  else failed = failed + 1; print("  FAIL " .. name .. (detail and ("  — " .. detail) or "")) end
end
local function eq(name, got, want)
  check(name, got == want, ("got %q want %q"):format(tostring(got), tostring(want)))
end

-- ── util.path ─────────────────────────────────────────────────────────────────
do
  local path = require("filetree.util.path")
  -- "E:\a\b" is only absolute on Windows; on POSIX it has no leading "/" and
  -- to_absolute() would (correctly) resolve it against cwd instead, so this
  -- assertion only holds on Windows. On POSIX, assert the same backslash-to-
  -- forward-slash behavior with a path that is actually absolute there.
  if vim.fn.has("win32") == 1 then
    eq("path.to_unix backslashes", path.to_unix("E:\\a\\b"):gsub("^%a:", ""), "/a/b")
  else
    eq("path.to_unix backslashes", path.to_unix("/a\\b"), "/a/b")
  end
  check("path.ensure_dir file → parent",
    path.ensure_dir(root .. "/lua/filetree/init.lua"):gsub("\\", "/"):match("/filetree$") ~= nil)
  check("path.ensure_dir dir → self",
    path.ensure_dir(root .. "/lua"):gsub("\\", "/"):match("/lua$") ~= nil)
  eq("path.relative under base", path.relative(root .. "/lua/x.lua", root), "lua/x.lua")
  eq("path.basename", path.basename("/a/b/c.lua"), "c.lua")
  eq("path.parent", path.parent("/a/b/c.lua"):gsub("\\", "/"), "/a/b")
  check("path.escape_shell_arg is string", type(path.escape_shell_arg("a b")) == "string")

  -- Single canonical separator: prompts/notifications always show "/", and
  -- either "/" or "\" typed by the user sanitizes to "/". Regression coverage
  -- for the smart_create/smart_rename prompt fix.
  eq("path.slashify converts backslashes", path.slashify("E:\\a\\b"), "E:/a/b")
  eq("path.slashify is idempotent on forward slashes", path.slashify("E:/a/b"), "E:/a/b")
  check("path.parent never contains a backslash",
    not path.parent(root .. "\\lua\\filetree\\init.lua"):find("\\", 1, true))
  check("path.relative (outside base) never contains a backslash",
    not path.relative("Z:\\some\\other\\file.lua", root):find("\\", 1, true))
end

-- ── util.buffer ───────────────────────────────────────────────────────────────
do
  local buf = require("filetree.util.buffer")
  check("buffer.TREE_FT has neo-tree", buf.TREE_FT["neo-tree"] == true)
  check("buffer.find_editor_win callable", type(buf.find_editor_win) == "function")
  -- a scratch (nofile) buffer is not a valid file buffer
  local b = vim.api.nvim_create_buf(false, true)
  check("is_valid_file_buffer false for scratch", buf.is_valid_file_buffer(b) == false)
  -- an editor window holding a real file is found
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/README.md"))
  local ewin = buf.find_editor_win(nil)
  check("find_editor_win finds the README window", ewin ~= nil)

  -- ── buffer.relocate ── repoint open buffers after a file/dir move or rename.
  -- Regression for: cutting a node (x) and pasting it (p) into a new
  -- directory left the original buffer pointing at a path that no longer
  -- existed, so opening the file at its new location created a second,
  -- disconnected buffer instead of reusing the original one.
  local tmp = (TMP_ROOT .. "/units-relocate"):gsub("\\", "/")
  vim.fn.mkdir(tmp .. "/src/sub", "p")
  vim.fn.mkdir(tmp .. "/dst", "p")

  -- exact-match single file
  vim.fn.writefile({ "a" }, tmp .. "/src/a.txt")
  vim.cmd("edit " .. tmp .. "/src/a.txt")
  local buf_a = vim.api.nvim_get_current_buf()
  vim.fn.rename(tmp .. "/src/a.txt", tmp .. "/dst/a.txt")
  local n1 = buf.relocate(tmp .. "/src/a.txt", tmp .. "/dst/a.txt")
  eq("relocate: exact match repoints 1 buffer", n1, 1)
  eq("relocate: exact match new buffer name",
    vim.api.nvim_buf_get_name(buf_a):gsub("\\", "/"), tmp .. "/dst/a.txt")

  -- directory move: a buffer nested under the moved dir is repointed too
  vim.fn.writefile({ "b" }, tmp .. "/src/sub/b.txt")
  vim.cmd("edit " .. tmp .. "/src/sub/b.txt")
  local buf_b = vim.api.nvim_get_current_buf()
  vim.fn.mkdir(tmp .. "/dst2", "p")
  vim.fn.rename(tmp .. "/src/sub", tmp .. "/dst2/sub")
  buf.relocate(tmp .. "/src/sub", tmp .. "/dst2/sub")
  eq("relocate: directory move repoints nested buffer",
    vim.api.nvim_buf_get_name(buf_b):gsub("\\", "/"), tmp .. "/dst2/sub/b.txt")

  -- a MODIFIED buffer must not lose its unsaved changes
  vim.fn.writefile({ "orig" }, tmp .. "/src/c.txt")
  vim.cmd("edit " .. tmp .. "/src/c.txt")
  local buf_c = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf_c, 0, -1, false, { "UNSAVED" })
  vim.fn.rename(tmp .. "/src/c.txt", tmp .. "/dst/c.txt")
  buf.relocate(tmp .. "/src/c.txt", tmp .. "/dst/c.txt")
  check("relocate: modified buffer keeps its unsaved content",
    vim.api.nvim_buf_get_lines(buf_c, 0, -1, false)[1] == "UNSAVED")
  eq("relocate: modified buffer still gets the new name",
    vim.api.nvim_buf_get_name(buf_c):gsub("\\", "/"), tmp .. "/dst/c.txt")

  -- path-separator mismatch (backslash old/new vs forward-slash buffer name) --
  -- regression for the class of bug this session found across all 5 adapters.
  vim.fn.writefile({ "d" }, tmp .. "/src/d.txt")
  vim.cmd("edit " .. tmp .. "/src/d.txt")
  vim.fn.rename(tmp .. "/src/d.txt", tmp .. "/dst/d.txt")
  local n4 = buf.relocate((tmp .. "/src/d.txt"):gsub("/", "\\"), (tmp .. "/dst/d.txt"):gsub("/", "\\"))
  eq("relocate: backslash old/new path still matches forward-slash buffer name", n4, 1)

  -- ── buffer.close_for_path ── closing a shown buffer must NOT spawn a fresh
  -- [No Name]; the window is switched to another real (named) buffer first.
  -- Regression for: deleting an open file left a blank buffer that reshuffled
  -- the window layout, even though other buffers were open.
  vim.fn.writefile({ "1" }, tmp .. "/f1.txt")
  vim.fn.writefile({ "2" }, tmp .. "/f2.txt")
  vim.cmd("only")
  vim.cmd("edit " .. tmp .. "/f1.txt")   -- becomes the alternate
  vim.cmd("edit " .. tmp .. "/f2.txt")   -- shown in the window, to be closed
  local win  = vim.api.nvim_get_current_win()
  local doomed = vim.api.nvim_get_current_buf()

  local function noname_count()
    local c = 0
    for _, nb in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(nb) and vim.api.nvim_buf_is_loaded(nb)
         and vim.api.nvim_buf_get_name(nb) == "" then c = c + 1 end
    end
    return c
  end
  local before_noname = noname_count()

  local cn = buf.close_for_path(tmp .. "/f2.txt")
  eq("close_for_path: closed the shown buffer", cn, 1)
  check("close_for_path: doomed buffer is gone",
    not vim.api.nvim_buf_is_valid(doomed) or vim.api.nvim_buf_get_name(doomed) == "")
  local now_shown = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):gsub("\\", "/")
  eq("close_for_path: window switched to the alternate named buffer, not a blank",
    now_shown, tmp .. "/f1.txt")
  eq("close_for_path: no new [No Name] buffer was created", noname_count(), before_noname)
end

-- ── util.confirm ── kit.confirm button dialog, replacing native vim.fn.confirm ─
do
  local confirm = require("filetree.util.confirm")
  local function keys(s) return vim.api.nvim_replace_termcodes(s, true, false, true) end

  local got
  confirm({ title = " T ", body = { "  info line" }, question = "Do it?",
            on_choice = function(yes) got = yes end })
  -- The dialog floats and takes focus; default focus is "Yes" (button 1).
  local float_open = false
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then float_open = true end
  end
  check("confirm: opens a floating window", float_open)
  vim.api.nvim_feedkeys(keys("<CR>"), "x", false)
  check("confirm: <CR> on the default-focused Yes resolves to true", got == true)

  got = nil
  confirm({ body = {}, question = "Do it?", on_choice = function(yes) got = yes end })
  vim.api.nvim_feedkeys(keys("l<CR>"), "x", false)
  check("confirm: l<CR> moves focus to No and resolves to false", got == false)
end

-- ── opened_sync ── buffer open/close triggers a light adapter redraw ────────
do
  local redrew = 0
  local stub = setmetatable({
    name = "units-stub-opensync", is_available = function() return true end,
    is_open = function() return true, 1 end,
    redraw  = function() redrew = redrew + 1; return true end,
  }, { __index = function() return function() return false end end })

  package.loaded["filetree.features.ui.opened_sync"] = nil
  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-opensync",
    features = { opened_sync = { enabled = true, debounce_ms = 0 } } })

  vim.api.nvim_exec_autocmds("BufAdd", {})
  vim.wait(80, function() return redrew > 0 end, 10)
  check("opened_sync: a buffer event triggers adapter.redraw()", redrew > 0)
end

-- ── util.line_count ───────────────────────────────────────────────────────────
do
  local lc = require("filetree.util.line_count")
  check("line_count.is_countable lua", lc.is_countable("lua") == true)
  check("line_count.is_binary_ext png", lc.is_binary_ext("png") == true)
  check("line_count.count README > 0", (lc.count(root .. "/README.md", "md") or 0) > 0)
  eq("line_count.format 1", lc.format(1), "1 line")
end

-- ── util.map / util.autocmd (wrappers) ────────────────────────────────────────
do
  local map = require("filetree.util.map")
  local au  = require("filetree.util.autocmd")
  check("util.map is callable", type(map) == "function")
  local g = au.group("filetree_units_test", true)
  check("au.group returns id", type(g) == "number")
  local fired = false
  au.acmd("User", { group = g, pattern = "FiletreeUnitsPing", callback = function() fired = true end })
  vim.api.nvim_exec_autocmds("User", { pattern = "FiletreeUnitsPing" })
  check("au.acmd handler fires", fired)
  au.del_group(g)
end

-- ── util.select (adapter) ─────────────────────────────────────────────────────
do
  package.loaded["filetree.util.select"] = nil
  package.loaded["lib.nvim.ui.kit"] = { select = function(o) o.on_select(o.items[2], 2) end }
  local ui_select = require("filetree.util.select")
  local chosen
  ui_select({ "a", "b", "c" }, { prompt = "p" }, function(item, idx) chosen = { item, idx } end)
  check("select passes original item + index", chosen and chosen[1] == "b" and chosen[2] == 2)
  package.loaded["lib.nvim.ui.kit"] = nil
  package.loaded["filetree.util.select"] = nil
end

-- ── neotree adapter helpers (pure) ────────────────────────────────────────────
do
  package.loaded["neo-tree"] = { config = {} }
  local nt = dofile(root .. "/lua/filetree/adapter/neotree.lua")
  local paths, names = nt.extract_paths({
    { path = "E:/a/b.lua", name = "b.lua" },
    { name = "no-path-node" },
    { get_id = function() return "E:/c/d.lua" end },
  })
  check("extract_paths skips pathless nodes", #paths == 2)
  eq("extract_paths path 1", paths[1], "E:/a/b.lua")
  eq("extract_paths name 1", names[1], "b.lua")
  check("extract_paths resolves via get_id", paths[2] == "E:/c/d.lua")
end

-- ── cwd_sync: silently changes cwd + refreshes, never prompts ────────────────
do
  local tmp = (TMP_ROOT .. "/units-cwdsync"):gsub("\\", "/")
  vim.fn.mkdir(tmp .. "/proj/.git", "p")
  vim.fn.mkdir(tmp .. "/proj/sub", "p")
  vim.fn.writefile({ "x" }, tmp .. "/proj/sub/file.lua")
  vim.fn.chdir(tmp)  -- start OUTSIDE the project root

  local refreshed, revealed_path = false, nil
  local stub = setmetatable({
    name = "units-stub", is_available = function() return true end,
    get_winid   = function() return nil end,
    open_reveal = function(p) revealed_path = p; return true end,
    refresh     = function() refreshed = true; return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)

  local ui_input_called = false
  local orig_input = vim.ui.input
  vim.ui.input = function(...) ui_input_called = true; return orig_input(...) end

  ft.setup({ adapter = "units-stub", features = { cwd_sync = { enabled = true, debounce_ms = 0 } } })
  vim.cmd("edit " .. tmp .. "/proj/sub/file.lua")
  vim.wait(200, function() return revealed_path ~= nil end, 10)
  vim.ui.input = orig_input

  check("cwd_sync never prompts (no vim.ui.input)", not ui_input_called)
  eq("cwd_sync chdir's to the detected project root",
    vim.fn.getcwd():gsub("\\", "/"), tmp .. "/proj")
  -- cwd_sync deliberately does NOT call adapter.refresh() itself (a full
  -- filesystem rescan) -- the reveal call below re-renders the tree, so a
  -- separate rescan would be redundant work. See cwd_sync/init.lua's do_reveal.
  check("cwd_sync does not call adapter.refresh() itself", not refreshed)
  check("cwd_sync still reveals the file",
    revealed_path and revealed_path:gsub("\\", "/") == tmp .. "/proj/sub/file.lua")
end

-- ── cwd_sync: startup catch-up syncs a buffer focused BEFORE setup() ran ─────
-- Regression for: a session-restore plugin (or anything that focuses a buffer
-- very early) can leave the cwd stale with no BufEnter/WinEnter left to fire
-- for cwd_sync to react to, since the relevant buffer was already current
-- by the time setup() registered its autocmds. In this headless test process,
-- vim_did_enter is already 1 by the time the script runs, so this exercises
-- the "VimEnter already happened" branch that filetree.nvim actually hits in
-- practice (it typically loads on a lazy event well after VimEnter).
do
  local tmp = (TMP_ROOT .. "/units-cwdsync-catchup"):gsub("\\", "/")
  vim.fn.mkdir(tmp .. "/proj/.git", "p")
  vim.fn.writefile({ "x" }, tmp .. "/proj/file.lua")

  -- Focus the buffer and go to a stale cwd FIRST -- before setup() runs, so no
  -- BufEnter/WinEnter for this buffer will ever reach cwd_sync's autocmds.
  vim.cmd("edit " .. tmp .. "/proj/file.lua")
  vim.fn.chdir(tmp)

  local revealed_path
  local stub = setmetatable({
    name = "units-stub-catchup", is_available = function() return true end,
    get_winid   = function() return nil end,
    open_reveal = function(p) revealed_path = p; return true end,
    refresh     = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-catchup", features = { cwd_sync = { enabled = true, debounce_ms = 0 } } })

  vim.wait(500, function() return revealed_path ~= nil end, 10)

  eq("cwd_sync startup catch-up: chdir's to the project root with no BufEnter",
    vim.fn.getcwd():gsub("\\", "/"), tmp .. "/proj")
  check("cwd_sync startup catch-up: reveals the already-focused file",
    revealed_path and revealed_path:gsub("\\", "/") == tmp .. "/proj/file.lua")
end

-- ── neotree adapter: reveal-prompt guard ─────────────────────────────────────
-- Regression for neo-tree's own "File not in cwd. Change cwd to ...?" confirm
-- prompt (lua/neo-tree/command/init.lua's handle_reveal): it fires whenever a
-- reveal is requested (explicitly, or implicitly via
-- filesystem.follow_current_file.enabled) without an explicit `dir` and
-- without `reveal_force_cwd` set. filetree.nvim can't control every call site
-- that might trigger a reveal (a user's own custom keymaps calling neo-tree's
-- command API directly are just as much at risk as filetree's own code), so
-- install_reveal_guard() wraps neo-tree.command.execute ONCE to inject
-- reveal_force_cwd=true on any at-risk call, protecting all callers uniformly.
do
  package.loaded["neo-tree"] = { config = {}, ensure_config = function() return {} end }
  local captured = {}
  package.loaded["neo-tree.command"] = {
    execute = function(args) captured[#captured + 1] = vim.deepcopy(args); return true end,
  }
  package.loaded["neo-tree.sources.manager"] = { get_state = function() return nil end }
  package.loaded["neo-tree.setup.mapping-helper"] = { normalize_map_key = function(k) return k end }

  local ft = require("filetree")
  ft.setup({ adapter = "neotree" })

  local cmd = require("neo-tree.command")
  cmd.execute({ action = "focus", reveal = true })                       -- explicit reveal, no dir
  cmd.execute({ action = "show" })                                       -- reveal left nil (implicit-via-follow)
  cmd.execute({ action = "show", reveal = false })                       -- explicit opt-out, must stay untouched
  cmd.execute({ action = "show", dir = "E:/some/dir" })                  -- dir already given, already safe
  cmd.execute({ action = "show", reveal = true, reveal_force_cwd = false }) -- caller's explicit choice, must win

  eq("reveal guard: injects reveal_force_cwd for explicit reveal=true",
    captured[1].reveal_force_cwd, true)
  eq("reveal guard: injects reveal_force_cwd for implicit reveal (nil)",
    captured[2].reveal_force_cwd, true)
  eq("reveal guard: leaves an explicit reveal=false untouched",
    captured[3].reveal_force_cwd, nil)
  eq("reveal guard: does not inject when dir is already given",
    captured[4].reveal_force_cwd, nil)
  eq("reveal guard: respects an explicit reveal_force_cwd=false",
    captured[5].reveal_force_cwd, false)

  local before = cmd.execute
  ft.setup({ adapter = "neotree" })
  check("reveal guard: re-running setup() does not double-wrap execute",
    before == require("neo-tree.command").execute)

  package.loaded["neo-tree"] = nil
  package.loaded["neo-tree.command"] = nil
  package.loaded["neo-tree.sources.manager"] = nil
  package.loaded["neo-tree.setup.mapping-helper"] = nil
end

-- ── ignore_list: hide_by_name must be dict-shaped, not array-shaped ─────────
-- neo-tree's own filesystem.setup() converts hide_by_name from a user-facing
-- string[] into a {name=true,...} dict (utils.list_to_dict) — its render-time
-- filter (file-items.lua) only ever does f.hide_by_name[name], never iterates.
-- Appending array-style (ipairs + #+1) after that conversion silently hides
-- nothing at all, which is exactly the bug this guards against.
do
  package.loaded["neo-tree"] = { config = { filesystem = { filtered_items = {} } } }
  package.loaded["neo-tree.sources.manager"] = { _get_all_states = function() return {} end }
  package.loaded["filetree.features.infra.ignore_list"] = nil
  local il = require("filetree.features.infra.ignore_list")
  local refreshed = false
  il.setup({ enabled = true }, { name = "neotree", refresh = function() refreshed = true end })

  local fi = package.loaded["neo-tree"].config.filesystem.filtered_items
  check("ignore_list: hide_by_name is a table", type(fi.hide_by_name) == "table")
  check("ignore_list: '.git' hidden via dict lookup", fi.hide_by_name[".git"] == true)
  check("ignore_list: '.agents' hidden (from lib.nvim's list)", fi.hide_by_name[".agents"] == true)
  check("ignore_list: '.claude' hidden (from lib.nvim's list)", fi.hide_by_name[".claude"] == true)
  check("ignore_list: not array-shaped (no numeric key 1)", fi.hide_by_name[1] == nil)
  vim.wait(150, function() return refreshed end)
  check("ignore_list: adapter.refresh() called", refreshed)

  package.loaded["neo-tree"] = nil
  package.loaded["neo-tree.sources.manager"] = nil
  package.loaded["filetree.features.infra.ignore_list"] = nil
end

-- ── ignore_list: must force visible=false, even over a pre-existing true ────
-- `filtered_items.visible = true` disables the hide_by_name filter entirely
-- (neo-tree shows everything until "H" toggles it off). If the user's own
-- neo-tree opts already set visible=true for any reason, hide_by_name would
-- be correctly populated but never actually applied until a manual H press —
-- defeating this feature's documented purpose of hiding clutter by default.
do
  package.loaded["neo-tree"] = {
    config = { filesystem = { filtered_items = { visible = true } } },
  }
  package.loaded["neo-tree.sources.manager"] = { _get_all_states = function() return {} end }
  package.loaded["filetree.features.infra.ignore_list"] = nil
  local il = require("filetree.features.infra.ignore_list")
  il.setup({ enabled = true }, { name = "neotree", refresh = function() end })

  local fi = package.loaded["neo-tree"].config.filesystem.filtered_items
  check("ignore_list: visible forced to false even if pre-set true", fi.visible == false)

  package.loaded["neo-tree"] = nil
  package.loaded["neo-tree.sources.manager"] = nil
  package.loaded["filetree.features.infra.ignore_list"] = nil
end

-- ── ignore_list: predicate() feeds path-output actions (copy_file_list, ────
-- markdown_links) the same basenames this feature hides in the tree, so
-- recursive copies stop surfacing .git/node_modules/etc (see filetree.util.ignore).
do
  package.loaded["filetree.features.infra.ignore_list"] = nil
  local il = require("filetree.features.infra.ignore_list")

  check("ignore_list: predicate() ignores nothing before setup()",
    il.predicate()(".git") == false)

  il.setup({ enabled = true }, { name = "stub" })
  local pred = il.predicate()
  check("ignore_list: predicate() ignores '.git'", pred(".git") == true)
  check("ignore_list: predicate() ignores 'node_modules'", pred("node_modules") == true)
  check("ignore_list: predicate() does not ignore ordinary names", pred("src") == false)

  il.teardown()
  check("ignore_list: predicate() ignores nothing after teardown()",
    il.predicate()(".git") == false)
  package.loaded["filetree.features.infra.ignore_list"] = nil
end

-- ── copy_file_list: recursive collection skips ignored subtrees (.git) ──────
-- Regression test for the bug this predicate wiring fixes: `[f`/`]f`/`[F`/`]F`
-- used to walk fs.collect_files/collect_folders with no ignore_fn at all, so
-- .git internals ended up in the copied path list.
do
  local tmp = (TMP_ROOT .. "/units-copyfilelist"):gsub("\\", "/")
  vim.fn.mkdir(tmp .. "/.git/objects", "p")
  vim.fn.mkdir(tmp .. "/src", "p")
  vim.fn.writefile({ "x" }, tmp .. "/.git/HEAD")
  vim.fn.writefile({ "x" }, tmp .. "/src/main.lua")

  package.loaded["filetree.features.infra.ignore_list"] = nil
  local il = require("filetree.features.infra.ignore_list")
  il.setup({ enabled = true }, { name = "stub" })

  local fs = require("filetree.util.fs")
  local ignore = require("filetree.util.ignore")
  local files = fs.collect_files(tmp, ignore.predicate())

  local has_git = false
  for _, f in ipairs(files) do
    if f:find("/.git/", 1, true) then has_git = true end
  end
  check("copy_file_list: recursive collect skips .git subtree", not has_git)
  check("copy_file_list: recursive collect still finds src/main.lua",
    vim.tbl_contains(files, tmp .. "/src/main.lua"))

  il.teardown()
  package.loaded["filetree.features.infra.ignore_list"] = nil
end

-- ── find_files: via_builtin fallback skips ignored subtrees (.git) too ──────
-- Same category of bug as copy_file_list above: vim.fn.globpath expands
-- everything, so without filtering the ignore predicate the picker would
-- offer .git internals as "find files" candidates. telescope/fzf-lua/
-- mini.pick aren't on rtp in this headless harness, so M.find() falls
-- through to via_builtin exactly as it would for a real user without those
-- plugins installed.
do
  local tmp = (TMP_ROOT .. "/units-findfiles"):gsub("\\", "/")
  vim.fn.mkdir(tmp .. "/.git/objects", "p")
  vim.fn.mkdir(tmp .. "/src", "p")
  vim.fn.writefile({ "x" }, tmp .. "/.git/HEAD")
  vim.fn.writefile({ "x" }, tmp .. "/src/main.lua")

  package.loaded["filetree.features.infra.ignore_list"] = nil
  local il = require("filetree.features.infra.ignore_list")
  il.setup({ enabled = true }, { name = "stub" })

  local shown
  package.loaded["lib.nvim.ui.kit"] = {
    select = function(o) shown = o.items end,
  }
  package.loaded["filetree.util.select"] = nil
  package.loaded["filetree.features.search.find_files"] = nil
  local find_files = require("filetree.features.search.find_files")
  find_files.find(tmp)

  check("find_files: builtin fallback shown", shown ~= nil)
  local has_git = false
  for _, rel in ipairs(shown or {}) do
    if rel:find(".git/", 1, true) or rel == ".git" then has_git = true end
  end
  check("find_files: builtin fallback skips .git subtree", not has_git)
  check("find_files: builtin fallback still finds src/main.lua",
    vim.tbl_contains(shown or {}, "src/main.lua") or vim.tbl_contains(shown or {}, "src\\main.lua"))

  il.teardown()
  package.loaded["filetree.features.infra.ignore_list"] = nil
  package.loaded["lib.nvim.ui.kit"] = nil
  package.loaded["filetree.util.select"] = nil
  package.loaded["filetree.features.search.find_files"] = nil
end

-- ── copy_move: default single-char "c"/"x" cleanly override the adapter's ───
-- native "c"/"x" (exact same key, last-registration-wins -- no ambiguity).
do
  local tmp = (TMP_ROOT .. "/units-copymove"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf") -- fresh dst/ each run, so a leftover file1.txt from a
                           -- prior run doesn't look like a paste conflict here
  vim.fn.mkdir(tmp .. "/dst", "p")
  vim.fn.writefile({ "hi" }, tmp .. "/file1.txt")

  local cur_node = { path = tmp .. "/file1.txt", type = "file" }
  local stub = setmetatable({
    name = "units-stub", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    get_bufnr = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({
    adapter = "units-stub",
    features = { copy_move = { enabled = true, confirm = false, use_safety = false } },
  })

  -- unlisted+scratch (buftype=nofile), like a real neo-tree buffer -- an
  -- ordinary listed buffer with no name is indistinguishable from a stray
  -- [No Name] window, which the enabled-by-default no_name_guard feature
  -- would wipe out from under this test during the vim.wait below.
  local buf = vim.api.nvim_create_buf(false, true)
  -- Simulate the adapter's own native single-char mappings, set BEFORE
  -- filetree's FileType-driven keymaps get scheduled (mirrors real timing).
  vim.api.nvim_buf_set_keymap(buf, "n", "c", "", { callback = function() end, nowait = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "x", "", { callback = function() end, nowait = true })
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "neo-tree"
  vim.wait(200, function() return false end)

  local km = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do km[m.lhs] = m end
  check("copy_move: 'c' overridden by filetree's own stage-copy handler",
    km["c"] ~= nil and km["c"].callback ~= nil)
  check("copy_move: 'x' overridden by filetree's own stage-cut handler",
    km["x"] ~= nil and km["x"].callback ~= nil)

  local cm = ft.feature("copy_move")
  cm.stage_copy()
  cur_node = { path = tmp .. "/dst", type = "directory" }
  local captured
  local orig_notify = vim.notify
  vim.notify = function(m) captured = m end
  cm.paste()
  vim.notify = orig_notify
  check("copy_move: paste actually copies the file (shell-free vim.uv.fs_copyfile)",
    vim.fn.filereadable(tmp .. "/dst/file1.txt") == 1)
  check("copy_move: notifies 1/1 pasted, not 'Clipboard is empty'",
    captured and captured:find("1/1") ~= nil, tostring(captured))
end

-- ── copy_move: a user-configured two-char sequence (e.g. "yy"/"xx") must ────
-- still survive an adapter-native nowait single-char "y"/"x", for anyone who
-- opts back into that style via config. neo-tree's own window.mappings apply
-- a global `nowait = true`, so a native single-char "y" mapping fires
-- immediately on the first keypress, never giving Neovim a chance to wait
-- for the second character of "yy" -- copy_move must re-bind the bare prefix
-- char to a plain (non-nowait) <Nop> to restore Neovim's normal
-- ambiguous-mapping wait behaviour.
do
  local tmp = (TMP_ROOT .. "/units-copymove2"):gsub("\\", "/")
  vim.fn.mkdir(tmp, "p")

  local cur_node = { path = tmp, type = "directory" }
  local stub = setmetatable({
    name = "units-stub2", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    get_bufnr = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({
    adapter = "units-stub2",
    features = {
      copy_move = {
        enabled = true, confirm = false, use_safety = false,
        keymaps = { copy = "yy", cut = "xx", paste = "p", show = "P" },
      },
    },
  })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_keymap(buf, "n", "y", "", { callback = function() end, nowait = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "x", "", { callback = function() end, nowait = true })
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "neo-tree"
  vim.wait(200, function() return false end)

  local km = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do km[m.lhs] = m end
  check("copy_move (custom yy/xx): 'y' re-bound without nowait (unblocks 'yy')",
    km["y"] ~= nil and (km["y"].nowait == 0 or not km["y"].nowait))
  check("copy_move (custom yy/xx): 'x' re-bound without nowait (unblocks 'xx')",
    km["x"] ~= nil and (km["x"].nowait == 0 or not km["x"].nowait))
  check("copy_move (custom yy/xx): 'yy' still bound", km["yy"] ~= nil)
  check("copy_move (custom yy/xx): 'xx' still bound", km["xx"] ~= nil)
end

-- ── copy_move: cut+paste repoints the open buffer at the moved file ─────────
-- End-to-end regression for the user-reported bug: cutting a node (x) and
-- pasting (p) it into a new directory left the original buffer pointing at a
-- path that no longer existed on disk; opening the file at its new location
-- then created a second, disconnected buffer instead of reusing the original.
do
  local tmp = (TMP_ROOT .. "/units-copymove-relocate"):gsub("\\", "/")
  -- Wipe any leftover state from a previous run first: do_move() deliberately
  -- refuses to silently overwrite an existing destination, so a stale
  -- docs/filetree/filetree.md from a prior run would make this test fail for
  -- a reason that has nothing to do with the behavior under test.
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp .. "/docs", "p")
  vim.fn.writefile({ "# filetree" }, tmp .. "/docs/filetree.md")

  vim.cmd("edit " .. tmp .. "/docs/filetree.md")
  local orig_buf = vim.api.nvim_get_current_buf()

  vim.fn.mkdir(tmp .. "/docs/filetree", "p")
  local cur_node    = { path = tmp .. "/docs/filetree.md", type = "file" }
  local target_node = { path = tmp .. "/docs/filetree",    type = "directory" }
  local stub = setmetatable({
    name = "units-stub7", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub7",
    features = { copy_move = { enabled = true, confirm = false, use_safety = false } } })

  local copy_move = ft.feature("copy_move")
  copy_move.stage_cut()
  stub.get_current_node = function() return target_node end -- cursor now on the new dir
  copy_move.paste()

  eq("copy_move relocate: original path no longer readable",
    vim.fn.filereadable(tmp .. "/docs/filetree.md"), 0)
  eq("copy_move relocate: file exists at the new path",
    vim.fn.filereadable(tmp .. "/docs/filetree/filetree.md"), 1)
  eq("copy_move relocate: original buffer repointed to the new path",
    vim.api.nvim_buf_get_name(orig_buf):gsub("\\", "/"), tmp .. "/docs/filetree/filetree.md")

  local bufcount_before = #vim.api.nvim_list_bufs()
  vim.cmd("edit " .. tmp .. "/docs/filetree/filetree.md")
  check("copy_move relocate: opening the new-location file reuses the original buffer (no duplicate)",
    vim.api.nvim_get_current_buf() == orig_buf
      and #vim.api.nvim_list_bufs() == bufcount_before)
end

-- ── copy_move: markdown.nvim soft-dep -- cut updates refs, copy leaves them ─
do
  local tmp = (TMP_ROOT .. "/units-copymove-mdrefs"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp .. "/dst", "p")
  local cut_src   = tmp .. "/cut.md"
  local cut_dst   = tmp .. "/dst/cut.md"
  local copy_src  = tmp .. "/copy.md"
  local copy_dst  = tmp .. "/dst/copy.md"
  local linker    = tmp .. "/linker.md"
  vim.fn.writefile({ "# Cut" },  cut_src)
  vim.fn.writefile({ "# Copy" }, copy_src)
  vim.fn.writefile({ "Refs: [cut](cut.md) and [copy](copy.md)." }, linker)

  package.loaded["filetree.util.confirm_choice"] = function(_question, choices, on_choice)
    on_choice(choices[1]) -- "Update all refs"
  end
  local function cm_refs(target_path)
    if target_path == cut_src then
      return { { file = linker, line = 1, target = "cut.md", display = "[cut](cut.md)" } }
    end
    return {} -- copy_src is never queried by a correct implementation, but
              -- return {} regardless so a wrong one doesn't false-positive.
  end
  package.loaded["markdown_nvim"] = {
    find_references       = function(tp, _o) return cm_refs(tp) end,
    find_references_async = function(tp, _o, cb) cb(cm_refs(tp)) end,
  }
  package.loaded["filetree.features.fileops.copy_move"] = nil -- reload with stubs

  local cur_node = { path = tmp .. "/dst", type = "directory" }
  local stub = setmetatable({
    name = "units-stub-copymove-mdrefs", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    get_bufnr = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-copymove-mdrefs",
    features = { copy_move = { enabled = true, confirm = false, use_safety = false } } })

  local cm = ft.feature("copy_move")

  -- Cut cut.md, paste into dst/ -> its reference must be updated.
  cur_node = { path = cut_src, type = "file" }
  cm.stage_cut()
  cur_node = { path = tmp .. "/dst", type = "directory" }
  cm.paste()
  eq("copy_move+mdrefs: cut file moved", vim.fn.filereadable(cut_dst), 1)

  -- Copy copy.md, paste into dst/ -> the original stays put, no ref check needed.
  cur_node = { path = copy_src, type = "file" }
  cm.stage_copy()
  cur_node = { path = tmp .. "/dst", type = "directory" }
  cm.paste()
  eq("copy_move+mdrefs: copied file duplicated, original untouched", vim.fn.filereadable(copy_src), 1)
  eq("copy_move+mdrefs: copy landed at destination too", vim.fn.filereadable(copy_dst), 1)

  local linker_lines = vim.fn.readfile(linker)
  check("copy_move+mdrefs: cut reference rewritten to the new (dst/) path",
    linker_lines[1]:find("dst/cut.md", 1, true) ~= nil, linker_lines[1])
  check("copy_move+mdrefs: copy reference left exactly as-is (original still valid)",
    linker_lines[1]:find("](copy.md)", 1, true) ~= nil, linker_lines[1])

  package.loaded["filetree.util.confirm_choice"] = nil
  package.loaded["markdown_nvim"] = nil
  package.loaded["filetree.features.fileops.copy_move"] = nil
end

-- ── trash: delete_current binds d/U/<leader>th and trashes the right node ───
do
  local tmp = (TMP_ROOT .. "/units-trash"):gsub("\\", "/")
  vim.fn.mkdir(tmp, "p")
  vim.fn.writefile({ "x" }, tmp .. "/victim.txt")

  local cur_node = { path = tmp .. "/victim.txt", type = "file" }
  local stub = setmetatable({
    name = "units-stub3", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({
    adapter = "units-stub3",
    features = { trash = { enabled = true, confirm = false, dry_run = true } },
  })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "neo-tree"
  vim.wait(200, function() return false end)

  -- "<leader>" is substituted with the current mapleader (default "\") at
  -- map-registration time, so nvim_buf_get_keymap reports the already-expanded
  -- lhs, not the literal "<leader>..." string.
  local leader = vim.g.mapleader or "\\"
  local km = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do km[m.lhs] = m end
  check("trash: 'd' bound",          km["d"] ~= nil)
  check("trash: 'U' bound",          km["U"] ~= nil)
  check("trash: '<leader>th' bound", km[leader .. "th"] ~= nil)

  local trash = ft.feature("trash")
  -- delete_current() now emits more than one message for a batch (the per-item
  -- dry-run line + a single summary), so accumulate them all rather than only
  -- keeping the last one.
  local messages = {}
  local orig_notify = vim.notify
  vim.notify = function(m) messages[#messages + 1] = m end
  trash.delete_current()
  vim.notify = orig_notify
  local joined = table.concat(messages, "\n")
  check("trash: delete_current() (dry-run) targets the current node",
    joined:find("victim.txt", 1, true) ~= nil, joined)
end

-- ── trash: single delete closes the file's open buffer ──────────────────────
-- Deleting a file must force-close any buffer still open for it, so a stale
-- buffer doesn't linger pointing at a now-deleted path. Uses a stubbed trash
-- backend (removes the file from disk, no real Recycle Bin side effects).
do
  local tmp = (TMP_ROOT .. "/units-trash-bufclose"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local file = tmp .. "/doomed.txt"
  vim.fn.writefile({ "x" }, file)

  -- Stub the platform so no real trash happens; it just deletes on disk.
  package.loaded["filetree.features.fileops.trash.platform"] = {
    available = function() return true end,
    send = function(p) os.remove(p); return { ok = true } end,
  }
  package.loaded["filetree.features.fileops.trash"] = nil -- reload with the stub

  vim.cmd("edit " .. vim.fn.fnameescape(file))
  local doomed_buf = vim.api.nvim_get_current_buf()

  local cur_node = { path = file, type = "file" }
  local stub = setmetatable({
    name = "units-stub-bufclose", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  -- confirm = false → single item deletes straight away (no y/N to drive).
  ft.setup({ adapter = "units-stub-bufclose",
    features = { trash = { enabled = true, confirm = false } } })

  ft.feature("trash").delete_current()

  eq("trash: single delete removes the file", vim.fn.filereadable(file), 0)
  check("trash: single delete force-closes the file's buffer",
    not vim.api.nvim_buf_is_valid(doomed_buf) or vim.api.nvim_buf_get_name(doomed_buf) == "")

  package.loaded["filetree.features.fileops.trash.platform"] = nil
  package.loaded["filetree.features.fileops.trash"] = nil
end

-- ── trash: multi-mark batch chooser deletes all + clears marks ──────────────
-- With >1 item, delete_current() shows ONE chooser (hover_select) instead of
-- prompting per file. Stub the chooser to pick "Delete all at once" and stub
-- the marks feature to report two marked paths; verify both are trashed, both
-- buffers closed, and marks cleared once.
do
  local tmp = (TMP_ROOT .. "/units-trash-batch"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local a, b = tmp .. "/a.txt", tmp .. "/b.txt"
  vim.fn.writefile({ "a" }, a)
  vim.fn.writefile({ "b" }, b)

  package.loaded["filetree.features.fileops.trash.platform"] = {
    available = function() return true end,
    send = function(p) os.remove(p); return { ok = true } end,
  }
  -- Auto-drive the batch chooser: always pick option 1 ("Delete all at once").
  package.loaded["filetree.util.confirm_choice"] = function(_question, choices, on_choice)
    on_choice(choices[1])
  end
  -- Stub marks: report a + b as marked, track that clear_all was called.
  local cleared = false
  package.loaded["filetree.features.org.marks"] = {
    setup = function() end, teardown = function() end,
    count = function() return 2 end,
    get_marked = function() return { a, b } end,
    clear_all = function() cleared = true end,
  }
  package.loaded["filetree.features.fileops.trash"] = nil -- reload with stubs

  vim.cmd("edit " .. vim.fn.fnameescape(a))
  local buf_a = vim.api.nvim_get_current_buf()
  vim.cmd("edit " .. vim.fn.fnameescape(b))
  local buf_b = vim.api.nvim_get_current_buf()

  local stub = setmetatable({
    name = "units-stub-batch", is_available = function() return true end,
    get_current_node = function() return nil end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-batch",
    features = { trash = { enabled = true, confirm = true } } })

  ft.feature("trash").delete_current()

  eq("trash batch: file a removed", vim.fn.filereadable(a), 0)
  eq("trash batch: file b removed", vim.fn.filereadable(b), 0)
  check("trash batch: buffer a closed",
    not vim.api.nvim_buf_is_valid(buf_a) or vim.api.nvim_buf_get_name(buf_a) == "")
  check("trash batch: buffer b closed",
    not vim.api.nvim_buf_is_valid(buf_b) or vim.api.nvim_buf_get_name(buf_b) == "")
  check("trash batch: marks cleared after successful delete", cleared)

  package.loaded["filetree.features.fileops.trash.platform"] = nil
  package.loaded["filetree.util.confirm_choice"] = nil
  package.loaded["filetree.features.org.marks"] = nil
  package.loaded["filetree.features.fileops.trash"] = nil
end

-- ── markdown_refs.update: patches a LIVE buffer, not just the file on disk ───
-- Regression: writefile() alone doesn't reload an open buffer (only a later
-- checktime/autoread does — hence "switch away and back" was needed). update()
-- must patch the open buffer directly and, when it had no unsaved changes,
-- persist + keep it unmodified.
do
  local refs_util = require("filetree.util.markdown_refs")
  local tmp = (TMP_ROOT .. "/units-mdrefs-livebuf"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")

  -- Case 1: referencing file OPEN in an unmodified buffer.
  local open_file = tmp .. "/open.md"
  vim.fn.writefile({ "intro", "See [x](old.md) here.", "outro" }, open_file)
  vim.cmd("edit " .. vim.fn.fnameescape(open_file))
  local buf = vim.api.nvim_get_current_buf()

  refs_util.update({
    { file = open_file, line = 2, target = "old.md", display = "[x](old.md)", new_target = "new.md" },
  })

  local buf_line2 = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
  check("mdrefs.update: open buffer patched live (no reload needed)",
    buf_line2 == "See [x](new.md) here.", buf_line2)
  check("mdrefs.update: buffer left unmodified (change persisted to disk)",
    vim.bo[buf].modified == false)
  local disk = vim.fn.readfile(open_file)
  check("mdrefs.update: disk also updated for the open+unmodified buffer",
    disk[2] == "See [x](new.md) here.", disk[2])

  -- Case 2: referencing file NOT open anywhere -> disk edit as before.
  local closed_file = tmp .. "/closed.md"
  vim.fn.writefile({ "[y](old.md)" }, closed_file)
  refs_util.update({
    { file = closed_file, line = 1, target = "old.md", display = "[y](old.md)", new_target = "new.md" },
  })
  check("mdrefs.update: closed file edited on disk",
    vim.fn.readfile(closed_file)[1] == "[y](new.md)")

  -- Case 3: open buffer WITH unsaved changes -> patched live, left modified,
  -- disk NOT written (user's edits win on their own save).
  local dirty_file = tmp .. "/dirty.md"
  vim.fn.writefile({ "[z](old.md)" }, dirty_file)
  vim.cmd("edit " .. vim.fn.fnameescape(dirty_file))
  local dbuf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(dbuf, 1, 1, false, { "unsaved tail" }) -- make it modified
  refs_util.update({
    { file = dirty_file, line = 1, target = "old.md", display = "[z](old.md)", new_target = "new.md" },
  })
  check("mdrefs.update: dirty buffer patched live",
    vim.api.nvim_buf_get_lines(dbuf, 0, 1, false)[1] == "[z](new.md)")
  check("mdrefs.update: dirty buffer stays modified (not force-saved)",
    vim.bo[dbuf].modified == true)
  check("mdrefs.update: disk left untouched while buffer is dirty",
    vim.fn.readfile(dirty_file)[1] == "[z](old.md)")

  -- cleanup buffers
  pcall(vim.api.nvim_buf_delete, buf,  { force = true })
  pcall(vim.api.nvim_buf_delete, dbuf, { force = true })
end

-- ── trash: markdown.nvim soft-dep — reference chooser + cleanup ─────────────
-- When markdown.nvim is present and reports references to the file being
-- trashed, delete_current() must show the 3-way chooser (not the plain y/N
-- popup) and, on "delete + remove references", rewrite the reporting line's
-- link target to "REF!" in the referencing file.
do
  local tmp = (TMP_ROOT .. "/units-trash-mdrefs"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local victim  = tmp .. "/victim.md"
  local linker  = tmp .. "/linker.md"
  vim.fn.writefile({ "# Victim" }, victim)
  vim.fn.writefile({ "intro", "See [victim](victim.md) here.", "outro" }, linker)

  package.loaded["filetree.features.fileops.trash.platform"] = {
    available = function() return true end,
    send = function(p) os.remove(p); return { ok = true } end,
  }
  -- Auto-drive the chooser: always pick option 1 ("Delete + remove refs").
  local select_prompt = nil
  package.loaded["filetree.util.confirm_choice"] = function(question, choices, on_choice)
    select_prompt = question
    on_choice(choices[1])
  end
  package.loaded["markdown_nvim"] = {
    find_references = function(target_path, _opts)
      if target_path == victim then
        return { { file = linker, line = 2, target = "victim.md", display = "[victim](victim.md)" } }
      end
      return {}
    end,
  }
  package.loaded["filetree.features.fileops.trash"] = nil -- reload with stubs

  local cur_node = { path = victim, type = "file" }
  local stub = setmetatable({
    name = "units-stub-mdrefs", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-mdrefs",
    features = { trash = { enabled = true, confirm = true } } })

  ft.feature("trash").delete_current()

  check("trash+mdrefs: markdown reference triggers the chooser, not the plain y/N popup",
    select_prompt ~= nil and select_prompt:find("ref", 1, true) ~= nil, tostring(select_prompt))
  eq("trash+mdrefs: victim file removed", vim.fn.filereadable(victim), 0)
  local linker_lines = vim.fn.readfile(linker)
  check("trash+mdrefs: referencing line rewritten to REF!",
    linker_lines[2] == "See [victim](REF!) here.", linker_lines[2])
  check("trash+mdrefs: unrelated lines untouched",
    linker_lines[1] == "intro" and linker_lines[3] == "outro")

  package.loaded["filetree.features.fileops.trash.platform"] = nil
  package.loaded["filetree.util.confirm_choice"] = nil
  package.loaded["markdown_nvim"] = nil
  package.loaded["filetree.features.fileops.trash"] = nil
end

-- ── trash: "Inspect references" (idx 2) -> quickfix picker -> partial cleanup ─
-- End-to-end through the real chooser: pick "Inspect references first", the
-- quickfix fallback opens (no telescope/fzf-lua stubbed), prune one entry the
-- same way a user would (delete a line), confirm via the picker's own public
-- API, and verify only the surviving reference got cleaned up.
do
  local tmp = (TMP_ROOT .. "/units-trash-mdrefs-inspect"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local victim  = tmp .. "/victim.md"
  local linker  = tmp .. "/linker.md"
  vim.fn.writefile({ "# Victim" }, victim)
  vim.fn.writefile({
    "See [victim](victim.md) here.",
    "Again: [victim](victim.md) there.",
  }, linker)

  package.loaded["filetree.features.fileops.trash.platform"] = {
    available = function() return true end,
    send = function(p) os.remove(p); return { ok = true } end,
  }
  -- Auto-drive the chooser: always pick option 2 ("Inspect first").
  package.loaded["filetree.util.confirm_choice"] = function(_question, choices, on_choice)
    on_choice(choices[2])
  end
  package.loaded["markdown_nvim"] = {
    find_references = function(target_path, _opts)
      if target_path == victim then
        return {
          { file = linker, line = 1, target = "victim.md", display = "[victim](victim.md)" },
          { file = linker, line = 2, target = "victim.md", display = "[victim](victim.md)" },
        }
      end
      return {}
    end,
  }
  package.loaded["filetree.features.fileops.trash"] = nil -- reload with stubs

  local cur_node = { path = victim, type = "file" }
  local stub = setmetatable({
    name = "units-stub-mdrefs-inspect", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-mdrefs-inspect",
    features = { trash = { enabled = true, confirm = true, refs_picker_prefer = "quickfix" } } })

  ft.feature("trash").delete_current()

  -- The quickfix picker is now open awaiting user pruning; simulate keeping
  -- only line 1's reference (drop the line-2 duplicate) and confirming.
  local qf = vim.fn.getqflist()
  check("trash+inspect: quickfix populated with both references", #qf == 2)
  vim.fn.setqflist({}, "r", { items = { qf[1] } })
  require("filetree.util.refs_picker").qf_confirm()

  eq("trash+inspect: victim file removed", vim.fn.filereadable(victim), 0)
  local linker_lines = vim.fn.readfile(linker)
  check("trash+inspect: kept reference (line 1) was cleaned up",
    linker_lines[1] == "See [victim](REF!) here.", linker_lines[1])
  check("trash+inspect: pruned reference (line 2) was left untouched",
    linker_lines[2] == "Again: [victim](victim.md) there.", linker_lines[2])

  package.loaded["filetree.features.fileops.trash.platform"] = nil
  package.loaded["filetree.util.confirm_choice"] = nil
  package.loaded["markdown_nvim"] = nil
  package.loaded["filetree.features.fileops.trash"] = nil
end

-- ── smart_rename: markdown.nvim soft-dep -> update refs to the new path ─────
-- Same soft-dep + chooser pattern as trash, but post-rename (no "cancel" --
-- the rename already happened) and the "update all" path rewrites to the new
-- cwd-relative path rather than a "REF!" marker.
do
  local tmp = (TMP_ROOT .. "/units-smartrename-mdrefs"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local old_path = tmp .. "/old.md"
  local new_path = tmp .. "/renamed.md"
  local linker   = tmp .. "/linker.md"
  vim.fn.writefile({ "# Old" }, old_path)
  vim.fn.writefile({ "See [old](old.md) here." }, linker)

  -- Auto-drive the "Rename to:" prompt and the resulting chooser.
  package.loaded["lib.nvim.ui.kit"] = {
    input = function(opts) opts.on_submit("renamed.md") end,
  }
  package.loaded["filetree.util.confirm_choice"] = function(_question, choices, on_choice)
    on_choice(choices[1]) -- "Update all refs"
  end
  local function sr_refs(target_path)
    if target_path == old_path then
      return { { file = linker, line = 1, target = "old.md", display = "[old](old.md)" } }
    end
    return {}
  end
  package.loaded["markdown_nvim"] = {
    find_references       = function(tp, _o) return sr_refs(tp) end,
    find_references_async = function(tp, _o, cb) cb(sr_refs(tp)) end,
    -- retarget left unstubbed on purpose: refs_util.retarget falls back to a
    -- cwd-relative path, which still contains the new basename the test checks.
  }
  package.loaded["filetree.features.fileops.smart_rename"] = nil -- reload with stubs

  local cur_node = { path = old_path, type = "file" }
  local stub = setmetatable({
    name = "units-stub-smartrename", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-smartrename",
    features = { smart_rename = { enabled = true, use_safety = false, update_references = false } } })

  ft.feature("smart_rename").rename_current()
  vim.wait(500, function() return vim.fn.filereadable(new_path) == 1 end)

  eq("smart_rename+mdrefs: file renamed on disk", vim.fn.filereadable(new_path), 1)
  local linker_lines = vim.fn.readfile(linker)
  check("smart_rename+mdrefs: reference rewritten to the cwd-relative new path",
    linker_lines[1]:find("](", 1, true) ~= nil and linker_lines[1]:find(vim.fn.fnamemodify(new_path, ":t"), 1, true) ~= nil,
    linker_lines[1])
  check("smart_rename+mdrefs: old target string no longer present",
    linker_lines[1]:find("old.md", 1, true) == nil, linker_lines[1])

  package.loaded["lib.nvim.ui.kit"] = nil
  package.loaded["filetree.util.confirm_choice"] = nil
  package.loaded["markdown_nvim"] = nil
  package.loaded["filetree.features.fileops.smart_rename"] = nil
end

-- ── rename_batch: markdown.nvim soft-dep -> aggregated across the batch ─────
-- Two renamed files, each referenced from markdown; verify refs from BOTH
-- land in one aggregated chooser and each gets its own correct new target.
do
  local tmp = (TMP_ROOT .. "/units-renamebatch-mdrefs"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local a_old, a_new = tmp .. "/a.md", tmp .. "/a2.md"
  local b_old, b_new = tmp .. "/b.md", tmp .. "/b2.md"
  local linker = tmp .. "/linker.md"
  vim.fn.writefile({ "# A" }, a_old)
  vim.fn.writefile({ "# B" }, b_old)
  vim.fn.writefile({ "See [a](a.md) and [b](b.md) here." }, linker)

  package.loaded["filetree.util.confirm_choice"] = function(_question, choices, on_choice)
    on_choice(choices[1]) -- "Update all refs"
  end
  local function rb_refs(target_path)
    if target_path == a_old then
      return { { file = linker, line = 1, target = "a.md", display = "[a](a.md)" } }
    elseif target_path == b_old then
      return { { file = linker, line = 1, target = "b.md", display = "[b](b.md)" } }
    end
    return {}
  end
  package.loaded["markdown_nvim"] = {
    find_references       = function(tp, _o) return rb_refs(tp) end,
    find_references_async = function(tp, _o, cb) cb(rb_refs(tp)) end,
  }
  package.loaded["filetree.features.fileops.rename_batch"] = nil -- reload with stubs

  local nodes = {
    { path = a_old, type = "file" },
    { path = b_old, type = "file" },
  }
  local stub = setmetatable({
    name = "units-stub-renamebatch", is_available = function() return true end,
    get_visible_nodes = function() return nodes end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-renamebatch",
    features = { rename_batch = { enabled = true, use_safety = false } } })

  ft.feature("rename_batch").open()
  local rb_buf = vim.api.nvim_get_current_buf()
  -- Lines: header, blank, then one name per node (see M.open()'s 2-line offset).
  vim.api.nvim_buf_set_lines(rb_buf, 2, 4, false, { "a2.md", "b2.md" })
  vim.cmd("write")

  eq("rename_batch+mdrefs: a.md renamed", vim.fn.filereadable(a_new), 1)
  eq("rename_batch+mdrefs: b.md renamed", vim.fn.filereadable(b_new), 1)
  local linker_lines = vim.fn.readfile(linker)
  check("rename_batch+mdrefs: both references updated to their own new paths",
    linker_lines[1]:find("a2.md", 1, true) ~= nil and linker_lines[1]:find("b2.md", 1, true) ~= nil,
    linker_lines[1])

  package.loaded["filetree.util.confirm_choice"] = nil
  package.loaded["markdown_nvim"] = nil
  package.loaded["filetree.features.fileops.rename_batch"] = nil
end

-- ── smart_rename: renaming onto an existing path asks confirm_choice ───────
-- Regression for the kit.confirm migration (Overwrite/Cancel used to be a
-- vim.ui.select list): the chooser must offer exactly Overwrite/Cancel, and
-- picking Cancel must leave both files untouched.
do
  local tmp = (TMP_ROOT .. "/units-smartrename-overwrite"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local old_path      = tmp .. "/old.txt"
  local existing_path = tmp .. "/existing.txt"
  vim.fn.writefile({ "old" }, old_path)
  vim.fn.writefile({ "existing" }, existing_path)

  package.loaded["lib.nvim.ui.kit"] = {
    input = function(opts) opts.on_submit("existing.txt") end,
  }

  local captured_question, captured_choices
  package.loaded["filetree.util.confirm_choice"] = function(question, choices, on_choice)
    captured_question, captured_choices = question, choices
    on_choice("Cancel")
  end
  package.loaded["filetree.features.fileops.smart_rename"] = nil -- reload with stub

  local cur_node = { path = old_path, type = "file" }
  local stub = setmetatable({
    name = "units-stub-smartrename-overwrite", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-smartrename-overwrite",
    features = { smart_rename = { enabled = true, use_safety = false } } })

  ft.feature("smart_rename").rename_current()

  check("smart_rename overwrite: confirm_choice asked with Overwrite/Cancel",
    captured_choices ~= nil and captured_choices[1] == "Overwrite" and captured_choices[2] == "Cancel",
    vim.inspect(captured_choices))
  check("smart_rename overwrite: question mentions the existing name",
    captured_question ~= nil and captured_question:find("existing.txt", 1, true) ~= nil, tostring(captured_question))
  check("smart_rename overwrite: Cancel leaves the old file in place",
    vim.fn.filereadable(old_path) == 1, "old file should still exist")

  package.loaded["lib.nvim.ui.kit"] = nil
  package.loaded["filetree.util.confirm_choice"] = nil
  package.loaded["filetree.features.fileops.smart_rename"] = nil
end

-- ── smart_create: non-empty clipboard asks confirm_choice (Empty/Paste) ─────
-- Regression for the kit.confirm migration (used to be a vim.ui.select list).
-- Skipped without a working clipboard provider (see HAS_CLIPBOARD above): the
-- whole scenario hinges on `getreg("+")` actually returning what was set.
if HAS_CLIPBOARD then
  local tmp = (TMP_ROOT .. "/units-smartcreate-paste"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  vim.fn.chdir(tmp)
  vim.fn.setreg("+", "clip content")

  package.loaded["lib.nvim.ui.kit"] = {
    input = function(opts) opts.on_submit("new.txt") end,
  }

  local captured_question, captured_choices
  package.loaded["filetree.util.confirm_choice"] = function(question, choices, on_choice)
    captured_question, captured_choices = question, choices
    on_choice("Paste clipboard")
  end
  package.loaded["filetree.features.fileops.smart_create"] = nil -- reload with stub

  local cur_node = { path = tmp, type = "directory" }
  local stub = setmetatable({
    name = "units-stub-smartcreate", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-smartcreate",
    features = { smart_create = { enabled = true, ask_clipboard = true } } })

  ft.feature("smart_create").create()

  check("smart_create paste: confirm_choice asked with Empty/Paste clipboard",
    captured_choices ~= nil and captured_choices[1] == "Empty" and captured_choices[2] == "Paste clipboard",
    vim.inspect(captured_choices))
  check("smart_create paste: question mentions the new file name",
    captured_question ~= nil and captured_question:find("new.txt", 1, true) ~= nil, tostring(captured_question))
  check("smart_create paste: file created with clipboard content",
    vim.fn.filereadable(tmp .. "/new.txt") == 1
      and table.concat(vim.fn.readfile(tmp .. "/new.txt"), "\n"):find("clip content", 1, true) ~= nil)

  package.loaded["lib.nvim.ui.kit"] = nil
  package.loaded["filetree.util.confirm_choice"] = nil
  package.loaded["filetree.features.fileops.smart_create"] = nil
end

-- ── link_create: file target asks Symlink/Hardlink, creates a real hardlink ──
-- The link is created in the CURRENT NODE's directory, which must be
-- different from the target's own directory or "same path" would collide
-- with the existence guard before creation is ever attempted.
do
  local tmp = (TMP_ROOT .. "/units-linkcreate-file"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp .. "/src", "p")
  vim.fn.mkdir(tmp .. "/dest", "p")
  local target = tmp .. "/src/target.txt"
  vim.fn.writefile({ "hello link" }, target)

  package.loaded["lib.nvim.ui.kit"] = {
    input = function(opts) opts.on_submit(target) end,
  }
  local captured_question, captured_choices
  package.loaded["filetree.util.confirm_choice"] = function(question, choices, on_choice)
    captured_question, captured_choices = question, choices
    on_choice("Hardlink")
  end
  package.loaded["filetree.features.fileops.link_create"] = nil -- reload with stub

  local cur_node = { path = tmp .. "/dest", type = "directory" }
  local stub = setmetatable({
    name = "units-stub-linkcreate-file", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-linkcreate-file",
    features = { link_create = { enabled = true } } })

  ft.feature("link_create").create()

  check("link_create file target: confirm_choice asked with Symlink/Hardlink",
    captured_choices ~= nil and captured_choices[1] == "Symlink" and captured_choices[2] == "Hardlink",
    vim.inspect(captured_choices))
  check("link_create file target: question mentions the link's name",
    captured_question ~= nil and captured_question:find("target.txt", 1, true) ~= nil,
    tostring(captured_question))
  check("link_create file target: hardlink created in dest/, with matching content",
    vim.fn.filereadable(tmp .. "/dest/target.txt") == 1
      and table.concat(vim.fn.readfile(tmp .. "/dest/target.txt"), "\n") == "hello link")

  package.loaded["lib.nvim.ui.kit"] = nil
  package.loaded["filetree.util.confirm_choice"] = nil
  package.loaded["filetree.features.fileops.link_create"] = nil
end

-- ── link_create: directory target skips the chooser (symlink only) ──────────
-- Windows symlink creation needs Developer Mode or an elevated process;
-- assert the no-chooser behavior unconditionally, but only assert the link
-- itself exists when creation actually succeeded (see mutate_spec.lua for the
-- same accommodation).
do
  local tmp = (TMP_ROOT .. "/units-linkcreate-dir"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp .. "/src/target_dir", "p")
  vim.fn.mkdir(tmp .. "/dest", "p")
  local target = tmp .. "/src/target_dir"

  package.loaded["lib.nvim.ui.kit"] = {
    input = function(opts) opts.on_submit(target) end,
  }
  local confirm_choice_called = false
  package.loaded["filetree.util.confirm_choice"] = function(_, _, on_choice)
    confirm_choice_called = true
    on_choice("Symlink")
  end
  package.loaded["filetree.features.fileops.link_create"] = nil -- reload with stub

  local cur_node = { path = tmp .. "/dest", type = "directory" }
  local stub = setmetatable({
    name = "units-stub-linkcreate-dir", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-linkcreate-dir",
    features = { link_create = { enabled = true } } })

  ft.feature("link_create").create()

  check("link_create dir target: no Symlink/Hardlink chooser (directories can't be hardlinked)",
    not confirm_choice_called)
  local link_stat = (vim.uv or vim.loop).fs_lstat(tmp .. "/dest/target_dir")
  if not link_stat then
    print("  note link_create: directory symlink not created in this environment (needs elevation on Windows)")
  else
    check("link_create dir target: symlink created", link_stat.type == "link")
  end

  package.loaded["lib.nvim.ui.kit"] = nil
  package.loaded["filetree.util.confirm_choice"] = nil
  package.loaded["filetree.features.fileops.link_create"] = nil
end

-- ── rename_batch: confirm=true asks kit.confirm (async), not the old ────────
-- blocking `vim.fn.input("...[y/N]...")` freetext prompt.
do
  local tmp = (TMP_ROOT .. "/units-renamebatch-confirm"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local a_old, a_new = tmp .. "/a.txt", tmp .. "/a2.txt"
  vim.fn.writefile({ "a" }, a_old)

  local captured_question
  package.loaded["filetree.util.confirm"] = function(opts)
    captured_question = opts.question
    opts.on_choice(true) -- confirm the rename
  end
  package.loaded["filetree.features.fileops.rename_batch"] = nil -- reload with stub

  local nodes = { { path = a_old, type = "file" } }
  local stub = setmetatable({
    name = "units-stub-renamebatch-confirm", is_available = function() return true end,
    get_visible_nodes = function() return nodes end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-renamebatch-confirm",
    features = { rename_batch = { enabled = true, use_safety = false, confirm = true } } })

  ft.feature("rename_batch").open()
  local rb_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(rb_buf, 2, 3, false, { "a2.txt" })
  vim.cmd("write")

  check("rename_batch confirm: util.confirm asked instead of vim.fn.input",
    captured_question ~= nil, tostring(captured_question))
  eq("rename_batch confirm: renamed on disk after Yes", vim.fn.filereadable(a_new), 1)

  package.loaded["filetree.util.confirm"] = nil
  package.loaded["filetree.features.fileops.rename_batch"] = nil
end

-- ── copy_move: paste confirm=true asks kit.confirm (async); Cancel pastes ───
-- nothing. Regression for the old blocking `vim.fn.input("...[y/N]...")`.
do
  local tmp = (TMP_ROOT .. "/units-copymove-confirm"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp .. "/dst", "p")
  vim.fn.writefile({ "hi" }, tmp .. "/file1.txt")

  local captured_question
  package.loaded["filetree.util.confirm"] = function(opts)
    captured_question = opts.question
    opts.on_choice(false) -- Cancel
  end
  package.loaded["filetree.features.fileops.copy_move"] = nil -- reload with stub

  local cur_node = { path = tmp .. "/file1.txt", type = "file" }
  local stub = setmetatable({
    name = "units-stub-copymove-confirm", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    get_bufnr = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-copymove-confirm",
    features = { copy_move = { enabled = true, confirm = true, use_safety = false } } })

  local cm = ft.feature("copy_move")
  cm.stage_copy()
  cur_node = { path = tmp .. "/dst", type = "directory" }
  cm.paste()

  check("copy_move confirm: util.confirm asked instead of vim.fn.input",
    captured_question ~= nil, tostring(captured_question))
  check("copy_move confirm: Cancel means nothing was pasted",
    vim.fn.filereadable(tmp .. "/dst/file1.txt") == 0)

  package.loaded["filetree.util.confirm"] = nil
  package.loaded["filetree.features.fileops.copy_move"] = nil
end

-- ── create_from_template: overwrite asks kit.confirm, Cancel keeps original ─
-- Regression for the old blocking `vim.fn.input("...Overwrite? [y/N] ")`.
do
  local tmp = (TMP_ROOT .. "/units-cft-overwrite"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local tdir = tmp .. "/templates"
  vim.fn.mkdir(tdir, "p")
  vim.fn.writefile({ "content" }, tdir .. "/basic.lua")

  local dest_dir = tmp .. "/dest"
  vim.fn.mkdir(dest_dir, "p")
  vim.fn.writefile({ "existing" }, dest_dir .. "/new.lua")

  package.loaded["lib.nvim.ui.kit"] = {
    select = function(o) o.on_select(o.items[1], 1) end, -- pick template 1
    input = function(opts) opts.on_submit("new.lua") end,
  }

  local captured_question
  package.loaded["filetree.util.confirm"] = function(opts)
    captured_question = opts.question
    opts.on_choice(false) -- Cancel: do not overwrite
  end
  package.loaded["filetree.util.select"] = nil -- reload so it picks up the stubbed kit
  package.loaded["filetree.features.fileops.create_from_template"] = nil -- reload with stub

  local stub = setmetatable({
    name = "units-stub-cft", is_available = function() return true end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-cft",
    features = { create_from_template = { enabled = true, template_dir = tdir } } })

  local cft = ft.feature("create_from_template")
  cft.open(dest_dir) -- picker resolves synchronously via the stubbed kit.select above

  check("create_from_template overwrite: util.confirm asked instead of vim.fn.input",
    captured_question ~= nil, tostring(captured_question))
  check("create_from_template overwrite: Cancel leaves existing content untouched",
    vim.fn.readfile(dest_dir .. "/new.lua")[1] == "existing")

  package.loaded["lib.nvim.ui.kit"] = nil
  package.loaded["filetree.util.confirm"] = nil
  package.loaded["filetree.util.select"] = nil
  package.loaded["filetree.features.fileops.create_from_template"] = nil
end

-- ── create_from_template: pickers.nvim dispatch (prefer, Pickers.Item) ──────
do
  local tmp = (TMP_ROOT .. "/units-cft-pickers"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local tdir = tmp .. "/templates"
  vim.fn.mkdir(tdir, "p")
  vim.fn.writefile({ "content" }, tdir .. "/basic.lua")

  local dest_dir = tmp .. "/dest"
  vim.fn.mkdir(dest_dir, "p")

  local stub = setmetatable({
    name = "units-stub-cft-pickers", is_available = function() return true end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  -- prefer = "auto" (default): dispatches through pickers.engines.load(),
  -- items carry {text, file, tmpl} and on_select unwraps .tmpl.
  do
    local captured_prefer, captured_items
    package.loaded["pickers.engines"] = {
      load = function(prefer)
        captured_prefer = prefer
        return {
          pick_item = function(o)
            captured_items = o.items
            o.on_select(o.items[1]) -- pick the first template
          end,
        }
      end,
    }
    package.loaded["lib.nvim.ui.kit"] = {
      input = function(opts) opts.on_submit("new.lua") end,
    }
    package.loaded["filetree.features.fileops.create_from_template"] = nil

    local ft = require("filetree")
    ft.register_adapter(stub)
    ft.setup({ adapter = "units-stub-cft-pickers",
      features = { create_from_template = { enabled = true, template_dir = tdir } } })

    local cft = ft.feature("create_from_template")
    cft.open(dest_dir)

    check("pickers dispatch: prefer defaults to \"auto\"", captured_prefer == "auto",
      tostring(captured_prefer))
    check("pickers dispatch: item carries display text", captured_items ~= nil
      and captured_items[1].text == "basic.lua")
    check("pickers dispatch: item carries the template's file path",
      captured_items ~= nil and captured_items[1].file == tdir .. "/basic.lua")
    check("pickers dispatch: selecting created the file from the template",
      vim.fn.filereadable(dest_dir .. "/new.lua") == 1
      and vim.fn.readfile(dest_dir .. "/new.lua")[1] == "content")
  end

  -- prefer = "builtin": pickers.engines.load() must never be called; falls
  -- through to the pre-existing kit.picker/ui_select flow unchanged.
  do
    vim.fn.delete(dest_dir .. "/new2.lua")
    local pickers_called = false
    package.loaded["pickers.engines"] = {
      load = function() pickers_called = true return nil end,
    }
    package.loaded["lib.nvim.ui.kit"] = {
      select = function(o) o.on_select(o.items[1], 1) end,
      input = function(opts) opts.on_submit("new2.lua") end,
    }
    package.loaded["filetree.util.select"] = nil
    package.loaded["filetree.features.fileops.create_from_template"] = nil

    local ft = require("filetree")
    ft.setup({ adapter = "units-stub-cft-pickers",
      features = { create_from_template = { enabled = true, template_dir = tdir, prefer = "builtin" } } })
    local cft = ft.feature("create_from_template")
    cft.open(dest_dir)

    check("pickers dispatch: prefer=\"builtin\" never calls pickers.engines.load",
      pickers_called == false)
    check("pickers dispatch: prefer=\"builtin\" still creates the file (fallback path)",
      vim.fn.filereadable(dest_dir .. "/new2.lua") == 1)
  end

  -- Both sub-blocks above stub lib.nvim.ui.kit with an incomplete table (only
  -- `.input`/`.select`, no `.confirm`). create_from_template's own module-level
  -- `require("filetree.util.confirm")` captures whatever `kit` is live THE
  -- MOMENT it is first (re)loaded, and caches it — so unless that cache is
  -- invalidated too, any later feature calling confirm.lua (e.g. trash) would
  -- permanently get our incomplete stub and crash on `kit.confirm(...)`.
  package.loaded["pickers.engines"] = nil
  package.loaded["lib.nvim.ui.kit"] = nil
  package.loaded["filetree.util.select"] = nil
  package.loaded["filetree.util.confirm"] = nil
  package.loaded["filetree.features.fileops.create_from_template"] = nil
end

-- ── open_in_fm: target resolution + reuse_existing dispatch ─────────────────
-- Regression coverage for a feature that previously had ZERO logic tests: it
-- only checked that a process STARTED, never that it succeeded — this is what
-- made an intermittent real-world failure look like it had "no pattern."
-- The platform dispatch now lives in lib.nvim.cross.reveal_in_fm (shared with
-- open.nvim), so what is tested here is what this module still decides: which
-- path is handed over, and with which options.
do
  local platform = require("filetree.util.platform")
  local tmp_dir = (TMP_ROOT .. "/units-open-in-fm"):gsub("\\", "/")
  vim.fn.mkdir(tmp_dir, "p")
  local tmp_file = tmp_dir .. "/node.txt"
  vim.fn.writefile({ "x" }, tmp_file)

  local node_path = tmp_dir
  local stub_adapter = {
    get_current_node = function() return { path = node_path } end,
  }

  local orig_is_windows = platform.is_windows
  platform.is_windows = function() return true end

  -- Stub the shared dispatcher: its own platform behavior is lib.nvim's to
  -- test, and stubbing keeps these checks host-independent.
  local orig_reveal_mod = package.loaded["lib.nvim.cross.reveal_in_fm"]
  local captured
  package.loaded["lib.nvim.cross.reveal_in_fm"] = function(target, opts)
    captured = { target = target, opts = opts or {} }
    return true, nil
  end

  local function reload()
    package.loaded["filetree.features.system.open_in_fm"] = nil
    return require("filetree.features.system.open_in_fm")
  end

  local open_in_fm = reload()
  open_in_fm.setup({ enabled = true }, stub_adapter)
  captured = nil
  open_in_fm.open()
  check("open_in_fm: directory node is handed over as-is", captured.target == tmp_dir)
  check("open_in_fm: reveal defaults to true", captured.opts.reveal == true)
  check("open_in_fm: no command override by default", captured.opts.command == nil)

  node_path = tmp_file
  open_in_fm = reload()
  open_in_fm.setup({ enabled = true }, stub_adapter)
  captured = nil
  open_in_fm.open()
  check("open_in_fm: file node keeps the FILE path (so it can be selected)",
    captured.target == tmp_file)

  open_in_fm = reload()
  open_in_fm.setup({ enabled = true, reveal = false, command = "thunar" }, stub_adapter)
  captured = nil
  open_in_fm.open()
  check("open_in_fm: reveal=false is forwarded", captured.opts.reveal == false)
  check("open_in_fm: command override is forwarded", captured.opts.command == "thunar")

  -- A node whose path no longer exists falls back to its parent directory:
  -- there is nothing to select there.
  node_path = tmp_dir .. "/gone/deleted.txt"
  open_in_fm = reload()
  open_in_fm.setup({ enabled = true }, stub_adapter)
  captured = nil
  open_in_fm.open()
  check("open_in_fm: nonexistent node falls back to a directory",
    captured.target ~= node_path)

  -- reuse_existing is no longer decided here: it is forwarded as an option, so
  -- the reuse and the raise happen in one step inside the shared dispatcher.
  -- The old in-module pre-step returned "reused" without ever bringing the
  -- window forward, which Windows silently refuses for a background process.
  node_path = tmp_dir

  open_in_fm = reload()
  open_in_fm.setup({ enabled = true, reuse_existing = true }, stub_adapter)
  captured = nil
  open_in_fm.open()
  check("open_in_fm: reuse_existing=true is forwarded as reuse", captured.opts.reuse == true)
  check("open_in_fm: reuse_existing=true still reaches the shared dispatcher",
    captured.target == tmp_dir)

  open_in_fm = reload()
  open_in_fm.setup({ enabled = true }, stub_adapter)
  captured = nil
  open_in_fm.open()
  check("open_in_fm: reuse defaults to false", captured.opts.reuse == false)

  -- A launcher override names the program, so there is no Explorer window to
  -- reuse — reuse must not be forwarded alongside it.
  open_in_fm = reload()
  open_in_fm.setup({ enabled = true, reuse_existing = true, command = "thunar" }, stub_adapter)
  captured = nil
  open_in_fm.open()
  check("open_in_fm: a command override suppresses reuse", captured.opts.reuse == false)

  -- Reuse is Explorer-specific COM automation; off-Windows it must not be sent.
  platform.is_windows = function() return false end
  open_in_fm = reload()
  open_in_fm.setup({ enabled = true, reuse_existing = true }, stub_adapter)
  captured = nil
  open_in_fm.open()
  check("open_in_fm: reuse is not forwarded off Windows", captured.opts.reuse == false)

  platform.is_windows = orig_is_windows
  package.loaded["lib.nvim.cross.reveal_in_fm"] = orig_reveal_mod
  package.loaded["filetree.features.system.open_in_fm"] = nil
end

-- ── no_name_guard: tab-wide sweep on BufAdd/BufDelete/BufWipeout ────────────
-- Regression coverage for a real, previously-untested gap: a stray [No Name]
-- buffer sitting in a window that never itself refires BufWinEnter (so the
-- existing single-pair `handle()` never revisits it) used to persist
-- indefinitely even with real, usable buffers open elsewhere.
do
  vim.cmd("only")
  local real_path = (TMP_ROOT .. "/units-no-name-guard-real.txt"):gsub("\\", "/")
  vim.fn.writefile({ "x" }, real_path)
  vim.cmd("edit " .. vim.fn.fnameescape(real_path))

  vim.cmd("vsplit")
  local no_name_win = vim.api.nvim_get_current_win()
  vim.cmd("enew") -- fresh [No Name] buffer in THIS window only
  local no_name_buf = vim.api.nvim_win_get_buf(no_name_win)

  check("no_name_guard setup: second window really is a stray No Name buffer",
    vim.api.nvim_buf_get_name(no_name_buf) == "" and vim.bo[no_name_buf].buftype == "")

  local stub_adapter = setmetatable({
    name = "units-stub-no-name-guard",
    is_available = function() return true end,
    get_winid = function() return nil end,
    refresh = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub_adapter)
  ft.setup({ adapter = "units-stub-no-name-guard",
    features = { no_name_guard = { enabled = true } } })

  -- The sweep doesn't care which buffer/event triggered it, only that the
  -- buffer list changed -- fire BufAdd on something unrelated.
  vim.cmd("badd " .. vim.fn.fnameescape(vim.fn.tempname()))
  vim.wait(50)

  check("no_name_guard sweep: the No Name window was redirected to a real buffer",
    vim.api.nvim_win_get_buf(no_name_win) ~= no_name_buf)
  check("no_name_guard sweep: the stray buffer itself was wiped",
    not vim.api.nvim_buf_is_valid(no_name_buf))

  pcall(vim.api.nvim_win_close, no_name_win, true)
  vim.cmd("only")
end

-- ── open_variants: sg/sv/st/gb/<S-CR> are all bound ──────────────────────────
do
  local cur_node = { path = (TMP_ROOT .. "/units-openvariants.txt"):gsub("\\", "/"), type = "file" }
  vim.fn.writefile({ "x" }, cur_node.path)
  local stub = setmetatable({
    name = "units-stub4", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub4", features = { open_variants = { enabled = true } } })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "neo-tree"
  vim.wait(200, function() return false end)

  local km = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do km[m.lhs] = m end
  check("open_variants: 'sg' bound", km["sg"] ~= nil)
  check("open_variants: 'sv' bound", km["sv"] ~= nil)
  check("open_variants: 'st' bound", km["st"] ~= nil)
  check("open_variants: 'gb' bound", km["gb"] ~= nil)
  check("open_variants: '<S-CR>' bound", km["<S-CR>"] ~= nil)

  local ov = ft.feature("open_variants")
  ov.open_badd()
  check("open_variants: open_badd() adds the file to the buffer list",
    vim.fn.bufnr(cur_node.path) ~= -1)
end

-- ── markdown_links: current/recursive/marked all produce "[name](path)" ─────
do
  local tmp = (TMP_ROOT .. "/units-mdlinks"):gsub("\\", "/")
  vim.fn.mkdir(tmp .. "/sub", "p")
  vim.fn.writefile({ "x" }, tmp .. "/a.lua")
  vim.fn.writefile({ "x" }, tmp .. "/sub/b.lua")
  vim.fn.chdir(tmp)

  local cur_node = { path = tmp .. "/a.lua", type = "file" }
  local stub = setmetatable({
    name = "units-stub5", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub5", features = { markdown_links = { enabled = true } } })

  local md = ft.feature("markdown_links")
  local ok_cur = pcall(md.link_current)
  check("markdown_links: link_current() does not error", ok_cur)
  if HAS_CLIPBOARD then
    check("markdown_links: link_current() copies '[a.lua](a.lua)'",
      vim.fn.getreg("+") == "[a.lua](a.lua)", vim.fn.getreg("+"))
  end

  cur_node = { path = tmp, type = "directory" }
  local ok_rec = pcall(md.link_recursive)
  check("markdown_links: link_recursive() does not error", ok_rec)
  if HAS_CLIPBOARD then
    local recursive_reg = vim.fn.getreg("+")
    check("markdown_links: link_recursive() includes the top-level file",
      recursive_reg:find("[a.lua](a.lua)", 1, true) ~= nil, recursive_reg)
    check("markdown_links: link_recursive() includes the nested file",
      recursive_reg:find("b.lua", 1, true) ~= nil, recursive_reg)
  end
end

-- ── config.confirmations: boolean shorthand + per-action table ──────────────
-- explicit per-feature `confirm` always wins over the top-level switch.
do
  local config = require("filetree.config")

  config.setup({ adapter = "stub", confirmations = false })
  local cfg = config.get()
  check("confirmations=false: copy_move.confirm is false",
    cfg.features.copy_move.confirm == false)
  check("confirmations=false: trash.confirm is false",
    cfg.features.trash.confirm == false)
  check("confirmations=false: rename_batch.confirm is false",
    cfg.features.rename_batch.confirm == false)

  config.setup({ adapter = "stub", confirmations = { paste = false, delete = true } })
  cfg = config.get()
  check("confirmations table: paste -> copy_move.confirm false",
    cfg.features.copy_move.confirm == false)
  check("confirmations table: delete -> trash.confirm true",
    cfg.features.trash.confirm == true)
  check("confirmations table: rename_batch untouched (nil, not in table)",
    cfg.features.rename_batch == nil or cfg.features.rename_batch.confirm == nil)

  config.setup({
    adapter = "stub",
    confirmations = true,
    features = { trash = { confirm = false } },
  })
  cfg = config.get()
  check("explicit features.trash.confirm=false wins over confirmations=true",
    cfg.features.trash.confirm == false)
  check("confirmations=true still applies to copy_move (not explicitly set)",
    cfg.features.copy_move.confirm == true)
end

-- ── trash: default (no confirmations config at all) DOES prompt ────────────
-- End-to-end check of the *actual* out-of-the-box default, not just what
-- config.get() reports: with nothing set, delete_current() must prompt before
-- deleting (now via the util.confirm info popup, not native vim.fn.confirm).
-- trash is deliberately the one confirmable action that defaults to
-- confirm=true (copy_move/rename_batch stay confirm=false) -- see the comment
-- on trash/init.lua's _cfg.confirm.
do
  local tmp = (TMP_ROOT .. "/units-trash-noconfirm"):gsub("\\", "/")
  vim.fn.mkdir(tmp, "p")
  vim.fn.writefile({ "x" }, tmp .. "/victim2.txt")

  local cur_node = { path = tmp .. "/victim2.txt", type = "file" }
  local stub = setmetatable({
    name = "units-stub6", is_available = function() return true end,
    get_current_node = function() return cur_node end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  -- Force a fresh module load: trash's `_cfg` is a module-level table that
  -- earlier test blocks in this same process have already called setup() on
  -- with an explicit `confirm = false`, and setup() merges onto the existing
  -- _cfg rather than resetting to the module's literal default table -- so
  -- without this, this test would silently inherit that earlier confirm=false
  -- instead of exercising the actual shipped default.
  package.loaded["filetree.features.fileops.trash"] = nil

  local ft = require("filetree")
  ft.register_adapter(stub)
  -- No `confirm`/`confirmations` anywhere -- purely the shipped default.
  ft.setup({ adapter = "units-stub6", features = { trash = { enabled = true, dry_run = true } } })

  -- The shipped default confirms; a single delete now opens the nice info
  -- popup (util.confirm float) rather than the native vim.fn.confirm prompt.
  local confirm_called = false
  local orig_confirm = vim.fn.confirm
  vim.fn.confirm = function(...) confirm_called = true; return 1 end
  local floats_before = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then floats_before = floats_before + 1 end
  end
  ft.feature("trash").delete_current()
  vim.fn.confirm = orig_confirm

  local confirm_float = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then confirm_float = w end
  end
  check("trash: default confirm opens a popup, not the native vim.fn.confirm",
    confirm_float ~= nil and not confirm_called)
  eq("trash: file not yet deleted while the confirm popup is open",
    vim.fn.filereadable(tmp .. "/victim2.txt"), 1)
  if confirm_float then pcall(vim.api.nvim_win_close, confirm_float, true) end
end

-- ── trash.undo: Windows restore reports real failure, not silent success ────
-- Regression for a bug where InvokeVerb('restore') is a *localized* verb
-- caption (e.g. German "Wiederherstellen") -- on any non-English Windows it
-- silently matched nothing, yet the script still exited 0, so restore_last()
-- reported success and dropped the history entry despite restoring nothing.
do
  package.loaded["filetree.features.fileops.trash.undo"] = nil
  local undo = require("filetree.features.fileops.trash.undo")

  -- restore_windows() shells out via lib.nvim.cross.run_argv.run_blocking, not
  -- os.execute -- an earlier version of this test mocked os.execute, which the
  -- code has never called. That mock silently intercepted nothing: every
  -- "with_exit_code" run below actually spawned a real PowerShell process
  -- against the real Recycle Bin looking for a file that was never trashed,
  -- so every case coincidentally got real exit code 1 ("not found") regardless
  -- of the exit code the test asked for -- passing only by accident when the
  -- requested code also happened to be 1, and failing (with a live "Item not
  -- found" message) for every other code. Mock the actual dependency instead;
  -- run_argv's module table is cached by require(), so overwriting the field
  -- here is visible to undo.lua's own require(...).run_blocking(...) call.
  local run_argv = require("lib.nvim.cross.run_argv")
  local orig_run_blocking = run_argv.run_blocking
  local captured_cmd

  local function with_exit_code(code, fn)
    run_argv.run_blocking = function(cmd)
      captured_cmd = cmd[#cmd] -- the PowerShell script is the last argv element
      if code == 0 then return true, nil end
      return false, "exit code " .. code
    end
    local ok, err = fn()
    run_argv.run_blocking = orig_run_blocking
    return ok, err
  end

  local entry = {
    original_path = "C:/Users/x/project/victim.txt",
    name           = "victim.txt",
    trashed_at     = "2026-01-01 00:00:00",
    platform       = "windows",
  }

  local ok1, err1 = with_exit_code(1, function() return undo.restore(entry) end)
  check("trash.undo: exit 1 (not found) is reported as failure, not success",
    ok1 == false and err1 ~= nil and err1:find("not found") ~= nil, tostring(err1))

  local ok2, err2 = with_exit_code(2, function() return undo.restore(entry) end)
  check("trash.undo: exit 2 (move and verb fallback both failed) is reported as failure, not success",
    ok2 == false and err2 ~= nil and err2:find("could not move", 1, true) ~= nil, tostring(err2))

  local ok3, err3 = with_exit_code(3, function() return undo.restore(entry) end)
  check("trash.undo: exit 3 (target already exists) is reported as failure, not success",
    ok3 == false and err3 ~= nil and err3:find("already exists", 1, true) ~= nil, tostring(err3))

  local ok4 = with_exit_code(0, function() return undo.restore(entry) end)
  check("trash.undo: exit 0 is reported as success", ok4 == true)

  check("trash.undo: generated PowerShell command matches by DeletedFrom, not just Name",
    captured_cmd ~= nil and captured_cmd:find("DeletedFrom", 1, true) ~= nil)
  check("trash.undo: generated PowerShell command restores via a locale-free Move-Item first",
    captured_cmd ~= nil and captured_cmd:find("Move-Item", 1, true) ~= nil, tostring(captured_cmd))
  check("trash.undo: generated PowerShell command still keeps the verb-caption fallback (incl. German)",
    captured_cmd ~= nil and captured_cmd:find("Wiederherstellen", 1, true) ~= nil)
  check("trash.undo: generated PowerShell command targets the original path",
    captured_cmd ~= nil and captured_cmd:find("C:\\Users\\x\\project\\victim.txt", 1, true) ~= nil,
    tostring(captured_cmd))
end

-- ── project_root: caches per-directory, populates intermediate dirs too ─────
do
  package.loaded["filetree.features.infra.project_root"] = nil
  local proot = require("filetree.features.infra.project_root")

  local tmp = (TMP_ROOT .. "/units-projectroot"):gsub("\\", "/")
  vim.fn.mkdir(tmp .. "/proj/.git", "p")
  vim.fn.mkdir(tmp .. "/proj/src/deep/nested", "p")
  vim.fn.writefile({ "x" }, tmp .. "/proj/src/deep/nested/file.lua")

  proot.setup({ enabled = true }, { name = "stub" })
  proot.clear_cache()

  local root1 = proot.find(tmp .. "/proj/src/deep/nested/file.lua")
  eq("project_root: finds .git root from a deeply nested file",
    root1:gsub("\\", "/"), tmp .. "/proj")

  -- An intermediate directory passed on the same walk should now be cached
  -- too, without needing its own filesystem walk.
  local root2 = proot.find(tmp .. "/proj/src/deep")
  eq("project_root: intermediate directory resolves to the same cached root",
    root2:gsub("\\", "/"), tmp .. "/proj")

  -- Simulate a real cache hit: remove the .git dir on disk: if find() still
  -- returns the project root, it proved the cached value was used rather
  -- than a fresh (now-negative) filesystem walk.
  vim.fn.delete(tmp .. "/proj/.git", "d")
  local root3 = proot.find(tmp .. "/proj/src/deep/nested/file.lua")
  eq("project_root: cache hit survives the marker being removed from disk",
    root3:gsub("\\", "/"), tmp .. "/proj")

  proot.clear_cache()
  local root4 = proot.find(tmp .. "/proj/src/deep/nested/file.lua")
  check("project_root: clear_cache() forces a fresh walk (marker now gone)",
    root4:gsub("\\", "/") ~= tmp .. "/proj")
end

-- ── cheatsheet: `?` opens a float listing active tree-scoped keymaps ────────
-- Binds on a generic adapter (filetypes-driven, not hardcoded to neo-tree/
-- NvimTree), skips entirely on the neotree adapter (native `?` already
-- covers it), and degrades to a no-op when `filetypes` is missing/not a
-- table (the "got Function" bug from a catch-all __index stub adapter).
do
  local stub = setmetatable({
    name = "units-stub-cheatsheet", filetypes = { "units-cheatsheet-ft" },
    is_available = function() return true end,
    get_current_node = function() return nil end,
    get_winid = function() return nil end,
    refresh   = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-cheatsheet",
    features = { cheatsheet = { enabled = true, keymap = "?" }, trash = { enabled = true } } })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "units-cheatsheet-ft"
  vim.wait(200, function() return false end)

  local km = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do km[m.lhs] = m end
  check("cheatsheet: '?' bound on the stub adapter's own filetype", km["?"] ~= nil)

  ft.feature("cheatsheet").show()
  local wins = vim.api.nvim_list_wins()
  local float_win, float_buf
  for _, w in ipairs(wins) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then float_win = w end
  end
  check("cheatsheet: show() opens a floating window", float_win ~= nil)
  if float_win then
    float_buf = vim.api.nvim_win_get_buf(float_win)
    local lines = vim.api.nvim_buf_get_lines(float_buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    check("cheatsheet: lists the fileops category header", text:find("%sfileops") ~= nil, text)
    check("cheatsheet: lists trash's 'd' keymap (feature is enabled)", text:find("d%s+Trash") ~= nil, text)
    check("cheatsheet: shows a close hint", text:find("close") ~= nil)
  end

  ft.feature("cheatsheet").show() -- second invocation toggles it closed
  check("cheatsheet: second show() closes the float",
    float_win == nil or not vim.api.nvim_win_is_valid(float_win))

  -- neotree: must NOT bind '?' (native help already covers it) and must not
  -- error even though the neotree adapter module isn't actually loadable here.
  local neotree_stub = setmetatable({
    name = "neotree", filetypes = { "neo-tree" },
    is_available = function() return true end,
  }, { __index = function() return function() return false end end })
  ft.register_adapter(neotree_stub)
  local setup_ok = pcall(ft.setup, { adapter = "neotree",
    features = { cheatsheet = { enabled = true, keymap = "?" } } })
  check("cheatsheet: setup() with the neotree adapter does not error", setup_ok)

  local buf2 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf2)
  vim.bo[buf2].filetype = "neo-tree"
  vim.wait(200, function() return false end)
  local has_q = false
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf2, "n")) do
    if m.lhs == "?" then has_q = true end
  end
  check("cheatsheet: does NOT bind '?' on the neotree adapter", not has_q)

  -- filetypes missing/wrong-shaped (catch-all __index stub) must not error.
  local no_filetypes_stub = setmetatable({
    name = "units-stub-cheatsheet-nofiletypes",
    is_available = function() return true end,
  }, { __index = function() return function() return false end end })
  ft.register_adapter(no_filetypes_stub)
  local setup_ok2 = pcall(ft.setup, { adapter = "units-stub-cheatsheet-nofiletypes",
    features = { cheatsheet = { enabled = true, keymap = "?" } } })
  check("cheatsheet: setup() does not error when adapter.filetypes is missing/not a table", setup_ok2)
end

-- ── breadcrumbs: float mode via lib.nvim.ui.statusline, anchored at the top ──
-- Migrated off a hand-rolled float (position/buffer/lifecycle management) onto
-- the shared primitive; anchor="top" is what makes it a header rather than a
-- status bar, unlike cwd_mode's badge which sits at the bottom.
do
  vim.cmd("vsplit")
  local tree_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd p")

  local function floats()
    local out = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then out[#out + 1] = w end
    end
    return out
  end

  local before = #floats()
  local breadcrumbs = require("filetree.features.ui.breadcrumbs")
  local adapter = {
    name = "units-stub-breadcrumbs",
    get_winid = function() return tree_win end,
    get_current_node = function() return nil end,
  }

  breadcrumbs.setup({ enabled = true, mode = "float" }, adapter)
  breadcrumbs.update(root .. "/lua/filetree/init.lua")

  local open = floats()
  check("breadcrumbs float: exactly one float opened", #open == before + 1)
  if #open == before + 1 then
    local win = open[#open]
    local pos = vim.api.nvim_win_get_position(tree_win)
    local cfg = vim.api.nvim_win_get_config(win)
    check("breadcrumbs float: anchored at the tree window's TOP row",
      cfg.row == pos[1])
    local buf = vim.api.nvim_win_get_buf(win)
    local text = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] or ""
    check("breadcrumbs float: shows the path", text:find("init%.lua") ~= nil, text)
  end

  breadcrumbs.teardown()
  check("breadcrumbs float: teardown closes it", #floats() == before)
end

-- ── context_menu: right-click binding, opt-out default, soft nvzone/menu dep ──
do
  local stub = setmetatable({
    name = "units-stub-context-menu", filetypes = { "units-context-menu-ft" },
    is_available = function() return true end,
  }, { __index = function() return function() return false end end })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = "units-stub-context-menu" })  -- no explicit context_menu config at all

  check("context_menu: active without explicit config (opt-out, on by default)",
    ft.feature("context_menu") ~= nil)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "units-context-menu-ft"
  vim.wait(200, function() return false end)

  local km = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do km[m.lhs] = m end
  check("context_menu: default keymap '<RightMouse>' bound", km["<RightMouse>"] ~= nil)

  -- Without nvzone/menu on rtp: clicking must not error, just degrade quietly.
  package.loaded["menu"] = nil
  local ok_no_menu = pcall(km["<RightMouse>"].callback)
  check("context_menu: click without nvzone/menu installed does not error", ok_no_menu)

  -- With a stubbed nvzone/menu: click must call menu.open(items, {mouse=true})
  -- with the SAME entries filetree.integrations.menu.items() builds (that
  -- module's own content is covered by test/menu.lua; this only checks the
  -- wiring calls through correctly).
  local captured
  package.loaded["menu"] = { open = function(items, opts) captured = { items = items, opts = opts } end }
  local ok_menu = pcall(km["<RightMouse>"].callback)
  check("context_menu: click with nvzone/menu present does not error", ok_menu)
  check("context_menu: calls menu.open()", captured ~= nil)
  if captured then
    check("context_menu: opens with mouse=true", captured.opts.mouse == true)
    check("context_menu: passes a non-empty item list", #captured.items > 0)
  end
  package.loaded["menu"] = nil

  -- keymap = false disables the binding without disabling the feature.
  local stub2 = setmetatable({
    name = "units-stub-context-menu-2", filetypes = { "units-context-menu-ft2" },
    is_available = function() return true end,
  }, { __index = function() return function() return false end end })
  ft.register_adapter(stub2)
  ft.setup({ adapter = "units-stub-context-menu-2",
    features = { context_menu = { keymap = false } } })
  check("context_menu: keymap=false still leaves the feature enabled",
    ft.feature("context_menu") ~= nil)

  local buf2 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf2)
  vim.bo[buf2].filetype = "units-context-menu-ft2"
  vim.wait(200, function() return false end)
  local has_rm = false
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf2, "n")) do
    if m.lhs == "<RightMouse>" then has_rm = true end
  end
  check("context_menu: keymap=false does not bind '<RightMouse>'", not has_rm)
end

-- ── util.window: new editor windows stay clear of the tree's side ───────────
-- Regression: a bare `:vsplit` from the (full-width) tree window follows
-- 'splitright', so with the default `splitright = false` the new window landed
-- LEFT of a left sidebar — visually moving the tree to the right edge.
do
  local window = require("filetree.util.window")

  eq("window.away_modifier(left)",  window.away_modifier("left"),  "botright")
  eq("window.away_modifier(right)", window.away_modifier("right"), "topleft")
  eq("window.away_modifier(nil)",   window.away_modifier(nil),     "")

  local function stub(pos, winid)
    return {
      name = "units-stub-window",
      get_position = function() return pos end,
      get_winid    = function() return winid end,
    }
  end

  eq("window.tree_side: adapter position wins", window.tree_side(stub("right", nil)), "right")
  check("window.tree_side: float has no side", window.tree_side(stub("float", nil)) == nil)
  check("window.tree_side: no adapter at all", window.tree_side(nil) == nil)

  local saved_splitright = vim.o.splitright
  vim.o.splitright = false  -- the setting that produced the bug

  vim.cmd("only")
  local tree_win = vim.api.nvim_get_current_win()
  local new_win  = window.open_editor_window(stub("left", tree_win), { empty = true })
  check("window.open_editor_window: created a window", new_win ~= nil)
  eq("window.open_editor_window: left tree stays at column 0",
    vim.api.nvim_win_get_position(tree_win)[2], 0)
  check("window.open_editor_window: new window sits right of a left tree",
    new_win ~= nil and vim.api.nvim_win_get_position(new_win)[2] > 0)

  vim.cmd("only")
  local tree_win_r = vim.api.nvim_get_current_win()
  local new_win_r  = window.open_editor_window(stub("right", tree_win_r), { empty = true })
  check("window.open_editor_window: right tree keeps a non-zero column",
    vim.api.nvim_win_get_position(tree_win_r)[2] > 0)
  eq("window.open_editor_window: new window sits left of a right tree",
    new_win_r and vim.api.nvim_win_get_position(new_win_r)[2], 0)

  vim.cmd("only")
  vim.o.splitright = saved_splitright
end

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nfiletree.nvim units: %d passed, %d failed"):format(passed, failed))
if failed > 0 then vim.cmd("cq") else vim.cmd("qa!") end
