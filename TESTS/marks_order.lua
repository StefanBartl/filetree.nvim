---@diagnostic disable: need-check-nil, missing-fields, duplicate-set-field
-- marks_order.lua — headless tests for `marks.order`, the order in which the
-- marked set is handed to every consumer (`filetree.features.org.marks`).
--
-- Pins:
--   1. default "marked": three marks set in a scrambled order come back in
--      exactly that order; unmark + re-mark moves a path to the end;
--   2. bulk marks (mark all visible) number only the NEW nodes, in tree
--      order, behind the existing marks -- folders and files alike;
--   3. the switch: `order = "tree"` returns the old path-sorted output, and
--      an invalid value is rejected by the schema;
--   4. end to end: path_copy (the `[e` / copy-path family) puts the lines on
--      the clipboard in mark order.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/marks_order.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)

-- One ordered list, first hit wins: the environment overrides a sibling
-- checkout, which overrides lazy.nvim's copy.
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
local function same(name, got, want)
  check(
    name,
    vim.deep_equal(got, want),
    ("got %s want %s"):format(vim.inspect(got), vim.inspect(want))
  )
end

-- ── doubles ───────────────────────────────────────────────────────────────────

vim.notify = function() end
package.loaded["ui.kit"] = { viewer = function() end }
-- Keymaps are not under test; binding them needs a real tree buffer.
package.loaded["filetree.util.bind"] = { bind = function() end }

local TREE_BUF = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(TREE_BUF)

-- Tree order: a folder first, then files. Deliberately NOT alphabetical by
-- full path for the files, so "tree"/"marked"/"sorted" are all distinguishable.
local NODES = {
  { path = "/proj/docs", type = "directory" },
  { path = "/proj/eins.md", type = "file" },
  { path = "/proj/beins.md", type = "file" },
  { path = "/proj/zeins.md", type = "file" },
  { path = "/proj/assets", type = "directory" },
}
for i, n in ipairs(NODES) do
  n.line_number = i
  n.name = vim.fn.fnamemodify(n.path, ":t")
end
vim.api.nvim_buf_set_lines(
  TREE_BUF,
  0,
  -1,
  false,
  vim.tbl_map(function(n)
    return n.name
  end, NODES)
)

local adapter = {
  name = "stub",
  is_open = function()
    return true, TREE_BUF
  end,
  get_visible_nodes = function()
    return NODES
  end,
  get_current_node = function()
    return NODES[1]
  end,
}

local function fresh_marks(cfg)
  package.loaded["filetree.features.org.marks"] = nil
  local M = require("filetree.features.org.marks")
  M.setup(vim.tbl_extend("force", { enabled = true, auto_clear_ms = 0 }, cfg or {}), adapter)
  return M
end

-- ── 1. default: mark order ────────────────────────────────────────────────────

do
  print("\n-- default order = marked --")
  local M = fresh_marks()
  M.toggle("/proj/beins.md")
  M.toggle("/proj/zeins.md")
  M.toggle("/proj/eins.md")
  same(
    "three marks come back in the order they were set",
    M.get_marked(),
    { "/proj/beins.md", "/proj/zeins.md", "/proj/eins.md" }
  )

  M.toggle("/proj/beins.md") -- unmark
  M.toggle("/proj/beins.md") -- re-mark
  same(
    "unmark + re-mark moves the path to the end",
    M.get_marked(),
    { "/proj/zeins.md", "/proj/eins.md", "/proj/beins.md" }
  )
  check("is_marked still answers true", M.is_marked("/proj/beins.md"))
  check("an unmarked path is not marked", not M.is_marked("/proj/docs"))

  M.clear_all()
  same("clear_all empties the set", M.get_marked(), {})
  M.toggle("/proj/eins.md")
  same("numbering restarts cleanly after a clear", M.get_marked(), { "/proj/eins.md" })
  M.teardown()
end

-- ── 2. bulk marks, folders and files mixed ────────────────────────────────────

do
  print("\n-- bulk marks: mixed folders/files --")
  local M = fresh_marks()
  M.toggle("/proj/zeins.md")
  M.toggle("/proj/assets")
  M.mark_all_visible()
  same("existing marks keep their place, new ones follow in tree order", M.get_marked(), {
    "/proj/zeins.md",
    "/proj/assets",
    "/proj/docs",
    "/proj/eins.md",
    "/proj/beins.md",
  })
  M.unmark_all_visible()
  same("unmark all visible clears them", M.get_marked(), {})
  M.toggle("/proj/assets")
  M.toggle("/proj/eins.md")
  M.toggle("/proj/docs")
  same(
    "folder, file, folder in mark order",
    M.get_marked(),
    { "/proj/assets", "/proj/eins.md", "/proj/docs" }
  )
  M.teardown()
end

-- ── 3. the switch ─────────────────────────────────────────────────────────────

do
  print("\n-- order = tree --")
  local M = fresh_marks({ order = "tree" })
  M.toggle("/proj/zeins.md")
  M.toggle("/proj/docs")
  M.toggle("/proj/beins.md")
  same(
    "order = tree sorts by full path (the old behaviour)",
    M.get_marked(),
    { "/proj/beins.md", "/proj/docs", "/proj/zeins.md" }
  )
  M.teardown()

  local schema = require("filetree.config.schema")
  local issues = {}
  local clean = schema.check_feature("marks", { order = "random" }, issues)
  check("an invalid order is reported", #issues == 1, vim.inspect(issues))
  check("...and dropped", clean.order == nil, vim.inspect(clean))
  issues = {}
  schema.check_feature("marks", { order = "tree" }, issues)
  check("order = tree validates", #issues == 0, vim.inspect(issues))

  local defaults = require("filetree.config.DEFAULTS")
  check(
    "DEFAULTS carries order = marked",
    defaults.features.marks and defaults.features.marks.order == "marked"
  )
end

-- ── 4. end to end: path_copy ──────────────────────────────────────────────────

do
  print("\n-- path_copy follows mark order --")
  local M = fresh_marks()
  M.toggle("/proj/beins.md")
  M.toggle("/proj/zeins.md")
  M.toggle("/proj/eins.md")
  local pc = require("filetree.features.paths.path_copy")
  pc.setup({ enabled = true, notify = false, root_markers = false }, adapter)
  pc.copy_name()
  same(
    "copy name: clipboard lines in mark order",
    vim.split(vim.fn.getreg('"'), "\n"),
    { "beins.md", "zeins.md", "eins.md" }
  )
  pc.copy_absolute()
  local abs = vim.split(vim.fn.getreg('"'), "\n")
  local tails = vim.tbl_map(function(p)
    return vim.fn.fnamemodify(p, ":t")
  end, abs)
  same("copy absolute: same order", tails, { "beins.md", "zeins.md", "eins.md" })
  pc.teardown()
  M.teardown()
end

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
