-- menu.lua — headless unit tests for filetree.nvim's nvzone/menu integration.
--
-- Complements test/smoke.lua and test/units.lua. Exercises
-- filetree.integrations.menu, which is a soft, opt-in layer: it reads
-- require("filetree").feature(name) and require("filetree").config().menu, so
-- it can be tested without a real adapter/tree window by stubbing the
-- top-level "filetree" module — exactly the seam a host (RightMouse
-- dispatcher) uses, so this is de-facto coverage of the real contract.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l test/menu.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root)

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1; print("  ok   " .. name)
  else failed = failed + 1; print("  FAIL " .. name .. (detail and ("  — " .. detail) or "")) end
end
local function eq(name, got, want)
  check(name, got == want, ("got %q want %q"):format(tostring(got), tostring(want)))
end

-- ── stub helpers ────────────────────────────────────────────────────────────

local function stub_action(name, fns)
  local calls = {}
  local t = {}
  for _, fn in ipairs(fns) do
    t[fn] = function() calls[#calls + 1] = name .. "." .. fn end
  end
  return t, calls
end

local function install_stub(menu_cfg, present_features)
  package.loaded["filetree"] = {
    feature = function(n) return present_features[n] end,
    config = function() return { menu = menu_cfg } end,
  }
  package.loaded["filetree.integrations.menu"] = nil
  return require("filetree.integrations.menu")
end

local function names(items)
  local out = {}
  for _, it in ipairs(items) do out[#out + 1] = it.name end
  return out
end
local function has(list, needle)
  for _, x in ipairs(list) do if x == needle then return true end end
  return false
end

-- ── Full menu: every group present; a disabled feature omits its entry ──────
do
  local create_calls
  local features = {}
  features.smart_create, create_calls = stub_action("smart_create", { "create" })
  features.smart_rename = (stub_action("smart_rename", { "rename_current" }))
  features.rename_batch = (stub_action("rename_batch", { "open" }))
  -- create_from_template intentionally omitted -> its entry must not appear.
  features.copy_move = (stub_action("copy_move", { "stage_copy", "stage_cut", "paste" }))
  features.trash = (stub_action("trash", { "delete_current" }))
  features.open_variants = (stub_action("open_variants", { "open_vsplit", "open_split", "open_tabnew" }))
  features.open_with = (stub_action("open_with", { "open_system" }))
  features.open_in_fm = (stub_action("open_in_fm", { "open" }))
  features.path_copy = (stub_action("path_copy", { "pick" }))
  features.markdown_links = (stub_action("markdown_links", { "link_current" }))
  features.find_files = (stub_action("find_files", { "find" }))
  features.grep_in_dir = (stub_action("grep_in_dir", { "grep" }))
  features.node_info = (stub_action("node_info", { "show_current" }))

  local menu = install_stub({ enable = true }, features)
  local items = menu.items()
  local list = names(items)

  check("menu: create entry present (feature enabled)", has(list, "  Create file / dir"))
  check("menu: trash entry present", has(list, "  Trash"))
  check("menu: path_copy entry present", has(list, "  Copy path…"))
  check("menu: node_info entry present", has(list, "  Node info"))
  check("menu: entry omitted when its feature is disabled/absent", not has(list, "New from template"))

  check("menu: does not start with a separator", items[1] and items[1].name ~= "separator")
  check("menu: does not end with a separator", items[#items] and items[#items].name ~= "separator")

  items[1].cmd()
  eq("menu entry cmd() invokes the underlying feature function (count)", #create_calls, 1)
  eq("menu entry cmd() calls the right feature.function", create_calls[1], "smart_create.create")

  -- Group-level opt-out: disabling clipboard + search removes exactly those.
  local menu2 = install_stub({ enable = true, clipboard = false, search = false }, features)
  local list2 = names(menu2.items())
  check("menu opt-out: clipboard=false hides the copy entry", not has(list2, "  Copy"))
  check("menu opt-out: search=false hides find_files", not has(list2, "  Find files"))
  check("menu opt-out: unrelated groups (delete) stay", has(list2, "  Trash"))

  -- Master switch: enable=false yields nothing at all.
  local menu3 = install_stub({ enable = false }, features)
  eq("menu master switch: enable=false yields zero entries", #menu3.items(), 0)

  -- submenu() wraps the same entries as a single fly-out; nil when empty.
  local menu4 = install_stub({ enable = true }, features)
  local sub = menu4.submenu()
  check("menu.submenu(): non-empty fly-out entry", sub ~= nil and sub.name ~= nil and #sub.items > 0)
  local menu5 = install_stub({ enable = false }, features)
  eq("menu.submenu(): nil when there is nothing to show", menu5.submenu(), nil)

  package.loaded["filetree"] = nil
  package.loaded["filetree.integrations.menu"] = nil
end

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nfiletree.nvim menu: %d passed, %d failed"):format(passed, failed))
if failed > 0 then vim.cmd("cq") else vim.cmd("qa!") end
