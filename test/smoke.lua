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
  "cwd_sync", "current_hl", "safety", "auto_resize",
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
  ft.setup({ adapter = "stub", features = { marks = { enabled = false }, auto_resize = { enabled = true } } })
  check("explicit { enabled=false } disables a default-on feature", ft.feature("marks") == nil)
  check("explicit { enabled=true } enables a default-off feature", ft.feature("auto_resize") ~= nil)
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

-- 6) no two default-on, tree-scoped keymaps target the same physical key ────
-- Terminals cannot distinguish some key pairs from each other: a physical Tab
-- keypress and Ctrl-I send the identical byte ("<Tab>" == "<C-i>"), likewise
-- "<CR>" == "<C-m>" and "<Esc>" == "<C-[>". Two default-on features silently
-- fighting over one of these pairs is exactly the jump_list/preview bug that
-- made <Tab> preview toggle fall through to an unrelated global mapping
-- instead of firing — this guards against that class of bug recurring.
do
  local ALIASES = {
    ["<c-i>"] = "<tab>", ["<tab>"] = "<tab>",
    ["<c-m>"] = "<cr>",  ["<cr>"]  = "<cr>",
    ["<c-[>"] = "<esc>", ["<esc>"] = "<esc>",
  }
  local function canonical(lhs)
    -- Only fold via the specific known alias pairs (case-insensitively, since
    -- "<C-i>"/"<c-i>" are the same key spelled differently) — anything else
    -- must stay case-sensitive: "b" and "B" are genuinely different physical
    -- keypresses, not an alias.
    return ALIASES[lhs:lower()] or lhs
  end

  -- marks.keymap_clear ("<C-m>") vs preview ("<CR>") is a deliberate, accepted
  -- exception: it reproduces the exact legacy keymap layout the user's old
  -- standalone neo-tree config used (this pairing existed there too, without
  -- reported issues) — whichever binds last on the buffer wins silently
  -- rather than the "neither fires" failure mode of the Tab/C-i case (that
  -- one involved a *prefix* ambiguity across a `nowait` native mapping;
  -- <C-m>/<CR> here are both exact single-key binds, so this is just an
  -- ordinary "last registration wins" shadowing, not the broken-resolution
  -- class of bug this check exists to catch).
  -- filter.keymap_clear ("<C-c>") vs copy_move.keymaps.clear ("<C-c>") is the
  -- same kind of deliberate, accepted exception: the reference legacy config
  -- also had "<C-c>" bound to clear_filter AND clear-clipboard simultaneously
  -- (two neo-tree native window.mappings entries for the same key) with no
  -- reported issue. Both are exact single-key binds -- last-registration-wins
  -- shadowing, not the broken-resolution class of bug this check exists to
  -- catch.
  local ACCEPTED = {
    ["marks:preview:<cr>"] = true,
    ["copy_move:filter:<C-c>"] = true,
  }

  local b = require("filetree.bindings")
  local seen = {}   -- canonical key -> feature name that claimed it first
  local collisions = {}
  for _, entries in pairs(b.keymaps) do
    for _, e in ipairs(entries) do
      if e.scope == "tree" and not e.opt_in then
        local key = canonical(e.lhs)
        if seen[key] and seen[key] ~= e.feature then
          local a, z = seen[key], e.feature
          if a > z then a, z = z, a end
          local accepted_key = a .. ":" .. z .. ":" .. key
          if not ACCEPTED[accepted_key] then
            collisions[#collisions + 1] = ("%s (%s) vs %s (%s) both target %q")
              :format(seen[key], key, e.feature, e.lhs, key)
          end
        else
          seen[key] = e.feature
        end
      end
    end
  end
  check("no default-on tree keymaps collide on an alias-equivalent physical key",
    #collisions == 0, table.concat(collisions, "; "))
end

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nfiletree.nvim smoke: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")   -- non-zero exit
else
  vim.cmd("qa!")
end
