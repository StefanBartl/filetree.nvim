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
  -- for the smart_create/compare_dirs/duplicate_node/smart_rename prompt fix.
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
  check("cwd_sync triggers adapter.refresh()", refreshed)
  check("cwd_sync still reveals the file",
    revealed_path and revealed_path:gsub("\\", "/") == tmp .. "/proj/sub/file.lua")
end

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nfiletree.nvim units: %d passed, %d failed"):format(passed, failed))
if failed > 0 then vim.cmd("cq") else vim.cmd("qa!") end
