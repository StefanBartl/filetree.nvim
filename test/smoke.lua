-- smoke.lua — headless regression smoke test for filetree.nvim.
--
-- Runs the plugin against a stub adapter (no tree plugin required) and asserts
-- the core invariants: every feature module loads, the opt-out defaults resolve,
-- the registry resolver works, and the binding catalog is populated.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l test/smoke.lua
--
-- Exit code 0 = all checks passed; 1 = a check failed (message printed).

-- ── Locate the repo root relative to this file, put it (and lib.nvim) on rtp ──
-- ":p" resolves to absolute first, so `root` survives any later cwd change
-- (":h:h" alone would stay relative to invocation-time cwd).
local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root)
-- lib.nvim is a declared dependency; add a sibling checkout if present.
local sibling_lib = vim.fn.fnamemodify(root, ":h") .. "/lib.nvim"
if vim.fn.isdirectory(sibling_lib) == 1 then
  vim.opt.rtp:prepend(sibling_lib)
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

-- ── Stub adapter: satisfies the interface, does nothing ──────────────────────
local function stub_adapter()
  return setmetatable({
    name = "stub",
    is_available = function() return true end,
  }, { __index = function() return function() return false end end })
end

local ft  = require("filetree")
local reg = require("filetree.features")
ft.register_adapter(stub_adapter())

-- 1) every registered feature module loads at its (category) path
do
  local bad = {}
  for name, info in pairs(reg.FEATURES) do
    if not pcall(require, info.mod) then bad[#bad + 1] = name end
  end
  check("all feature modules load", #bad == 0, table.concat(bad, ", "))
end

-- 2) setup is clean and opt-out resolves (default-on minus the opt-in few)
local DEFAULT_OFF = {
  "cwd_sync", "current_hl", "safety", "auto_resize", "git_actions",
  "path_utils", "harpoon_integration", "telescope_integration", "tree_open_keymaps",
}
do
  local warnings = 0
  local orig = vim.notify
  vim.notify = function(m, l, o)
    if type(m) == "string" and m:find("filetree") and (l or 0) >= vim.log.levels.WARN then
      warnings = warnings + 1
    end
    return orig(m, l, o)
  end
  local ok = pcall(ft.setup, { adapter = "stub" })
  vim.notify = orig
  check("setup() runs without warnings", ok and warnings == 0, "warnings=" .. warnings)

  local total = vim.tbl_count(reg.FEATURES)
  local active = 0
  for name in pairs(reg.FEATURES) do
    if ft.feature(name) then active = active + 1 end
  end
  check("opt-out active count = total - " .. #DEFAULT_OFF,
    active == total - #DEFAULT_OFF, ("active=%d total=%d"):format(active, total))

  local off_ok = true
  for _, n in ipairs(DEFAULT_OFF) do
    if ft.is_feature_enabled(n) then off_ok = false end
  end
  check("all opt-in features are off by default", off_ok)
end

-- 3) explicit enable/disable overrides the default in both directions
do
  ft.setup({ adapter = "stub", features = { marks = { enabled = false }, git_actions = { enabled = true } } })
  check("explicit { enabled=false } disables a default-on feature", ft.feature("marks") == nil)
  check("explicit { enabled=true } enables a default-off feature", ft.feature("git_actions") ~= nil)
  ft.setup({ adapter = "stub" })
end

-- 4) registry resolver
do
  check("registry.require resolves a feature", reg.require("preview") ~= nil)
  check("registry.mod_path returns the category path",
    reg.mod_path("marks") == "filetree.features.org.marks", reg.mod_path("marks"))
  check("registry.require(unknown) is nil", reg.require("does_not_exist") == nil)
end

-- 5) binding catalog
do
  local b = require("filetree.bindings")
  local cat = b.catalog()
  check("catalog has usercommands (walked live)", #cat.usercommands > 50, "#=" .. #cat.usercommands)
  check("catalog has keymaps for several categories", vim.tbl_count(cat.keymaps) >= 8)
  check("catalog has autocmd entries", #cat.autocmds > 0)
  check("docs/BINDINGS.lua returns the catalog",
    type(dofile(root .. "/docs/BINDINGS.lua")) == "table")
end

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nfiletree.nvim smoke: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")   -- non-zero exit
else
  vim.cmd("qa!")
end
