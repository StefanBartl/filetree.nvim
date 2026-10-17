---@diagnostic disable: need-check-nil, missing-fields, duplicate-set-field
-- sibling_nav.lua — headless tests for the sibling jumps of
-- `filetree.features.nav.tree_traverse` (`]s` / `[s`).
--
-- Pins:
--   1. nested tree: the next/previous sibling skips the children of an
--      expanded sibling folder, and stops at the parent's last/first child;
--   2. from inside an expanded folder the jump stays among that folder's
--      children and never climbs out;
--   3. a count moves N siblings (clamped without wrap);
--   4. `sibling_wrap = true` wraps around inside the parent folder;
--   5. a flat listing (every node depth 1, as mini.files, netrw and oil
--      report it) degrades to plain next/previous;
--   6. the schema declares the three new options.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/sibling_nav.lua
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
local function same(name, got, want)
  check(name, got == want, ("got %s want %s"):format(vim.inspect(got), vim.inspect(want)))
end

-- ── doubles ───────────────────────────────────────────────────────────────────

vim.notify = function() end
-- Keymaps are not under test; binding them needs a real tree buffer.
package.loaded["filetree.util.bind"] = { bind = function() end }

-- Nested tree (indent = depth):
--   1 src/            (expanded)
--   2   a.lua
--   3   lib/          (expanded)
--   4     x.lua
--   5     y.lua
--   6   b.lua
--   7 docs/           (collapsed)
--   8 README.md
local NESTED = {
  { path = "/p/src", type = "directory", depth = 1, is_expanded = true },
  { path = "/p/src/a.lua", type = "file", depth = 2 },
  { path = "/p/src/lib", type = "directory", depth = 2, is_expanded = true },
  { path = "/p/src/lib/x.lua", type = "file", depth = 3 },
  { path = "/p/src/lib/y.lua", type = "file", depth = 3 },
  { path = "/p/src/b.lua", type = "file", depth = 2 },
  { path = "/p/docs", type = "directory", depth = 1, is_expanded = false },
  { path = "/p/README.md", type = "file", depth = 1 },
}

-- Flat listing, as the mini.files / netrw / oil adapters report it.
local FLAT = {
  { path = "/p/a", type = "directory", depth = 1 },
  { path = "/p/b.txt", type = "file", depth = 1 },
  { path = "/p/c.txt", type = "file", depth = 1 },
}

local function number(nodes)
  for i, n in ipairs(nodes) do
    n.line_number = i
    n.name = vim.fn.fnamemodify(n.path, ":t")
  end
end
number(NESTED)
number(FLAT)

local state = { nodes = NESTED, line = 1 }
local adapter = {
  name = "stub",
  is_open = function()
    return true, nil
  end,
  get_visible_nodes = function()
    return state.nodes
  end,
  get_current_node = function()
    return state.nodes[state.line]
  end,
  scroll_to_line = function(line)
    state.line = line
    return true
  end,
}

local function fresh(cfg)
  package.loaded["filetree.features.nav.tree_traverse"] = nil
  local M = require("filetree.features.nav.tree_traverse")
  M.setup(vim.tbl_extend("force", { enabled = true }, cfg or {}), adapter)
  return M
end

---Put the cursor on `path`, jump, return the path the cursor lands on.
local function jump(M, from, step, count)
  for i, n in ipairs(state.nodes) do
    if n.path == from then state.line = i end
  end
  M.sibling(step, count)
  return state.nodes[state.line].path
end

-- ── 1. nested tree: skip the children of an expanded sibling ─────────────────

do
  print("\n-- nested tree, no wrap --")
  state.nodes = NESTED
  local M = fresh()
  same("src -> docs skips src's whole subtree", jump(M, "/p/src", 1), "/p/docs")
  same("docs -> src skips src's whole subtree back", jump(M, "/p/docs", -1), "/p/src")
  same("a.lua -> lib", jump(M, "/p/src/a.lua", 1), "/p/src/lib")
  same("lib -> b.lua skips lib's children", jump(M, "/p/src/lib", 1), "/p/src/b.lua")
  same("b.lua -> lib skips lib's children back", jump(M, "/p/src/b.lua", -1), "/p/src/lib")
  same("README (last) stays put", jump(M, "/p/README.md", 1), "/p/README.md")
  same("src (first) stays put backwards", jump(M, "/p/src", -1), "/p/src")
  M.teardown()
end

-- ── 2. inside an expanded folder: never climbs out ───────────────────────────

do
  print("\n-- inside an expanded folder --")
  state.nodes = NESTED
  local M = fresh()
  same("x.lua -> y.lua", jump(M, "/p/src/lib/x.lua", 1), "/p/src/lib/y.lua")
  same("y.lua (last child) stays put", jump(M, "/p/src/lib/y.lua", 1), "/p/src/lib/y.lua")
  same("b.lua (last child of src) does not reach docs", jump(M, "/p/src/b.lua", 1), "/p/src/b.lua")
  M.teardown()
end

-- ── 3. count ──────────────────────────────────────────────────────────────────

do
  print("\n-- count --")
  state.nodes = NESTED
  local M = fresh()
  same("2]s from src lands on README", jump(M, "/p/src", 1, 2), "/p/README.md")
  same("9]s clamps at the last sibling", jump(M, "/p/src", 1, 9), "/p/README.md")
  M.teardown()
end

-- ── 4. wrap ───────────────────────────────────────────────────────────────────

do
  print("\n-- sibling_wrap = true --")
  state.nodes = NESTED
  local M = fresh({ sibling_wrap = true })
  same("README (last) wraps to src", jump(M, "/p/README.md", 1), "/p/src")
  same("src (first) wraps back to README", jump(M, "/p/src", -1), "/p/README.md")
  same("b.lua wraps to a.lua inside src", jump(M, "/p/src/b.lua", 1), "/p/src/a.lua")
  same("y.lua wraps to x.lua inside lib", jump(M, "/p/src/lib/y.lua", 1), "/p/src/lib/x.lua")
  M.teardown()
end

-- ── 5. flat listing ───────────────────────────────────────────────────────────

do
  print("\n-- flat listing --")
  state.nodes = FLAT
  local M = fresh()
  same("a -> b.txt", jump(M, "/p/a", 1), "/p/b.txt")
  same("c.txt -> b.txt", jump(M, "/p/c.txt", -1), "/p/b.txt")
  same("c.txt (last) stays put", jump(M, "/p/c.txt", 1), "/p/c.txt")
  M.teardown()
end

-- ── 6. schema ─────────────────────────────────────────────────────────────────

do
  print("\n-- schema --")
  local M = fresh()
  same("keymap_next_sibling is a keymap option", M.SCHEMA.keymap_next_sibling, "keymap")
  same("keymap_prev_sibling is a keymap option", M.SCHEMA.keymap_prev_sibling, "keymap")
  same("sibling_wrap is a boolean option", M.SCHEMA.sibling_wrap, "boolean")
  M.teardown()
end

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
