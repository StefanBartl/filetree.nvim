---@diagnostic disable: need-check-nil
-- cheatsheet.lua — headless unit test for the paged `?` cheatsheet and the
-- pickers.nvim bridge (`filetree.util.pickers`).
--
-- Usage (from the repo root):
--   nvim -n --clean --headless -u NONE -l TESTS/cheatsheet.lua
--
-- Exit code 0 = all checks passed; 1 = a check failed.

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
      return true
    end
  end
  return false
end
local has_lib =
  prepend_dep({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }, "lib.nvim", "lib.nvim", "/lua/lib")
local has_ui = prepend_dep({ "FILETREE_UI_NVIM", "UI_NVIM_PATH" }, "ui.nvim", "ui.nvim", "/lua/ui")
if not (has_lib and has_ui) then
  print("SKIP cheatsheet.lua: lib.nvim / ui.nvim not found")
  vim.cmd("qa!")
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

-- ── A tree buffer with one key filetree owns and two it does not ─────────────

local cheatsheet = require("filetree.features.ui.cheatsheet")
local bind = require("filetree.util.bind")

-- `bind.bind` waits for a tree buffer to attach; `bind_buffer` registers for
-- one buffer now, which is all the cheatsheet reads.
local tree = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(tree)
bind.bind_buffer("diff", { keymap = "D" }, {
  {
    name = "stage_or_diff",
    field = "keymap",
    rhs = function() end,
    desc = "stage/diff current file",
  },
}, tree)
vim.keymap.set("n", "Q", function() end, { buffer = tree, desc = "some plugin's key" })
vim.keymap.set("n", "<leader>zz", function() end, { buffer = tree, desc = "leader key" })

cheatsheet.show()

-- The viewer is the current window now.
local buf = vim.api.nvim_get_current_buf()
local function body()
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

check("page 1 is the filetree page", body():find("%[1 filetree%]") ~= nil)
check("page 1 lists filetree's own key", body():find("D%s+Stage/diff current file") ~= nil, body())
check("page 1 omits foreign keys", body():find("some plugin's key", 1, true) == nil)

-- ── Paging ───────────────────────────────────────────────────────────────────

vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "x", false)
check("<Tab> turns to page 2", body():find("%[2 other keys%]") ~= nil, body())
check("page 2 lists a foreign buffer key", body():find("Q%s+Some plugin's key") ~= nil, body())
check("page 2 shows <leader> as such", body():find("<leader>zz") ~= nil, body())
check("page 2 leaves out a filetree key", body():find("Stage/diff current file", 1, true) == nil)

vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "x", false)
check("<Tab> turns to page 3", body():find("%[3 commands%]") ~= nil, body())
check("page 3 lists sub-commands", body():find(":%w+ marks show") ~= nil, body())

vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "x", false)
check("<Tab> wraps to page 1", body():find("%[1 filetree%]") ~= nil)
vim.api.nvim_feedkeys(vim.keycode("<S-Tab>"), "x", false)
check("<S-Tab> wraps back to page 3", body():find("%[3 commands%]") ~= nil)
vim.api.nvim_feedkeys("2", "x", false)
check("`2` jumps to page 2", body():find("%[2 other keys%]") ~= nil)

-- ── Toggle ───────────────────────────────────────────────────────────────────

cheatsheet.close()
check("close() closes the float", vim.api.nvim_get_current_buf() == tree)

-- -- pickers bridge: soft dependency, opt-out on both sides ---------------------

local cfg_mod = require("filetree.config")
local bridge = require("filetree.util.pickers")
package.loaded["pickers.integrations.filetree"] = nil
local has_pickers = pcall(require, "pickers.integrations.filetree")
if not has_pickers then
  check("bridge answers false without pickers.nvim", bridge.files(root) == false)
  check("bridge grep answers false without pickers.nvim", bridge.grep(root) == false)
  check("available() is false without pickers.nvim", bridge.available() == false)
end

-- A stand-in for pickers.nvim's own bridge: the directory arrives as given,
-- the query and the extra rg flags in the opts table.
local seen = {}
local remote_on = true
package.loaded["pickers.integrations.filetree"] = {
  available = function()
    return remote_on
  end,
  files = function(dir, opts)
    seen.files = { dir = dir, opts = opts }
    return remote_on
  end,
  grep = function(dir, opts)
    seen.grep = { dir = dir, opts = opts }
    return remote_on
  end,
}
cfg_mod.setup({})
check("integrations.pickers defaults to true", cfg_mod.get().integrations.pickers == true)
check("available() with the bridge present", bridge.available() == true)
check("files() reports handled", bridge.files("/x/proj", "foo") == true)
check(
  "files() hands over the dir and query",
  seen.files.dir == "/x/proj" and seen.files.opts.query == "foo"
)
check("grep() reports handled", bridge.grep("/x/proj", nil, { "--glob=!x" }) == true)
check("grep() forwards extra args", vim.deep_equal(seen.grep.opts.extra_args, { "--glob=!x" }))

-- pickers.nvim's side switched off: it answers false, and so does the bridge.
remote_on = false
check("pickers.nvim opt-out: files() answers false", bridge.files("/x") == false)
check("pickers.nvim opt-out: available() is false", bridge.available() == false)
remote_on = true

-- filetree's side switched off: pickers.nvim is not even asked.
seen = {}
cfg_mod.setup({ integrations = { pickers = false } })
check("integrations.pickers = false is kept", cfg_mod.get().integrations.pickers == false)
check("filetree opt-out: files() answers false", bridge.files("/x") == false)
check("filetree opt-out: grep() answers false", bridge.grep("/x") == false)
check("filetree opt-out: pickers.nvim is never called", seen.files == nil and seen.grep == nil)

-- A wrongly typed / unknown option is dropped with an issue, default kept.
cfg_mod.setup({ integrations = { pickers = "no", nope = true } })
check("bad integrations value: default applies", cfg_mod.get().integrations.pickers == true)
check("bad integrations value: reported", #cfg_mod.issues() == 2, vim.inspect(cfg_mod.issues()))
cfg_mod.setup({})

print(string.format("\ncheatsheet.lua: %d passed, %d failed", passed, failed))
vim.cmd(failed == 0 and "qa!" or "cq!")
