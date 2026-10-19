-- create_names_spec.lua -- `filetree.create_names`: name suggestions a plugin
-- registers for the create prompt (`smart_create`, `a`), and that the prompt
-- really is pre-filled with them.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/create_names_spec.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root)

local function prepend_dep(envs, sibling, lazy_name, marker)
  local candidates = {}
  for _, env in ipairs(envs) do
    local v = vim.env[env]
    if v and v ~= "" then candidates[#candidates + 1] = v end
  end
  candidates[#candidates + 1] = vim.fn.fnamemodify(root, ":h") .. "/" .. sibling
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/" .. lazy_name
  for _, c in ipairs(candidates) do
    if vim.fn.isdirectory(c .. marker) == 1 then
      vim.opt.rtp:prepend(c)
      return
    end
  end
end
prepend_dep(
  { "FILETREE_LIB_NVIM", "LIB_NVIM_PATH", "LIB_NVIM_DIR" },
  "lib.nvim",
  "lib.nvim",
  "/lua/lib"
)

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
  check(name, got == want, ("got %s want %s"):format(vim.inspect(got), vim.inspect(want)))
end

local names = require("filetree.create_names")

-- ── registry ────────────────────────────────────────────────────────────────

eq("no provider, no suggestion", names.suggest("/x/assets"), nil)

names.register("a", function(dir)
  if dir:match("/assets$") then return "03_2026-10-19/" end
end)
eq("a provider answers for its folders", names.suggest("/c/1234/assets"), "03_2026-10-19/")
eq("and stays out of the others", names.suggest("/c/1234/Research"), nil)

names.register("b", function()
  return "from b"
end)
eq("the first provider with an answer wins", names.suggest("/c/1234/assets"), "03_2026-10-19/")
eq("a later one answers where the first has nothing", names.suggest("/elsewhere"), "from b")

names.register("a", function()
  error("broken")
end)
eq(
  "a provider that raises is skipped (and re-registering replaced it)",
  names.suggest("/c/1234/assets"),
  "from b"
)

names.register("c", function()
  return ""
end)
names.unregister("b")
eq("an empty answer is no answer; unregister removes", names.suggest("/c/1234/assets"), nil)
names.unregister("a")
names.unregister("c")
names.unregister("never-registered")

-- ── the prompt is pre-filled ────────────────────────────────────────────────

local seen
package.loaded["ui.kit"] = {
  input = function(opts)
    seen = opts
  end,
}
local cwd = vim.fn.getcwd():gsub("\\", "/")
names.register("spec", function(dir)
  if dir == cwd then return "00_2026-10-19/" end
end)
local smart_create = require("filetree.features.fileops.smart_create")
smart_create.create()
eq("smart_create pre-fills the prompt with the suggestion", seen and seen.default, "00_2026-10-19/")
names.unregister("spec")
smart_create.create()
eq("and pre-fills nothing without one", seen and seen.default, nil)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
