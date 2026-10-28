-- Test code: a nil here must crash and name itself, not be guarded away.
---@diagnostic disable: need-check-nil
-- compress_spec.lua — headless tests for `features.system.compress`: zipping the
-- node under the cursor, or the marked nodes.
--
--   * `archiver.build()` is pure: the argv zip and bsdtar are handed is asserted on
--     every OS (one folder only for zip, one `-C` per source for bsdtar, a name
--     starting with `-` never read as an option);
--   * the naming: `<name>.zip` beside the source, `_2` instead of overwriting, the
--     answer to the "together" prompt, a zip refused inside a folder it compresses;
--   * the target choice (marks, else the cursor node, stale marks dropped) against
--     a stub adapter and a stub marks module;
--   * a real round trip with whichever tool this machine has (skipped without one):
--     a file and a folder end up in the zip, the sources stay.
--
-- Usage (from the repo root):
--   nvim -n --clean --headless -u NONE -l TESTS/compress_spec.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)
local lib_candidates = {}
for _, env in ipairs({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH", "LIB_NVIM_DIR" }) do
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

local TMP_ROOT = vim.env.TEMP or vim.env.TMPDIR or vim.env.TMP or "/tmp"

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
  check(
    name,
    vim.deep_equal(got, want),
    ("got %s want %s"):format(vim.inspect(got), vim.inspect(want))
  )
end

local archiver = require("filetree.features.system.compress.archiver")

local base = (TMP_ROOT .. "/ft-compress-" .. tostring(vim.uv.hrtime())):gsub("\\", "/")
vim.fn.mkdir(base .. "/dir/sub", "p")
vim.fn.mkdir(base .. "/other", "p")
vim.fn.writefile({ "alpha" }, base .. "/a.log")
vim.fn.writefile({ "beta" }, base .. "/dir/sub/b.txt")
vim.fn.writefile({ "gamma" }, base .. "/other/c.txt")

-- ── archiver.build ────────────────────────────────────────────────────────────

local ZIP = { kind = "zip", exe = "zip" }
local TAR = { kind = "bsdtar", exe = "tar.exe" }

do
  local cmd, cwd = archiver.build(ZIP, base .. "/x.zip", { base .. "/a.log", base .. "/dir" })
  eq("zip: recursive, quiet, best, names relative to the folder", cmd, {
    "zip",
    "-r",
    "-q",
    "-9",
    base .. "/x.zip",
    "a.log",
    "dir",
  })
  eq("zip: runs in the sources' folder", cwd, base)

  local none, why =
    archiver.build(ZIP, base .. "/x.zip", { base .. "/a.log", base .. "/other/c.txt" })
  eq("zip: sources from two folders give no command", none, nil)
  check(
    "zip: ... and say why",
    type(why) == "string" and why:find("one folder", 1, true) ~= nil,
    why
  )

  cmd, cwd = archiver.build(TAR, base .. "/x.zip", { base .. "/a.log", base .. "/other/c.txt" })
  eq("bsdtar: format from the suffix, one -C per source", cmd, {
    "tar.exe",
    "-a",
    "-c",
    "-f",
    base .. "/x.zip",
    "-C",
    base,
    "a.log",
    "-C",
    base .. "/other",
    "c.txt",
  })
  eq("bsdtar: no cwd needed", cwd, nil)

  cmd = archiver.build(TAR, base .. "/x.zip", { base .. "/-rf" })
  eq("a name starting with - is passed as ./name", cmd[#cmd], "./-rf")
  cmd = archiver.build(ZIP, base .. "/x.zip", { base .. "/-rf" })
  eq("... for zip too", cmd[#cmd], "./-rf")

  eq("nothing to compress gives no command", archiver.build(TAR, base .. "/x.zip", {}), nil)
end

-- ── naming ────────────────────────────────────────────────────────────────────

local compress = require("filetree.features.system.compress")

eq("free_path: a free name stays", archiver.free_path(base .. "/a.log.zip"), base .. "/a.log.zip")
vim.fn.writefile({}, base .. "/taken.zip")
eq(
  "free_path: a taken name gets _2",
  archiver.free_path(base .. "/taken.zip"),
  base .. "/taken_2.zip"
)
vim.fn.writefile({}, base .. "/taken_2.zip")
eq(
  "free_path: ... and _3 after that",
  archiver.free_path(base .. "/taken.zip"),
  base .. "/taken_3.zip"
)

check(
  "inside_source: a zip in a compressed folder",
  archiver.inside_source(base .. "/dir/x.zip", { base .. "/dir" })
)
check(
  "inside_source: a sibling with the same prefix is not inside",
  not archiver.inside_source(base .. "/dir2/x.zip", { base .. "/dir" })
)

eq(
  "jobs_each: <source>.zip beside each source",
  compress.jobs_each({ base .. "/a.log", base .. "/dir" }),
  {
    { out = base .. "/a.log.zip", sources = { base .. "/a.log" } },
    { out = base .. "/dir.zip", sources = { base .. "/dir" } },
  }
)
eq("jobs_each: an existing zip is not overwritten", compress.jobs_each({ base .. "/taken" }), {
  { out = base .. "/taken_3.zip", sources = { base .. "/taken" } },
})

local srcs = { base .. "/a.log", base .. "/dir" }
eq(
  "together_path: a bare name lands beside the first source",
  compress.together_path("logs", srcs),
  base .. "/logs.zip"
)
eq(
  "together_path: .zip is not doubled",
  compress.together_path(" logs.ZIP ", srcs),
  base .. "/logs.ZIP"
)
eq(
  "together_path: an absolute path is kept",
  compress.together_path(base .. "/other/all", srcs),
  base .. "/other/all.zip"
)

-- ── gather: marks, else the cursor node ───────────────────────────────────────

local marked = {}
package.loaded["filetree.features.org.marks"] = {
  count = function()
    return #marked
  end,
  get_marked = function()
    return vim.deepcopy(marked)
  end,
}
local cursor = { path = base .. "/dir/", type = "directory" }
local adapter = {
  get_current_node = function()
    return cursor
  end,
  refresh = function() end,
}
compress.setup({ enabled = true }, adapter)

eq(
  "gather: no marks -> the cursor node, without its trailing slash",
  compress.gather(),
  { base .. "/dir" }
)
marked = { base .. "/other/c.txt", base .. "/gone.txt", base .. "\\a.log" }
eq("gather: the marks in order, stale ones dropped, slashes unified", compress.gather(), {
  base .. "/other/c.txt",
  base .. "/a.log",
})
marked = {}

-- ── real round trip ───────────────────────────────────────────────────────────

local tool = archiver.detect()
if not tool then
  print("  skip real round trip: neither zip nor a bsdtar on this machine")
else
  local function listing(zip)
    local cmd = vim.fn.executable("unzip") == 1 and { "unzip", "-Z1", zip }
      or { tool.exe, "-t", "-f", zip }
    if tool.kind == "zip" and vim.fn.executable("unzip") == 0 then return nil end
    local res = vim.system(cmd, { text = true }):wait()
    local names = {}
    for line in (res.stdout or ""):gmatch("[^\r\n]+") do
      names[#names + 1] = (line:gsub("^%./", ""))
    end
    table.sort(names)
    return names
  end

  local function wait_for(p)
    return vim.wait(10000, function()
      return vim.uv.fs_stat(p) ~= nil
    end, 50)
  end

  -- One node: `gz` on the folder under the cursor.
  cursor = { path = base .. "/dir", type = "directory" }
  compress.compress()
  check("real (" .. tool.kind .. "): the folder's zip is written", wait_for(base .. "/dir.zip"))
  vim.wait(300)
  local names = listing(base .. "/dir.zip")
  if names then
    check(
      "real: the zip holds the folder with its contents",
      vim.tbl_contains(names, "dir/sub/b.txt"),
      vim.inspect(names)
    )
  end
  check("real: the source folder is left alone", vim.uv.fs_stat(base .. "/dir/sub/b.txt") ~= nil)

  -- Several marked nodes, "each".
  marked = { base .. "/a.log", base .. "/other/c.txt" }
  compress.compress("each")
  check("real each: a.log.zip", wait_for(base .. "/a.log.zip"))
  check("real each: c.txt.zip beside its source", wait_for(base .. "/other/c.txt.zip"))
  vim.wait(300)
  names = listing(base .. "/a.log.zip")
  if names then eq("real each: one zip holds one source", names, { "a.log" }) end
  check("real each: the sources stay", vim.uv.fs_stat(base .. "/a.log") ~= nil)
  marked = {}
end

vim.fn.delete(base, "rf")
print(string.format("\ncompress_spec: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
