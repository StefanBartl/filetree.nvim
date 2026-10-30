-- TESTS/refs/slow_scan_spec.lua -- TESTS/refs/run.lua must not race its own
-- asynchronous reference scan.
--
-- run.lua used to wait a fixed 2-5 s for each scan and then check the files
-- anyway. On a loaded machine the scan (the plaintext provider is the heaviest)
-- took longer, and the half-finished rename was reported as wrong content
-- ("docs/index.md updated -- missing ../notes/Renamed.md"), on and off for the
-- same tree. This spec runs the plaintext case of run.lua in a child process
-- with every scan result held back 6 s -- longer than the old limit -- and
-- asserts that it still passes, and that a wait which really does run out is
-- reported as a TIMEOUT of its own and not as a content check.
--
--   nvim --clean --headless -u NONE -l TESTS/refs/slow_scan_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local run_lua = vim.fn.fnamemodify(this, ":p:h") .. "/run.lua"

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

---Run the plaintext case of run.lua with the given extra environment.
---@param env table<string, string>
---@return integer code, string out
local function run(env)
  env = vim.tbl_extend("force", { FILETREE_REFS_TEST_ONLY = "plaintext" }, env)
  local res = vim
    .system({ vim.v.progpath, "--clean", "--headless", "-u", "NONE", "-l", run_lua }, {
      env = env,
      text = true,
    })
    :wait(120000)
  return res.code, (res.stdout or "") .. (res.stderr or "")
end

---@param out string
---@return string[]
local function fail_lines(out)
  local lines = {}
  for line in out:gmatch("[^\r\n]+") do
    if line:find("^%s*FAIL ") then lines[#lines + 1] = line end
  end
  return lines
end

print("\n== a scan slower than the old fixed 5 s wait ==")
do
  local code, out = run({ FILETREE_REFS_TEST_SCAN_DELAY_MS = "6000" })
  check("run.lua exits 0", code == 0, ("exit %d\n%s"):format(code, out))
  check("no check failed", #fail_lines(out) == 0, table.concat(fail_lines(out), " | "))
  check(
    "the plaintext rewrites were checked at all",
    out:find("ok   plaintext: docs/index.md updated", 1, true) ~= nil,
    out
  )
end

print("\n== a wait that really runs out ==")
do
  local code, out = run({
    FILETREE_REFS_TEST_SCAN_DELAY_MS = "3000",
    FILETREE_REFS_TEST_WAIT_MS = "500",
  })
  local fails = fail_lines(out)
  check("run.lua exits non-zero", code ~= 0, ("exit %d"):format(code))
  check(
    "the only FAIL is the TIMEOUT",
    #fails == 1 and fails[1]:find("FAIL TIMEOUT waiting for", 1, true) ~= nil,
    table.concat(fails, " | ")
  )
  -- A failed run keeps its scratch dir for inspection; it is unique per run.
  local kept = out:match("scratch dir kept for inspection: ([^\r\n]+)")
  check(
    "the scratch dir is per run (pid + hrtime)",
    kept ~= nil and kept:find("filetree%-refs%-test%-%d+%-%d+$") ~= nil,
    tostring(kept)
  )
  if kept then vim.fn.delete(kept, "rf") end
end

print(("\nfiletree.nvim refs/slow_scan_spec: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
