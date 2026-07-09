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
local sibling_lib = vim.fn.fnamemodify(root, ":h") .. "/lib.nvim"
if vim.fn.isdirectory(sibling_lib) == 1 then vim.opt.rtp:prepend(sibling_lib) end

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
  eq("path.to_unix backslashes", path.to_unix("E:\\a\\b"):gsub("^%a:", ""), "/a/b")
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
  local tmp = (vim.env.TEMP .. "/units-relocate"):gsub("\\", "/")
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
  local buf_d = vim.api.nvim_get_current_buf()
  vim.fn.rename(tmp .. "/src/d.txt", tmp .. "/dst/d.txt")
  local n4 = buf.relocate((tmp .. "/src/d.txt"):gsub("/", "\\"), (tmp .. "/dst/d.txt"):gsub("/", "\\"))
  eq("relocate: backslash old/new path still matches forward-slash buffer name", n4, 1)
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
  package.loaded["lib.nvim.ui.hover_select"] = { open = function(o) o.on_select(o.items[2], 2) end }
  local ui_select = require("filetree.util.select")
  local chosen
  ui_select({ "a", "b", "c" }, { prompt = "p" }, function(item, idx) chosen = { item, idx } end)
  check("select passes original item + index", chosen and chosen[1] == "b" and chosen[2] == 2)
  package.loaded["lib.nvim.ui.hover_select"] = nil
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
  local tmp = (vim.env.TEMP .. "/units-cwdsync"):gsub("\\", "/")
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
  local tmp = (vim.env.TEMP .. "/units-cwdsync-catchup"):gsub("\\", "/")
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

-- ── copy_move: default single-char "c"/"x" cleanly override the adapter's ───
-- native "c"/"x" (exact same key, last-registration-wins -- no ambiguity).
do
  local tmp = (vim.env.TEMP .. "/units-copymove"):gsub("\\", "/")
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

  local buf = vim.api.nvim_create_buf(true, false)
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
  local tmp = (vim.env.TEMP .. "/units-copymove2"):gsub("\\", "/")
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

  local buf = vim.api.nvim_create_buf(true, false)
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
  local tmp = (vim.env.TEMP .. "/units-copymove-relocate"):gsub("\\", "/")
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

-- ── trash: delete_current binds d/U/<leader>th and trashes the right node ───
do
  local tmp = (vim.env.TEMP .. "/units-trash"):gsub("\\", "/")
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

  local buf = vim.api.nvim_create_buf(true, false)
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
  local captured
  local orig_notify = vim.notify
  vim.notify = function(m) captured = m end
  trash.delete_current()
  vim.notify = orig_notify
  check("trash: delete_current() (dry-run) targets the current node",
    captured and captured:find("victim.txt", 1, true) ~= nil, tostring(captured))
end

-- ── open_variants: sg/sv/st/gb/<S-CR> are all bound ──────────────────────────
do
  local cur_node = { path = (vim.env.TEMP .. "/units-openvariants.txt"):gsub("\\", "/"), type = "file" }
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

  local buf = vim.api.nvim_create_buf(true, false)
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
  local tmp = (vim.env.TEMP .. "/units-mdlinks"):gsub("\\", "/")
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
  md.link_current()
  check("markdown_links: link_current() copies '[a.lua](a.lua)'",
    vim.fn.getreg("+") == "[a.lua](a.lua)", vim.fn.getreg("+"))

  cur_node = { path = tmp, type = "directory" }
  md.link_recursive()
  local recursive_reg = vim.fn.getreg("+")
  check("markdown_links: link_recursive() includes the top-level file",
    recursive_reg:find("[a.lua](a.lua)", 1, true) ~= nil, recursive_reg)
  check("markdown_links: link_recursive() includes the nested file",
    recursive_reg:find("b.lua", 1, true) ~= nil, recursive_reg)
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
-- config.get() reports: with nothing set, delete_current() must call
-- vim.fn.confirm. trash is deliberately the one confirmable action that
-- defaults to confirm=true (copy_move/rename_batch stay confirm=false) --
-- see the comment on trash/init.lua's _cfg.confirm.
do
  local tmp = (vim.env.TEMP .. "/units-trash-noconfirm"):gsub("\\", "/")
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

  local confirm_called = false
  local orig_confirm = vim.fn.confirm
  vim.fn.confirm = function(...) confirm_called = true; return 1 end
  ft.feature("trash").delete_current()
  vim.fn.confirm = orig_confirm

  check("trash: default (no confirmations config) calls vim.fn.confirm",
    confirm_called)
end

-- ── trash.undo: Windows restore reports real failure, not silent success ────
-- Regression for a bug where InvokeVerb('restore') is a *localized* verb
-- caption (e.g. German "Wiederherstellen") -- on any non-English Windows it
-- silently matched nothing, yet the script still exited 0, so restore_last()
-- reported success and dropped the history entry despite restoring nothing.
do
  package.loaded["filetree.features.fileops.trash.undo"] = nil
  local undo = require("filetree.features.fileops.trash.undo")

  local orig_execute = os.execute
  local captured_cmd

  local function with_exit_code(code, fn)
    os.execute = function(cmd) captured_cmd = cmd; return code end
    local ok, err = fn()
    os.execute = orig_execute
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

  local tmp = (vim.env.TEMP .. "/units-projectroot"):gsub("\\", "/")
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

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nfiletree.nvim units: %d passed, %d failed"):format(passed, failed))
if failed > 0 then vim.cmd("cq") else vim.cmd("qa!") end
