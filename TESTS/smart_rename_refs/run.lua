-- run.lua — reference-update regression test for smart_rename's textual
-- fallback (lua_ls has no workspace/willRenameFiles, so this fallback is the
-- only thing keeping require()/import references correct for Lua projects;
-- Python and TS/JS are covered too since the same code path serves them).
--
-- For each language under fixtures/<lang>/, it copies the fixture tree to a
-- scratch dir, renames the "hub" module via smart_rename.rename_current()
-- with a stubbed adapter (no real tree plugin needed) and a stubbed
-- vim.ui.input, then asserts every referencing file was rewritten to point
-- at the new name — and that an unrelated same-prefix module was NOT touched
-- (negative control, guards against overly loose pattern matching).
--
-- Usage (from the filetree.nvim repo root):
--   nvim --clean --headless -u NONE -l TESTS/smart_rename_refs/run.lua
--
-- Exit 0 = all passed, 1 = a check failed.
--
-- To add another language: add a fixtures/<lang>/ tree with a project marker
-- file (see project_root's marker list — .luarc.json, pyproject.toml,
-- package.json, Cargo.toml, go.mod, ... all work) and a LANGS entry below
-- pointing at the hub file + the files that reference it.

-- ── Locate the repo root relative to this file, put it on rtp ────────────────
local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h:h")
vim.opt.rtp:prepend(root)
local sibling_lib = vim.fn.fnamemodify(root, ":h") .. "/lib.nvim"
if vim.fn.isdirectory(sibling_lib) == 1 then vim.opt.rtp:prepend(sibling_lib) end

local fixtures_root = vim.fn.fnamemodify(this, ":p:h") .. "/fixtures"
local scratch_root = (vim.fn.has("win32") == 1 and vim.env.TEMP or "/tmp") .. "/filetree-smart-rename-test"

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

-- ── Portable recursive directory copy (binary-safe, no shell dependency) ─────
local function copy_dir(src, dst)
  vim.fn.mkdir(dst, "p")
  for _, name in ipairs(vim.fn.readdir(src)) do
    local s = src .. "/" .. name
    local d = dst .. "/" .. name
    if vim.fn.isdirectory(s) == 1 then
      copy_dir(s, d)
    else
      vim.fn.writefile(vim.fn.readfile(s, "b"), d, "b")
    end
  end
end

local function read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and table.concat(lines, "\n") or nil
end

local function count_sub(s, sub)
  local n, i = 0, 1
  while true do
    local f = s:find(sub, i, true)
    if not f then return n end
    n = n + 1
    i = f + #sub
  end
end

---Whether `old` was fully replaced by `new` in `content`. Plain substring
---absence isn't enough when `new` textually extends `old` (e.g. python's bare
---"import pkg.util.shared" -> "import pkg.util.shared_utils" has no delimiter
---between them) — every correctly-updated occurrence of `new` would then
---still contain `old` as its own prefix. In that case compare counts instead:
---equal counts means every `old` match is accounted for by a `new` match,
---i.e. nothing was left unreplaced.
---@param content string
---@param old string
---@param new string
---@return boolean
local function old_fully_replaced(content, old, new)
  if new:sub(1, #old) == old then
    return count_sub(content, old) == count_sub(content, new)
  end
  return content:find(old, 1, true) == nil
end

-- ── Language specs ────────────────────────────────────────────────────────────
-- checks[i].old == checks[i].new marks a negative control: the file must
-- still contain `old` unchanged (proves the rename didn't over-match).

---@class LangSpec
---@field name     string
---@field hub      string  Path (relative to the fixture root) of the file to rename.
---@field new_name string  New basename for the hub file.
---@field checks   {file: string, old: string, new: string}[]

---@type LangSpec[]
local LANGS = {
  {
    name     = "lua",
    hub      = "lua/proj/util/shared.lua",
    new_name = "shared_utils.lua",
    checks = {
      { file = "lua/proj/a.lua",              old = 'require("proj.util.shared")', new = 'require("proj.util.shared_utils")' },
      { file = "lua/proj/nested/b.lua",       old = 'require("proj.util.shared")', new = 'require("proj.util.shared_utils")' },
      { file = "lua/proj/nested/deep/c.lua",  old = 'require "proj.util.shared"',  new = 'require "proj.util.shared_utils"' },
      { file = "lua/proj/other/unrelated.lua",old = 'require("proj.util.shared_other")', new = 'require("proj.util.shared_other")' },
    },
  },
  {
    name     = "python",
    hub      = "pkg/util/shared.py",
    new_name = "shared_utils.py",
    checks = {
      { file = "pkg/a.py",               old = "from pkg.util.shared import greet", new = "from pkg.util.shared_utils import greet" },
      { file = "pkg/nested/b.py",        old = "import pkg.util.shared",            new = "import pkg.util.shared_utils" },
      { file = "pkg/other/unrelated.py", old = "from pkg.util.shared_other import greet", new = "from pkg.util.shared_other import greet" },
    },
  },
  {
    name     = "ts",
    hub      = "src/util/shared.ts",
    new_name = "shared_utils.ts",
    checks = {
      { file = "src/a.ts",               old = 'from "./util/shared"',     new = 'from "./util/shared_utils"' },
      { file = "src/nested/b.ts",        old = 'from "../util/shared"',    new = 'from "../util/shared_utils"' },
      { file = "src/nested/deep/c.tsx",  old = 'from "../../util/shared"', new = 'from "../../util/shared_utils"' },
      { file = "src/other/d.js",         old = 'import("../util/shared")', new = 'import("../util/shared_utils")' },
      { file = "src/other/unrelated.ts", old = 'from "../util/shared_other"', new = 'from "../util/shared_other"' },
    },
  },
}

-- ── Run one language ──────────────────────────────────────────────────────────
local function run_lang(lang)
  print("\n== " .. lang.name .. " ==")

  local work = scratch_root .. "/" .. lang.name
  vim.fn.delete(work, "rf")
  copy_dir(fixtures_root .. "/" .. lang.name, work)

  local hub_old = work .. "/" .. lang.hub
  local hub_dir = vim.fn.fnamemodify(hub_old, ":h")
  local hub_new = hub_dir .. "/" .. lang.new_name

  local smart_rename = require("filetree.features.fileops.smart_rename")
  -- do_rename's fs_rename callback fires as soon as the OS-level rename
  -- completes, but it then *schedules* the rest of the work (reference
  -- update, refresh, final notify) for the next event-loop tick — so
  -- filereadable(hub_new) can flip true a tick before the reference fallback
  -- has actually run. adapter.refresh() is the last thing do_rename calls
  -- before its final notify, so use it as the "fully done" signal instead.
  local done = false
  local stub_adapter = {
    get_current_node = function() return { path = hub_old, type = "file" } end,
    refresh          = function() done = true end,
  }
  smart_rename.setup({
    enabled           = true,
    use_safety        = false,
    dry_run           = false,
    update_references = true,
  }, stub_adapter)

  local orig_input = vim.ui.input
  vim.ui.input = function(_, on_confirm) on_confirm(lang.new_name) end

  smart_rename.rename_current()
  vim.wait(3000, function() return done end, 20)
  vim.ui.input = orig_input

  check(lang.name .. ": hub file renamed on disk", vim.fn.filereadable(hub_new) == 1)
  check(lang.name .. ": old hub path gone", vim.fn.filereadable(hub_old) == 0)

  for _, c in ipairs(lang.checks) do
    local content = read(work .. "/" .. c.file)
    if c.old == c.new then
      check(("%s: %s unchanged (negative control)"):format(lang.name, c.file),
        content ~= nil and content:find(c.old, 1, true) ~= nil)
    else
      check(("%s: %s updated"):format(lang.name, c.file),
        content ~= nil and content:find(c.new, 1, true) ~= nil,
        "missing " .. c.new)
      check(("%s: %s old reference gone"):format(lang.name, c.file),
        content ~= nil and old_fully_replaced(content, c.old, c.new),
        "still contains " .. c.old)
    end
  end
end

-- ── Bonus: verify the open-buffer branch (not just on-disk files) ────────────
-- patch_file_references patches loaded buffers live via nvim_buf_set_lines
-- instead of going through disk I/O; exercise that path once, for Lua.
local function run_lua_buffer_check()
  print("\n== lua (open buffer) ==")

  local work = scratch_root .. "/lua_buffer"
  vim.fn.delete(work, "rf")
  copy_dir(fixtures_root .. "/lua", work)

  local hub_old = work .. "/lua/proj/util/shared.lua"
  local ref_path = work .. "/lua/proj/nested/b.lua"

  vim.cmd("edit " .. vim.fn.fnameescape(ref_path))
  local bufnr = vim.fn.bufnr(ref_path)

  local done = false
  local smart_rename = require("filetree.features.fileops.smart_rename")
  smart_rename.setup({
    enabled = true, use_safety = false, dry_run = false, update_references = true,
  }, {
    get_current_node = function() return { path = hub_old, type = "file" } end,
    refresh          = function() done = true end,
  })

  local orig_input = vim.ui.input
  vim.ui.input = function(_, on_confirm) on_confirm("shared_utils.lua") end
  smart_rename.rename_current()
  vim.wait(3000, function() return done end, 20)
  vim.ui.input = orig_input

  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local buf_content = table.concat(buf_lines, "\n")
  check("lua buffer: open buffer patched in-memory",
    buf_content:find('require("proj.util.shared_utils")', 1, true) ~= nil,
    "buffer content: " .. buf_content)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ── Regression: directory rename cascades to nested submodule requires ──────
-- Renaming a directory ("proj.util" -> "proj.utilities") must update
-- require("proj.util.shared") -> require("proj.utilities.shared") in every
-- referencing file, not just an exact require("proj.util") match (which
-- doesn't even occur here — nothing requires the directory itself).
local function run_lua_directory_cascade_check()
  print("\n== lua (directory rename, submodule cascade) ==")

  local work = scratch_root .. "/lua_dir_cascade"
  vim.fn.delete(work, "rf")
  copy_dir(fixtures_root .. "/lua", work)

  local old_dir = work .. "/lua/proj/util"
  local new_dir = work .. "/lua/proj/utilities"

  local done = false
  local smart_rename = require("filetree.features.fileops.smart_rename")
  smart_rename.setup({
    enabled = true, use_safety = false, dry_run = false, update_references = true,
  }, {
    get_current_node = function() return { path = old_dir, type = "directory" } end,
    refresh          = function() done = true end,
  })

  local orig_input = vim.ui.input
  vim.ui.input = function(_, on_confirm) on_confirm("utilities") end
  smart_rename.rename_current()
  vim.wait(3000, function() return done end, 20)
  vim.ui.input = orig_input

  check("lua dir cascade: directory renamed on disk", vim.fn.isdirectory(new_dir) == 1)
  check("lua dir cascade: old directory gone", vim.fn.isdirectory(old_dir) == 0)

  local cascade_checks = {
    { file = "lua/proj/a.lua",             old = 'require("proj.util.shared")', new = 'require("proj.utilities.shared")' },
    { file = "lua/proj/nested/b.lua",      old = 'require("proj.util.shared")', new = 'require("proj.utilities.shared")' },
    { file = "lua/proj/nested/deep/c.lua", old = 'require "proj.util.shared"',  new = 'require "proj.utilities.shared"' },
    -- "proj.util.shared_other" is itself a submodule of "proj.util" (the
    -- directory being renamed) even though its basename looks like the
    -- file-rename negative control above — renaming the whole directory
    -- must cascade to it too, unlike renaming just shared.lua.
    { file = "lua/proj/other/unrelated.lua", old = 'require("proj.util.shared_other")', new = 'require("proj.utilities.shared_other")' },
  }
  for _, c in ipairs(cascade_checks) do
    local content = read(work .. "/" .. c.file)
    if c.old == c.new then
      check(("lua dir cascade: %s unchanged (negative control)"):format(c.file),
        content ~= nil and content:find(c.old, 1, true) ~= nil)
    else
      check(("lua dir cascade: %s updated"):format(c.file),
        content ~= nil and content:find(c.new, 1, true) ~= nil,
        "missing " .. c.new)
      check(("lua dir cascade: %s old reference gone"):format(c.file),
        content ~= nil and old_fully_replaced(content, c.old, c.new),
        "still contains " .. c.old)
    end
  end
end

-- ── Run ───────────────────────────────────────────────────────────────────────
for _, lang in ipairs(LANGS) do
  run_lang(lang)
end
run_lua_buffer_check()
run_lua_directory_cascade_check()

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nsmart_rename_refs: %d passed, %d failed"):format(passed, failed))
if failed > 0 then vim.cmd("cq") else vim.cmd("qa!") end
