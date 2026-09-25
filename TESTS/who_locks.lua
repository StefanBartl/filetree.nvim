---@diagnostic disable: need-check-nil, missing-fields
-- who_locks.lua — headless tests for features/infra/who_locks.
--
-- No real neo-tree and no real Restart Manager: `neo-tree...fs_watch` is a stub
-- whose `show_watched` closes over a `watchers` upvalue (the exact seam the
-- module reads), and `lib.nvim.cross.fs.lock` is a double.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/who_locks.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)

for _, env in ipairs({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" and vim.fn.isdirectory(v .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(v)
    break
  end
end
for _, c in ipairs({
  vim.fn.fnamemodify(root_dir, ":h") .. "/lib.nvim",
  vim.fn.stdpath("data") .. "/lazy/lib.nvim",
}) do
  if vim.fn.isdirectory(c .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(c)
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

-- ── Doubles ───────────────────────────────────────────────────────────────────
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local file = tmp .. "/locked.txt"
vim.fn.writefile({ "x" }, file)

local watchers = {
  [tmp] = { references = 2, active = true, handle = {} },
  [tmp .. "/elsewhere"] = { references = 1, active = true, handle = {} },
}
package.loaded["neo-tree"] = {}
package.loaded["neo-tree.sources.filesystem.lib.fs_watch"] = {
  show_watched = function()
    return watchers
  end,
}
package.loaded["lib.nvim.cross.fs.lock"] = {
  probe = function()
    return false, "EBUSY"
  end,
  supported = function()
    return true
  end,
  who = function(_, cb)
    cb({ { name = "other.exe", pid = 42 } })
  end,
  report = function(_, cb)
    cb({ "path: x", "probe: EBUSY" })
  end,
}

local printed = {}
local real_print = print
_G.print = function(...)
  printed[#printed + 1] = table.concat(vim.tbl_map(tostring, { ... }), " ")
end

local who = require("filetree.features.infra.who_locks")

-- ── --json output ─────────────────────────────────────────────────────────────
who.run(file, true)
_G.print = real_print
local ok, decoded = pcall(vim.json.decode, printed[#printed] or "")
check("json output decodes", ok, tostring(decoded))
if ok then
  check("json: probe reports EBUSY", decoded.probe.renameable == false and decoded.probe.error == "EBUSY")
  check("json: holder listed", decoded.holders.list[1].pid == 42)
  check("json: watchers ok, 2 total", decoded.watchers.status == "ok" and decoded.watchers.total == 2)
  check("json: only the file's folder matches", #decoded.watchers.entries == 1)
  check("json: buffer not open", decoded.buffer.open == false)
end

-- ── unreachable watcher table ─────────────────────────────────────────────────
package.loaded["neo-tree.sources.filesystem.lib.fs_watch"] = { show_watched = function() end }
printed = {}
_G.print = function(...)
  printed[#printed + 1] = table.concat(vim.tbl_map(tostring, { ... }), " ")
end
who.run(file, true)
_G.print = real_print
local ok2, d2 = pcall(vim.json.decode, printed[#printed] or "")
check("json: unreachable table reported", ok2 and d2.watchers.status == "unreachable")

-- ── neo-tree not loaded ───────────────────────────────────────────────────────
package.loaded["neo-tree"] = nil
printed = {}
_G.print = function(...)
  printed[#printed + 1] = table.concat(vim.tbl_map(tostring, { ... }), " ")
end
who.run(file, true)
_G.print = real_print
local ok3, d3 = pcall(vim.json.decode, printed[#printed] or "")
check("json: not_loaded reported", ok3 and d3.watchers.status == "not_loaded")

vim.fn.delete(tmp, "rf")
real_print(("\n%d passed, %d failed"):format(passed, failed))
vim.cmd(failed == 0 and "qa!" or "cq!")
