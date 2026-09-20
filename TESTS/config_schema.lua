-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- config_schema.lua -- the feature-owned config schemas (ERR-50 / ERR-22).
--
-- Three layers:
--   1. `filetree.config.schema` on its own: type unions, ranges, enums, nested
--      records, arrays, the hint on an unknown key.
--   2. Through `config.setup()` / `filetree.setup()`: a typo inside a feature's
--      body, a wrongly-typed or out-of-range value and a non-table body are
--      reported and dropped -- and a legitimate config (including the
--      deprecated per-feature reference options) raises nothing.
--   3. Drift: every feature module exports a SCHEMA (bar the ones validated
--      centrally), the SCHEMA accepts the module's own defaults, and the module
--      reads no option its SCHEMA does not declare.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/config_schema.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root)

-- Same lib.nvim / ui.nvim resolution order as smoke.lua (see the comment there
-- for why each candidate exists).
local function prepend_first(envs, sibling, lazy_name, marker)
  local candidates = {}
  for _, env in ipairs(envs) do
    local v = vim.env[env]
    if v and v ~= "" then candidates[#candidates + 1] = v end
  end
  candidates[#candidates + 1] = vim.fn.fnamemodify(root, ":h") .. "/" .. sibling
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/" .. lazy_name
  for _, candidate in ipairs(candidates) do
    if vim.fn.isdirectory(candidate .. marker) == 1 then
      vim.opt.rtp:prepend(candidate)
      return
    end
  end
end
prepend_first({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }, "lib.nvim", "lib.nvim", "/lua/lib")
prepend_first({ "FILETREE_UI_NVIM", "UI_NVIM_PATH" }, "ui.nvim", "ui.nvim", "/lua/ui")

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
local function eq(name, got, want)
  check(
    name,
    vim.deep_equal(got, want),
    ("got %s, want %s"):format(vim.inspect(got), vim.inspect(want))
  )
end
local function has(name, haystack, needle)
  check(name, haystack:find(needle, 1, true) ~= nil, ("%q not in %q"):format(needle, haystack))
end

local schema = require("filetree.config.schema")
local config = require("filetree.config")
local registry = require("filetree.features")

---Run `schema.check` and return (clean, joined issues).
local function run(body, fields)
  local issues = {}
  local clean = schema.check(body, fields, "f", issues)
  return clean, table.concat(issues, "\n"), issues
end

-- ── 1. the schema engine ─────────────────────────────────────────────────────
do
  local clean, msg = run({ n = "5" }, { n = "number" })
  eq("type mismatch: value dropped", clean, {})
  has(
    "type mismatch: names the option and both types",
    msg,
    "option 'f.n' must be a number, got \"5\""
  )

  clean = run({ k = false, s = "x" }, { k = "keymap", s = "keymap" })
  eq("keymap: a string and `false` are both accepted", clean, { k = false, s = "x" })
  clean, msg = run({ k = true }, { k = "keymap" })
  eq("keymap: `true` is rejected", clean, {})
  has("keymap: message says what is accepted", msg, "a string or false")

  clean, msg = run({ n = -1 }, { n = { "number", min = 0 } })
  eq("min: out-of-range number dropped", clean, {})
  has("min: message names the bound", msg, ">= 0")
  clean = run({ n = 0 }, { n = { "number", min = 0 } })
  eq("min: the bound itself is accepted", clean, { n = 0 })
  local _, range_msg = run({ n = 11 }, { n = { "number", min = 0, max = 10 } })
  has("min+max: message names both bounds", range_msg, "between 0 and 10")

  clean = run({ a = 0 / 0, b = math.huge, c = -math.huge }, {
    a = "number",
    b = "number",
    c = "number",
  })
  eq("NaN and +-inf never pass a number spec", clean, {})

  clean, msg = run({ m = "permenant" }, { m = { "string", enum = { "trash", "permanent" } } })
  eq("enum: unknown member dropped", clean, {})
  has("enum: message lists the members", msg, [[one of "trash", "permanent"]])
  clean = run({ b = false, s = "auto" }, {
    b = { "string|false", enum = { "auto" } },
    s = { "string|false", enum = { "auto" } },
  })
  eq(
    "enum in a `string|false` union: `false` passes, the enum still binds strings",
    clean,
    { b = false, s = "auto" }
  )

  clean, msg = run({ confrim = true, confirm = true }, { confirm = "boolean" })
  eq("unknown key: dropped, the known one kept", clean, { confirm = true })
  has("unknown key: did-you-mean hint", msg, "did you mean 'f.confirm'")

  clean = run({ enabled = true, autocmds_enabled = false }, {})
  eq(
    "universal keys are accepted without being declared",
    clean,
    { enabled = true, autocmds_enabled = false }
  )
  local _, typed_msg = run({ enabled = "yes" }, {})
  has("universal keys are typed too", typed_msg, "option 'f.enabled' must be a boolean")

  local rec = { "table", fields = { text = "string", hl = "string" } }
  clean, msg = run({ sign = { text = "+", hl = 3, typo = 1 } }, { sign = rec })
  eq("record: bad field and unknown field dropped, good one kept", clean, { sign = { text = "+" } })
  has("record: nested path in the message", msg, "f.sign.hl")
  has("record: unknown nested key reported with its path", msg, "f.sign.typo")

  clean = run({ l = { "a", "b" } }, { l = { "table", of = "string" } })
  eq("array of strings accepted", clean, { l = { "a", "b" } })
  clean, msg = run({ l = { "a", 2 } }, { l = { "table", of = "string" } })
  eq("array with one bad element: the whole table falls back to the default", clean, {})
  has("array: the bad element is named", msg, "f.l.2")
  clean = run({ l = false }, { l = { "table|false", of = "string" } })
  eq("`table|false`: false accepted", clean, { l = false })

  local body = { n = "x" }
  run(body, { n = "number" })
  eq("check() does not mutate its input", body, { n = "x" })
end

-- ── 2. through config.setup() / filetree.setup() ─────────────────────────────
do
  local function joined()
    return table.concat(config.issues(), "\n")
  end

  config.setup({ features = { trash = { confrim = false } } })
  has(
    "typo inside a feature body: reported with a hint",
    joined(),
    "did you mean 'features.trash.confirm'"
  )
  eq("typo inside a feature body: not merged", config.get().features.trash.confrim, nil)

  config.setup({ features = { trash = { max_history = "50" } } })
  has(
    "wrongly-typed value: reported",
    joined(),
    "option 'features.trash.max_history' must be a number"
  )
  eq(
    "wrongly-typed value: dropped, the feature default applies",
    config.get().features.trash.max_history,
    nil
  )

  config.setup({ features = { trash = { max_history = -5 } } })
  has("out-of-range value: reported", joined(), "features.trash.max_history' must be a number >= 0")

  config.setup({ features = { trash = { mode = "permenant" } } })
  has("enum typo: reported", joined(), [[one of "trash", "permanent"]])
  eq("enum typo: dropped", config.get().features.trash.mode, nil)

  config.setup({ features = { trash = true } })
  has(
    "non-table feature body: reported",
    joined(),
    "option 'features.trash' must be a table, got true"
  )
  eq("non-table feature body: dropped", config.get().features.trash, nil)

  config.setup({ features = { layout_guard = true } })
  has(
    "non-table body of a centrally-declared feature: reported",
    joined(),
    "option 'features.layout_guard' must be a table"
  )

  -- A legitimate, generous configuration raises nothing.
  config.setup({
    features = {
      trash = {
        enabled = true,
        mode = "permanent",
        confirm = false,
        keymap = "d",
        keymap_undo = false,
        max_history = 0,
      },
      copy_move = { enabled = true, keymaps = { copy = "c", clear = false }, confirm = false },
      smart_create = { notify_level = "off", auto_init_lua = true },
      create_from_template = { prefer = "builtin", template_dir = "/tmp/t" },
      link_create = { keymap = "gl" },
      open_replace = { keymap_swap = false },
    },
  })
  eq("a legitimate configuration raises no issue", config.issues(), {})

  -- The deprecated per-feature reference options are still a real, migrated
  -- part of the config: the schema must not swallow them as "unknown".
  config.setup({
    features = {
      smart_rename = {
        check_markdown_refs = false,
        refs_picker_prefer = "quickfix",
        update_references = false,
      },
    },
  })
  eq("deprecated reference options are accepted", config.issues(), {})
  eq("deprecated reference options still migrate into `refs`", config.get().refs.on_rename, "off")
  eq("deprecated `refs_picker_prefer` migrates too", config.get().refs.picker, "quickfix")
  eq("deprecated `update_references = false` switches the code providers off", {
    config.get().refs.providers.lua,
    config.get().refs.providers.python,
    config.get().refs.providers.ts_js,
  }, { false, false, false })

  -- An explicit `refs` setting wins over the deprecated option, per field.
  config.setup({
    refs = { on_rename = "ask", providers = { lua = true } },
    features = { smart_rename = { check_markdown_refs = false, update_references = false } },
  })
  eq("an explicit refs.on_rename beats the deprecated option", config.get().refs.on_rename, "ask")
  eq(
    "an explicit refs.providers.lua beats the deprecated option",
    config.get().refs.providers.lua,
    true
  )
  eq(
    "...while the providers the user left alone are migrated",
    config.get().refs.providers.python,
    false
  )

  -- End to end: filetree.setup() survives a non-table body (it used to die at
  -- `fcfg.enabled = true` on a boolean).
  local ft = require("filetree")
  ft.register_adapter(setmetatable({
    name = "schema-stub",
    is_available = function()
      return true
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  }))
  local ok =
    pcall(ft.setup, { adapter = "schema-stub", features = { trash = true, size_info = "yes" } })
  check("filetree.setup() survives non-table feature bodies", ok and ft.is_initialized())
  config.setup({})
end

-- ── 3. drift ─────────────────────────────────────────────────────────────────

---Features whose body is validated centrally (KNOWN_FEATURE_BODY in
---config/init.lua) and therefore export no SCHEMA.
local CENTRAL = {
  cwd_sync = true,
  current_hl = true,
  safety = true,
  layout_guard = true,
  no_name_guard = true,
  sidebar_guard = true,
}

---Categories (as in `filetree.features`) whose modules have no SCHEMA yet.
---Empty means done.
local UNMIGRATED = {
  nav = true,
  ui = true,
  search = true,
  paths = true,
  git = true,
  org = true,
  system = true,
  lsp = true,
  compare = true,
  infra = true,
}

---Identifiers a module legitimately reads off something named `cfg`/`config`
---that is not its option table.
local NOT_OPTIONS = {
  breadcrumbs = { relative = true }, -- a window's `relative`, not an option
  -- Bound through `bind.bind(..., { cfg = keymaps })`: `copy` & co. are the
  -- fields of the nested `keymaps` record, declared under it.
  copy_move = { copy = true, cut = true, paste = true, show = true, clear = true },
}

local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end

---The literal table after `local <name> = {`, evaluated; nil when the module
---does not define its defaults as a literal.
local function literal_defaults(src, name)
  local start = src:find("\nlocal " .. name .. " = {\n", 1, true)
  if not start then return nil end
  local body_start = src:find("{", start, true)
  local finish = src:find("\n}\n", body_start, true)
  local chunk = src:sub(body_start, finish + 1)
  local fn, err = load("return " .. chunk, "=defaults")
  assert(fn, "cannot evaluate " .. name .. " literal: " .. tostring(err))
  return fn()
end

for name, info in pairs(registry.FEATURES) do
  local path = root .. "/lua/" .. info.mod:gsub("%.", "/") .. "/init.lua"
  local src = read_file(path)
  local mod = require(info.mod)

  if CENTRAL[name] then
    check(name .. ": validated centrally, exports no SCHEMA", mod.SCHEMA == nil)
  elseif UNMIGRATED[info.category] then
    check(name .. ": (not migrated yet)", true)
  else
    check(name .. ": exports a SCHEMA", type(mod.SCHEMA) == "table")
    if type(mod.SCHEMA) == "table" then
      local declared =
        vim.tbl_extend("force", { enabled = true, autocmds_enabled = true }, mod.SCHEMA)

      -- The SCHEMA accepts the module's own defaults.
      for _, literal in ipairs({ "_cfg", "DEFAULTS" }) do
        local defaults = literal_defaults(src, literal)
        if defaults then
          local issues = {}
          schema.check(defaults, mod.SCHEMA, "features." .. name, issues)
          check(
            name .. ": SCHEMA accepts the module's own `" .. literal .. "` defaults",
            #issues == 0,
            table.concat(issues, "; ")
          )
        end
      end

      -- The module reads no option its SCHEMA does not declare.
      local undeclared = {}
      for line in (src .. "\n"):gmatch("(.-)\n") do
        if not line:match("^%s*%-%-") then
          local code = line:gsub("%-%-.*$", "")
          for _, pat in ipairs({
            "%f[%w_]_cfg%.([%a_][%w_]*)",
            "%f[%w_]config%.([%a_][%w_]*)",
            "%f[%w_]cfg%.([%a_][%w_]*)",
            'field%s*=%s*"([%w_]+)"',
          }) do
            for key in code:gmatch(pat) do
              local ignored = NOT_OPTIONS[name] and NOT_OPTIONS[name][key]
              if not declared[key] and not ignored and key ~= "_prefix" then
                undeclared[key] = true
              end
            end
          end
        end
      end
      local list = vim.tbl_keys(undeclared)
      table.sort(list)
      check(
        name .. ": reads no option its SCHEMA does not declare",
        #list == 0,
        table.concat(list, ", ")
      )
    end
  end
end

print(("\nfiletree.nvim config_schema: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
