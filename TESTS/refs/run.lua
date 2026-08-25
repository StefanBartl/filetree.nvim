-- run.lua — regression test for the reference engine (lua/filetree/refs) and
-- the features that drive it.
--
-- For each language under fixtures/<lang>/ it copies the fixture tree to a
-- scratch dir, renames (or moves) the "hub" file through the real feature —
-- smart_rename / move, with a stubbed adapter and a stubbed kit.input, so no
-- tree plugin, no LSP server and no floating window are involved — and then
-- asserts that every referencing file was rewritten, and that a
-- similar-but-different name was NOT touched (negative control, guards against
-- loose matching).
--
-- The engine runs in `auto` mode here: the chooser (Update all / Select… /
-- Show diff / Leave as-is) is a UI concern covered in test/units.lua, and what
-- this suite is about is what actually lands on disk.
--
-- Usage (from the filetree.nvim repo root):
--   nvim --clean --headless -u NONE -l TESTS/refs/run.lua
--
-- Exit 0 = all passed, 1 = a check failed.
--
-- To add another language: add a fixtures/<lang>/ tree with a project marker
-- file (see project_root's marker list — .luarc.json, pyproject.toml,
-- package.json, Cargo.toml, go.mod, ... all work) and a LANGS entry below
-- pointing at the hub file + the files that reference it. A language the
-- engine has no provider for yet needs one first (lua/filetree/refs/providers).

-- ── Locate the repo root relative to this file, put it on rtp ────────────────
local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h:h")
vim.opt.rtp:prepend(root)

-- lib.nvim resolution: $LIB_NVIM_PATH -> sibling checkout -> lazy.nvim's
-- managed copy (see lib.nvim/templates/resolve_lib_nvim.lua for the
-- canonical copy of this function and the other caller patterns).
local function add_lib_nvim()
  local candidates = {}
  if vim.env.LIB_NVIM_PATH then candidates[#candidates + 1] = vim.env.LIB_NVIM_PATH end
  candidates[#candidates + 1] = vim.fn.fnamemodify(root, ":h") .. "/lib.nvim"
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"

  for _, path in ipairs(candidates) do
    local norm = vim.fs.normalize(path)
    if vim.fn.isdirectory(norm .. "/lua/lib") == 1 then
      vim.opt.rtp:prepend(norm)
      package.path = table.concat({
        norm .. "/lua/?.lua",
        norm .. "/lua/?/init.lua",
        package.path,
      }, ";")
      return norm
    end
  end
  return nil
end

add_lib_nvim()

local fixtures_root = vim.fn.fnamemodify(this, ":p:h") .. "/fixtures"
local scratch_root = (vim.fn.has("win32") == 1 and vim.env.TEMP or "/tmp") .. "/filetree-refs-test"

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
  if new:sub(1, #old) == old then return count_sub(content, old) == count_sub(content, new) end
  return content:find(old, 1, true) == nil
end

-- ── UI stubs ─────────────────────────────────────────────────────────────────
-- kit.input opens a real floating prompt in insert mode, which headless Neovim
-- cannot drive; kit.confirm likewise. Both are replaced by scripted answers.
local kit = require("lib.nvim.ui.kit")
local next_input, next_choice = nil, nil
kit.input = function(opts)
  if next_input ~= nil and opts.on_submit then opts.on_submit(next_input) end
  return nil
end
kit.confirm = function(opts)
  if opts.on_answer then opts.on_answer(next_choice) end
  return nil
end

-- Auto mode: apply every found reference without asking, so the assertions
-- below are about what the providers found, not about the chooser.
local refs = require("filetree.refs")
refs.setup({
  on_rename = "auto",
  on_move = "auto",
  on_delete = "auto",
  providers = { markdown = true, lua = true, python = true, ts_js = true },
  wiki_links = false,
})

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
    name = "lua",
    hub = "lua/proj/util/shared.lua",
    new_name = "shared_utils.lua",
    checks = {
      {
        file = "lua/proj/a.lua",
        old = 'require("proj.util.shared")',
        new = 'require("proj.util.shared_utils")',
      },
      {
        file = "lua/proj/nested/b.lua",
        old = 'require("proj.util.shared")',
        new = 'require("proj.util.shared_utils")',
      },
      {
        file = "lua/proj/nested/deep/c.lua",
        old = 'require "proj.util.shared"',
        new = 'require "proj.util.shared_utils"',
      },
      {
        file = "lua/proj/other/unrelated.lua",
        old = 'require("proj.util.shared_other")',
        new = 'require("proj.util.shared_other")',
      },
    },
  },
  {
    name = "python",
    hub = "pkg/util/shared.py",
    new_name = "shared_utils.py",
    checks = {
      {
        file = "pkg/a.py",
        old = "from pkg.util.shared import greet",
        new = "from pkg.util.shared_utils import greet",
      },
      {
        file = "pkg/nested/b.py",
        old = "import pkg.util.shared",
        new = "import pkg.util.shared_utils",
      },
      {
        file = "pkg/other/unrelated.py",
        old = "from pkg.util.shared_other import greet",
        new = "from pkg.util.shared_other import greet",
      },
    },
  },
  {
    name = "ts",
    hub = "src/util/shared.ts",
    new_name = "shared_utils.ts",
    checks = {
      {
        file = "src/a.ts",
        old = 'from "./util/shared"',
        new = 'from "./util/shared_utils"',
      },
      {
        file = "src/nested/b.ts",
        old = 'from "../util/shared"',
        new = 'from "../util/shared_utils"',
      },
      {
        file = "src/nested/deep/c.tsx",
        old = 'from "../../util/shared"',
        new = 'from "../../util/shared_utils"',
      },
      {
        file = "src/other/d.js",
        old = 'import("../util/shared")',
        new = 'import("../util/shared_utils")',
      },
      {
        file = "src/other/unrelated.ts",
        old = 'from "../util/shared_other"',
        new = 'from "../util/shared_other"',
      },
    },
  },
  {
    name = "markdown",
    hub = "docs/guide.md",
    new_name = "manual.md",
    checks = {
      -- every link form the provider claims to cover, all pointing at the
      -- same moved file from two different directories
      {
        file = "README.md",
        old = "[the guide](./docs/guide.md)",
        new = "[the guide](./docs/manual.md)",
      },
      {
        file = "README.md",
        old = '<a href="./docs/guide.md">',
        new = '<a href="./docs/manual.md">',
      },
      {
        file = "README.md",
        old = "[guide-ref]: ./docs/guide.md",
        new = "[guide-ref]: ./docs/manual.md",
      },
      { file = "docs/notes.md", old = "[guide](guide.md)", new = "[guide](manual.md)" },
      -- negative controls: an external URL that merely contains the same
      -- path, and a same-named file in a different directory
      {
        file = "README.md",
        old = "https://example.com/docs/guide.md",
        new = "https://example.com/docs/guide.md",
      },
      {
        file = "README.md",
        old = "[other](./docs/guides/guide.md)",
        new = "[other](./docs/guides/guide.md)",
      },
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
  -- The reference scan and the rename are asynchronous; adapter.refresh() is
  -- the last thing do_rename calls before its final notify, so it is the
  -- "fully done" signal (filereadable(hub_new) flips earlier).
  local done = false
  local stub_adapter = {
    get_current_node = function()
      return { path = hub_old, type = "file" }
    end,
    refresh = function()
      done = true
    end,
  }
  smart_rename.setup({ enabled = true, use_safety = false, dry_run = false }, stub_adapter)

  next_input = lang.new_name
  smart_rename.rename_current()
  vim.wait(5000, function()
    return done
  end, 20)

  check(lang.name .. ": hub file renamed on disk", vim.fn.filereadable(hub_new) == 1)
  check(lang.name .. ": old hub path gone", vim.fn.filereadable(hub_old) == 0)

  for _, c in ipairs(lang.checks) do
    local content = read(work .. "/" .. c.file)
    if c.old == c.new then
      check(
        ("%s: %s keeps %s (negative control)"):format(lang.name, c.file, c.old),
        content ~= nil and content:find(c.old, 1, true) ~= nil
      )
    else
      check(
        ("%s: %s updated"):format(lang.name, c.file),
        content ~= nil and content:find(c.new, 1, true) ~= nil,
        "missing " .. c.new
      )
      check(
        ("%s: %s old reference gone"):format(lang.name, c.file),
        content ~= nil and old_fully_replaced(content, c.old, c.new),
        "still contains " .. c.old
      )
    end
  end
end

-- ── Bonus: verify the open-buffer branch (not just on-disk files) ────────────
-- refs.apply patches loaded buffers via nvim_buf_set_lines instead of going
-- through disk I/O; exercise that path once, for Lua.
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
  smart_rename.setup({ enabled = true, use_safety = false, dry_run = false }, {
    get_current_node = function()
      return { path = hub_old, type = "file" }
    end,
    refresh = function()
      done = true
    end,
  })

  next_input = "shared_utils.lua"
  smart_rename.rename_current()
  vim.wait(5000, function()
    return done
  end, 20)

  local buf_content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  check(
    "lua buffer: open buffer patched in-memory",
    buf_content:find('require("proj.util.shared_utils")', 1, true) ~= nil,
    "buffer content: " .. buf_content
  )

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
  smart_rename.setup({ enabled = true, use_safety = false, dry_run = false }, {
    get_current_node = function()
      return { path = old_dir, type = "directory" }
    end,
    refresh = function()
      done = true
    end,
  })

  next_input = "utilities"
  smart_rename.rename_current()
  vim.wait(5000, function()
    return done
  end, 20)

  check("lua dir cascade: directory renamed on disk", vim.fn.isdirectory(new_dir) == 1)
  check("lua dir cascade: old directory gone", vim.fn.isdirectory(old_dir) == 0)

  local cascade_checks = {
    {
      file = "lua/proj/a.lua",
      old = 'require("proj.util.shared")',
      new = 'require("proj.utilities.shared")',
    },
    {
      file = "lua/proj/nested/b.lua",
      old = 'require("proj.util.shared")',
      new = 'require("proj.utilities.shared")',
    },
    {
      file = "lua/proj/nested/deep/c.lua",
      old = 'require "proj.util.shared"',
      new = 'require "proj.utilities.shared"',
    },
    -- "proj.util.shared_other" is itself a submodule of "proj.util" (the
    -- directory being renamed) even though its basename looks like the
    -- file-rename negative control above — renaming the whole directory
    -- must cascade to it too, unlike renaming just shared.lua.
    {
      file = "lua/proj/other/unrelated.lua",
      old = 'require("proj.util.shared_other")',
      new = 'require("proj.utilities.shared_other")',
    },
  }
  for _, c in ipairs(cascade_checks) do
    local content = read(work .. "/" .. c.file)
    check(
      ("lua dir cascade: %s updated"):format(c.file),
      content ~= nil and content:find(c.new, 1, true) ~= nil,
      "missing " .. c.new
    )
    check(
      ("lua dir cascade: %s old reference gone"):format(c.file),
      content ~= nil and old_fully_replaced(content, c.old, c.new),
      "still contains " .. c.old
    )
  end
end

-- ── The `move` feature (M): move into a directory, then undo the rewrite ────
local function run_move_feature_check()
  print("\n== move (M) + refs undo ==")

  local work = scratch_root .. "/move"
  vim.fn.delete(work, "rf")
  copy_dir(fixtures_root .. "/markdown", work)

  -- README.md links to ./docs/guide.md; moving docs/notes.md up to the root
  -- must rewrite the link that points at it from README.md.
  local src = work .. "/docs/notes.md"
  local dst = work .. "/notes.md"
  vim.fn.writefile({ "Notes live at [notes](./docs/notes.md)." }, work .. "/index.md")

  local move = require("filetree.features.fileops.move")
  local done = false
  move.setup({ enabled = true, use_safety = false, dry_run = false }, {
    get_current_node = function()
      return { path = src, type = "file" }
    end,
    refresh = function()
      done = true
    end,
  })

  -- ":Filetree move <dest>" path — no prompt involved, so nothing to stub.
  move.move(work)
  vim.wait(5000, function()
    return done
  end, 20)

  check("move: file moved into the destination directory", vim.fn.filereadable(dst) == 1)
  check("move: source is gone", vim.fn.filereadable(src) == 0)

  local index = read(work .. "/index.md")
  check(
    "move: reference rewritten to the new location",
    index ~= nil and index:find("[notes](./notes.md)", 1, true) ~= nil,
    index
  )

  -- …and the undo token puts the reference back, byte for byte.
  refs.undo()
  local reverted = read(work .. "/index.md")
  check(
    "move: refs undo restores the previous line",
    reverted ~= nil and reverted:find("[notes](./docs/notes.md)", 1, true) ~= nil,
    reverted
  )
end

-- ── Run ───────────────────────────────────────────────────────────────────────
for _, lang in ipairs(LANGS) do
  run_lang(lang)
end
run_lua_buffer_check()
run_lua_directory_cascade_check()
run_move_feature_check()

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nrefs: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
