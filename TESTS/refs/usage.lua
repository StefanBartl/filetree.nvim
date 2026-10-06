---@diagnostic disable: need-check-nil
-- usage.lua -- regression test for `filetree.refs.usage`, the batched
-- reference counter behind `:Filetree references`, `:Filetree refs unused` and
-- the `I` node info section.
--
-- A throwaway project is built in a scratch dir (referenced, twice-referenced,
-- unreferenced, self-referencing and look-alike files), then counted once with
-- ripgrep and once through the ripgrep-free walk fallback -- both backends
-- must agree.
--
-- Usage (from the filetree.nvim repo root):
--   nvim --clean --headless -u NONE -l TESTS/refs/usage.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h:h")
vim.opt.rtp:prepend(root)

-- Dependency resolution, same candidate order as TESTS/refs/run.lua.
local function add_dep(dir_name, env_names, probe)
  local candidates = {}
  for _, env in ipairs(env_names) do
    local v = vim.env[env]
    if v and v ~= "" then candidates[#candidates + 1] = v end
  end
  candidates[#candidates + 1] = vim.fn.fnamemodify(root, ":h") .. "/" .. dir_name
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/" .. dir_name
  for _, path in ipairs(candidates) do
    local norm = vim.fs.normalize(path)
    if vim.fn.isdirectory(norm .. probe) == 1 then
      vim.opt.rtp:prepend(norm)
      package.path =
        table.concat({ norm .. "/lua/?.lua", norm .. "/lua/?/init.lua", package.path }, ";")
      return
    end
  end
end
add_dep("lib.nvim", { "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }, "/lua/lib")
add_dep("ui.nvim", { "FILETREE_UI_NVIM", "UI_NVIM_PATH" }, "/lua/ui")

local scratch_root = (vim.fn.has("win32") == 1 and vim.env.TEMP or "/tmp") .. "/filetree-usage-test"
do
  local uv = vim.uv or vim.loop
  vim.fn.mkdir(scratch_root, "p")
  local real = uv.fs_realpath(scratch_root)
  if real then scratch_root = (real:gsub("\\", "/")) end
end

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local refs = require("filetree.refs")
refs.setup({
  providers = { markdown = true, lua = true, python = false, ts_js = false },
  -- A report must not depend on the rewrite-on-mutation switches.
  enabled = false,
  on_delete = "off",
})

-- ── Fixture ───────────────────────────────────────────────────────────────────
local work = scratch_root .. "/project"
vim.fn.delete(work, "rf")
vim.fn.mkdir(work .. "/assets", "p")
vim.fn.mkdir(work .. "/bulk", "p")
vim.fn.mkdir(work .. "/lua/mod", "p")
vim.fn.writefile({ "[tool.filetree]" }, work .. "/pyproject.toml")
for _, name in ipairs({
  "used.png",
  "twice.png",
  "orphan.png",
  "shot.png",
  "my shot.png",
  "self.png",
}) do
  vim.fn.writefile({ "x" }, work .. "/assets/" .. name)
end
vim.fn.writefile({
  "One: ![u](assets/used.png)",
  "Twice here: ![t](assets/twice.png) and again ![t](assets/twice.png)",
  "Spaced: ![s](assets/my%20shot.png)",
  -- Look-alike: `shot.png` is a substring of `myshot.png`, which is not it.
  "Look-alike: ![x](assets/myshot.png)",
  "Self: [me](doc.md)",
}, work .. "/doc.md")
vim.fn.writefile({ "![t](assets/twice.png)" }, work .. "/other.md")
vim.fn.writefile({ "I am [self](../assets/self.png)" }, work .. "/assets/note.md")
vim.fn.writefile({ "return {}" }, work .. "/lua/mod/util.lua")
vim.fn.writefile({ 'local u = require("mod.util")', "return u" }, work .. "/lua/mod/init.lua")

-- Enough long-named files that the combined needles exceed the argv limit and
-- take the stdin path of `scan.candidates`.
local bulk_ref
for i = 1, 400 do
  local name = string.format("bulk/screenshot_%04d_with_a_rather_long_descriptive_name.png", i)
  vim.fn.writefile({ "x" }, work .. "/" .. name)
  if i == 217 then bulk_ref = name end
end
vim.fn.writefile({ "![b](" .. bulk_ref .. ")" }, work .. "/bulk-user.md")

local function p(rel)
  return work .. "/" .. rel
end

---@return table<string, FiletreeRefUsage>, FiletreeRefUsageMeta
local function count(paths)
  local got, meta, done = nil, nil, false
  refs.usage.count(paths, { root = work }, function(by_path, m)
    got, meta, done = by_path, m, true
  end)
  vim.wait(20000, function()
    return done
  end, 10)
  return got, meta
end

local function basename_set(files)
  local set = {}
  for _, f in ipairs(files) do
    set[f:match("([^/]+)$")] = true
  end
  return set
end

local function run(label)
  print("\n== refs.usage (" .. label .. ") ==")
  local paths = {
    p("assets/used.png"),
    p("assets/twice.png"),
    p("assets/orphan.png"),
    p("assets/shot.png"),
    p("assets/my shot.png"),
    p("assets/self.png"),
    p("lua/mod/util.lua"),
  }
  local u, meta = count(paths)
  check(label .. ": result returned", u ~= nil)
  if not u then return end

  check(label .. ": once-referenced counts 1", u[p("assets/used.png")].count == 1)
  check(
    label .. ": twice-in-one-file plus once elsewhere counts 3 sites in 2 files",
    u[p("assets/twice.png")].count == 3 and #u[p("assets/twice.png")].files == 2
  )
  check(label .. ": unreferenced counts 0 with an entry", u[p("assets/orphan.png")].count == 0)
  check(
    label .. ": look-alike myshot.png does not count for shot.png",
    u[p("assets/shot.png")].count == 0
  )
  check(label .. ": url-encoded space is found", u[p("assets/my shot.png")].count == 1)
  local self_files = basename_set(u[p("assets/self.png")].files)
  check(
    label .. ": a link from a sibling note counts",
    u[p("assets/self.png")].count == 1 and self_files["note.md"]
  )
  check(label .. ": lua module referenced by require counts 1", u[p("lua/mod/util.lua")].count == 1)

  local doc = count({ p("doc.md") })
  check(label .. ": a file linking to itself is not counted", doc[p("doc.md")].count == 0)

  local refs_of_twice = u[p("assets/twice.png")].refs
  check(
    label .. ": refs are sorted by file then line",
    #refs_of_twice == 3
      and refs_of_twice[1].file <= refs_of_twice[2].file
      and (
        refs_of_twice[1].file ~= refs_of_twice[2].file
        or refs_of_twice[1].line <= refs_of_twice[2].line
      )
  )

  local bulk_paths = {}
  for i = 1, 400 do
    bulk_paths[i] =
      p(string.format("bulk/screenshot_%04d_with_a_rather_long_descriptive_name.png", i))
  end
  local b = count(bulk_paths)
  local referenced, total_sites = 0, 0
  for _, path in ipairs(bulk_paths) do
    if b[path].count > 0 then referenced = referenced + 1 end
    total_sites = total_sites + b[path].count
  end
  check(
    label .. ": 400-path sweep finds exactly the one referenced file",
    referenced == 1 and total_sites == 1 and b[p(bulk_ref)].count == 1
  )

  check(
    label .. ": meta lists the providers that ran",
    meta and vim.tbl_contains(meta.providers, "markdown") and meta.files_scanned > 0
  )

  local empty_done = false
  refs.usage.count({}, nil, function(by_path)
    empty_done = next(by_path) == nil
  end)
  check(label .. ": empty input answers immediately", empty_done)
end

run("ripgrep")

local real_executable = vim.fn.executable
---@diagnostic disable-next-line: duplicate-set-field
vim.fn.executable = function(name)
  if name == "rg" then return 0 end
  return real_executable(name)
end
run("walk fallback")
vim.fn.executable = real_executable

print(("\nrefs.usage: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
