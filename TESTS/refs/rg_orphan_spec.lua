-- TESTS/refs/rg_orphan_spec.lua -- no ripgrep search outlives the editor that
-- started it.
--
-- `filetree.refs.scan` runs ripgrep through `vim.system`. Neovim does not stop
-- such a child on exit (POSIX), and on Windows a Scoop shim between the editor
-- and ripgrep let ripgrep escape the job object that would kill it, so a search
-- still running at `:qa` (a test ending while another plan of the same rename
-- is in flight) kept running -- holding the editor's inherited stdout, so
-- `scripts/test.sh | tail` never returned.
--
-- The "ripgrep" here is a sleeping nvim: a child editor swaps it in for rg via a
-- `vim.system` double, records its pid, and quits mid-search. The sleeper must be
-- gone afterwards. A second case checks the scan's own timeout kills it too.
-- On Windows libuv's job object already kills a direct child at exit, so the
-- exit case guards the VimLeavePre kill on POSIX; the shim case at the end is
-- the Windows half (the leak found there came through a Scoop shim).
--
--   nvim --clean --headless -u NONE -l TESTS/refs/rg_orphan_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h:h")
local uv = vim.uv or vim.loop

-- lib.nvim, which filetree's util modules need: the runner's $LIB_NVIM_DIR, the
-- names the other suites read, a sibling checkout, lazy.nvim's copy.
local lib_dir
for _, dir in ipairs({
  vim.env.LIB_NVIM_DIR,
  vim.env.FILETREE_LIB_NVIM,
  vim.env.LIB_NVIM_PATH,
  vim.fn.fnamemodify(root, ":h") .. "/lib.nvim",
  vim.fn.stdpath("data") .. "/lazy/lib.nvim",
}) do
  if dir and dir ~= "" and vim.fn.isdirectory(dir .. "/lua/lib") == 1 then
    lib_dir = vim.fs.normalize(dir)
    break
  end
end
local rtp_lines = { ("vim.opt.rtp:prepend(%q)"):format((root:gsub("\\", "/"))) }
if lib_dir then rtp_lines[2] = ("vim.opt.rtp:prepend(%q)"):format(lib_dir) end

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

-- `kill(pid, 0)` probes for a process without signalling it (libuv supports it
-- on Windows too).
local function alive(pid)
  return uv.kill(pid, 0) == 0
end

local function wait_dead(pid, ms)
  vim.wait(ms, function()
    return not alive(pid)
  end, 50)
  return not alive(pid)
end

local scratch = vim.fn.tempname()
vim.fn.mkdir(scratch, "p")
local pidfile = (scratch .. "/sleeper.pid"):gsub("\\", "/")

-- What the child editor runs: it puts the repo on rtp, replaces rg with a
-- sleeper, starts one candidate search with a long timeout and quits while the
-- "search" still runs.
local child = (scratch .. "/child.lua"):gsub("\\", "/")
vim.fn.writefile({
  rtp_lines[1],
  rtp_lines[2] or "",
  ("local pidfile = %q"):format(pidfile),
  "local mode = vim.env.FILETREE_RG_ORPHAN_MODE",
  "local real_system = vim.system",
  "local real_exec = vim.fn.executable",
  "vim.fn.executable = function(name) if name == 'rg' then return 1 end return real_exec(name) end",
  "vim.system = function(cmd, opts, on_exit)",
  "  if cmd[1] == 'rg' then",
  "    cmd = { vim.v.progpath, '--clean', '--headless', '-u', 'NONE', '-c', 'sleep 30', '-c', 'qa!' }",
  "    opts = vim.tbl_extend('force', opts or {}, { cwd = vim.fn.getcwd() })",
  "    local obj = real_system(cmd, opts, on_exit)",
  "    vim.fn.writefile({ tostring(obj.pid) }, pidfile)",
  "    return obj",
  "  end",
  "  return real_system(cmd, opts, on_exit)",
  "end",
  "local scan = require('filetree.refs.scan')",
  "scan.rg_binary = function() return 'rg' end",
  "local timeout = mode == 'timeout' and 500 or 60000",
  "local got",
  "scan.candidates(vim.fn.getcwd(), { 'x' }, { 'md' }, { scan = { timeout_ms = timeout } }, function(f) got = f end)",
  "if mode == 'timeout' then vim.wait(20000, function() return got ~= nil end, 20) end",
  "vim.cmd('qa!')",
}, child)

---@param mode "exit"|"timeout"
---@return integer|nil pid
local function run_child(mode)
  vim.fn.delete(pidfile)
  -- No stdout/stderr pipes: a leaked sleeper holding them would make this wait
  -- hang instead of failing.
  vim
    .system({ vim.v.progpath, "--clean", "--headless", "-u", "NONE", "-l", child }, {
      cwd = scratch,
      stdout = false,
      stderr = false,
      env = { FILETREE_RG_ORPHAN_MODE = mode },
    })
    :wait(60000)
  if vim.fn.filereadable(pidfile) == 0 then return nil end
  return tonumber(vim.fn.readfile(pidfile)[1])
end

print("\n== the editor quits while ripgrep still runs ==")
do
  local pid = run_child("exit")
  check("the double started a sleeper in place of rg", pid ~= nil)
  local dead = pid ~= nil and wait_dead(pid, 5000)
  check(
    "the sleeper died with the editor (VimLeavePre)",
    dead,
    "pid " .. tostring(pid) .. " still alive"
  )
  if pid and not dead then pcall(uv.kill, pid, "sigkill") end
end

print("\n== the scan's timeout kills a hung ripgrep ==")
do
  local pid = run_child("timeout")
  check("the double started a sleeper in place of rg", pid ~= nil)
  local dead = pid ~= nil and wait_dead(pid, 5000)
  check("the sleeper was killed by the timeout", dead, "pid " .. tostring(pid) .. " still alive")
  if pid and not dead then pcall(uv.kill, pid, "sigkill") end
end

print("\n== a search that ends normally is no longer tracked ==")
do
  for _, line in ipairs(rtp_lines) do
    assert(loadstring(line))()
  end
  local scan = require("filetree.refs.scan")
  local real_binary = scan.rg_binary
  scan.rg_binary = function()
    return "rg"
  end
  local real_exec = vim.fn.executable
  local real_system = vim.system
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.executable = function(name)
    if name == "rg" then return 1 end
    return real_exec(name)
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, opts, on_exit)
    if cmd[1] == "rg" then
      cmd = { vim.v.progpath, "--clean", "--headless", "-u", "NONE", "-c", "qa!" }
    end
    return real_system(cmd, opts, on_exit)
  end
  local got
  scan.candidates(scratch, { "x" }, { "md" }, { scan = { timeout_ms = 30000 } }, function(f)
    got = f
  end)
  vim.system = real_system
  vim.fn.executable = real_exec
  scan.rg_binary = real_binary
  vim.wait(30000, function()
    return got ~= nil
  end, 20)
  check("the search delivered a result", got ~= nil)
  check("nothing is left in the live table", scan.live_count() == 0, tostring(scan.live_count()))
end

print("\n== a Scoop shim is resolved to the real ripgrep ==")
do
  -- The shim is a process between the editor and ripgrep; killing it (timeout,
  -- exit) could leave ripgrep running. The real binary is started instead.
  local scan = require("filetree.refs.scan")
  local shims = scratch .. "/shims"
  vim.fn.mkdir(shims, "p")
  local fake_shim = shims .. "/rg.exe"
  vim.fn.writefile({ "" }, fake_shim)
  local real_exepath = vim.fn.exepath
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.exepath = function(name)
    if name == "rg" then return fake_shim end
    return real_exepath(name)
  end
  -- Any existing executable stands in for the real binary.
  vim.fn.writefile({ ('path = "%s"'):format(vim.v.progpath) }, shims .. "/rg.shim")
  local with_shim = scan.rg_binary()
  vim.fn.writefile({ ('path = "%s"'):format(scratch .. "/no-such-rg.exe") }, shims .. "/rg.shim")
  local dangling = scan.rg_binary()
  vim.fn.delete(shims .. "/rg.shim")
  local no_shim = scan.rg_binary()
  vim.fn.exepath = real_exepath
  check("the shim's target is started directly", with_shim == vim.v.progpath, with_shim)
  check("a shim naming a missing binary falls back to rg", dangling == "rg", dangling)
  check("without a shim file rg is started by name", no_shim == "rg", no_shim)
end

vim.fn.delete(scratch, "rf")
print(("\nfiletree.nvim refs/rg_orphan_spec: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
