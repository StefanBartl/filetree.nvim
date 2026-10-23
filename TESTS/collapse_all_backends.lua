---@diagnostic disable: missing-fields
-- collapse_all_backends.lua — `adapter.collapse_all` and
-- `tree_toggle.collapse_on_toggle` against a REAL neo-tree (and nvim-tree when
-- installed).
--
-- What a stub cannot answer: which folders the real tree has open after the
-- collapse, and after the reveal of the toggle that follows it. The tree is
-- read back through neo-tree's own `renderer.get_expanded_nodes`, not through
-- the adapter under test.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/collapse_all_backends.lua
--
-- Not part of CI (no tree plugin there); prints a skip without neo-tree.
-- Exit 0 = all passed (or skipped), 1 = a check failed.

io.stdout:setvbuf("line")
vim.opt.swapfile = false
vim.opt.shortmess:append("A")

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)
package.path = table.concat({
  root_dir .. "/lua/?.lua",
  root_dir .. "/lua/?/init.lua",
  package.path,
}, ";")

---Prepend the first candidate directory that looks like the plugin we want.
---@param env string[]
---@param names string[]
---@param probe string
---@return string?
local function resolve(env, names, probe)
  local candidates = {}
  for _, e in ipairs(env) do
    local v = vim.env[e]
    if v and v ~= "" then candidates[#candidates + 1] = v end
  end
  for _, name in ipairs(names) do
    local parent = vim.fn.fnamemodify(root_dir, ":h")
    candidates[#candidates + 1] = parent .. "/" .. name
    candidates[#candidates + 1] = parent .. "/.test-plugins/" .. name
    candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/" .. name
    candidates[#candidates + 1] = vim.fn.expand("$LOCALAPPDATA/nvim-data/lazy/" .. name)
  end
  for _, c in ipairs(candidates) do
    local norm = vim.fs.normalize(c)
    if vim.fn.isdirectory(norm .. "/" .. probe) == 1 then
      vim.opt.rtp:prepend(norm)
      package.path = table.concat({
        norm .. "/lua/?.lua",
        norm .. "/lua/?/init.lua",
        package.path,
      }, ";")
      return norm
    end
  end
  return nil
end

resolve({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }, { "lib.nvim" }, "lua/lib")
resolve({ "FILETREE_UI_NVIM", "UI_NVIM_PATH" }, { "ui.nvim" }, "lua/ui")
resolve({}, { "plenary.nvim" }, "lua/plenary")
resolve({}, { "nvim-web-devicons" }, "lua/nvim-web-devicons")
local has_nui = resolve({}, { "nui.nvim" }, "lua/nui")
local has_neotree = resolve({ "FILETREE_NEOTREE" }, { "neo-tree.nvim" }, "lua/neo-tree")
local has_nvimtree = resolve({ "FILETREE_NVIMTREE" }, { "nvim-tree.lua" }, "lua/nvim-tree")

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

---@param p string
---@return string
local function key(p)
  local k = vim.fs.normalize(p):gsub("/+$", "")
  if vim.fn.has("win32") == 1 then k = k:lower() end
  return k
end

---root/top.lua, root/a/b/c/deep.lua, root/x/y/z.lua
---@return string work
local function make_project()
  local work = vim.fs.normalize((vim.env.TEMP or "/tmp") .. "/filetree-collapse-all")
  vim.fn.delete(work, "rf")
  vim.fn.mkdir(work .. "/a/b/c", "p")
  vim.fn.mkdir(work .. "/x/y", "p")
  vim.fn.writefile({ "-- top" }, work .. "/top.lua")
  vim.fn.writefile({ "-- deep" }, work .. "/a/b/c/deep.lua")
  vim.fn.writefile({ "-- z" }, work .. "/x/y/z.lua")
  return work
end

local function settle(ms)
  vim.wait(ms or 400, function()
    return false
  end, 25)
end

-- ── neo-tree ─────────────────────────────────────────────────────────────────

local function run_neotree()
  print("\n== neotree ==")
  local work = make_project()
  vim.cmd("cd " .. vim.fn.fnameescape(work))
  require("neo-tree").setup({
    close_if_last_window = false,
    filesystem = { use_libuv_file_watcher = false, follow_current_file = { enabled = false } },
    window = { position = "left", width = 40 },
  })
  require("filetree").setup({
    adapter = "neotree",
    features = {
      auto_reveal = { enabled = false },
      tree_toggle = { enabled = true, collapse_on_toggle = true },
    },
  })
  local adapter = require("filetree.adapter.neotree")
  local tt = require("filetree.features.nav.tree_toggle")
  local renderer = require("neo-tree.ui.renderer")
  local manager = require("neo-tree.sources.manager")

  ---The folders below the root the real tree has open, as `a/b`-style names.
  ---@return table<string, true>
  local function open_dirs()
    local state = manager.get_state("filesystem")
    local out = {}
    if not state or not state.tree then return out end
    local base = key(work)
    for _, id in ipairs(renderer.get_expanded_nodes(state.tree)) do
      local k = key(id)
      if k ~= base and k:sub(1, #base + 1) == base .. "/" then out[k:sub(#base + 2)] = true end
    end
    return out
  end

  local function names(set)
    local list = vim.tbl_keys(set)
    table.sort(list)
    return table.concat(list, ",")
  end

  ---Edit `rel`, then toggle the tree open (closing it first when it is open)
  ---and wait until `rel` is rendered.
  ---@param rel string
  local function open_on(rel)
    if adapter.is_open() then tt.toggle("left") end
    settle(200)
    vim.cmd("edit " .. vim.fn.fnameescape(work .. "/" .. rel))
    tt.toggle("left")
    vim.wait(6000, function()
      return adapter.get_node_line(work .. "/" .. rel) ~= nil
    end, 50)
    settle()
  end

  ---Open a folder the way a user does (`<CR>` on it): neo-tree's own
  ---`toggle_directory`, which records it in `explicitly_opened_nodes`. Folders
  ---a reveal opened are closed again by neo-tree's next reveal anyway; the
  ---ones opened by hand are the ones that pile up.
  ---@param rel string
  local function user_open(rel)
    local state = manager.get_state("filesystem")
    local want = key(work .. "/" .. rel)
    local node
    for _, id in ipairs({ work .. "/" .. rel, ((work .. "/" .. rel):gsub("/", "\\")) }) do
      node = node or state.tree:get_node(id)
    end
    if not node then
      local function walk(nodes)
        for _, n in ipairs(nodes or {}) do
          if key(n:get_id()) == want then return n end
          local found = n:has_children() and walk(state.tree:get_nodes(n:get_id())) or nil
          if found then return found end
        end
      end
      node = walk(state.tree:get_nodes())
    end
    if not node then
      check("user_open: found " .. rel, false)
      return
    end
    local done = false
    require("neo-tree.sources.filesystem").toggle_directory(
      state,
      node,
      nil,
      false,
      false,
      function()
        done = true
      end
    )
    vim.wait(3000, function()
      return done or open_dirs()[rel] == true
    end, 25)
    settle(150)
  end

  ---The scenario both option values run: x and x/y opened by hand on top.lua,
  ---then the tree closed and reopened on deep.lua.
  ---@return string
  local function reopen_after_manual_opens()
    open_on("top.lua")
    user_open("x")
    user_open("x/y")
    check("setup: x and x/y opened by hand", names(open_dirs()) == "x,x/y", names(open_dirs()))
    open_on("a/b/c/deep.lua")
    return names(open_dirs())
  end

  local got = reopen_after_manual_opens()
  check(
    "reopen on deep.lua: only its chain stays open (x, x/y collapsed)",
    got == "a,a/b,a/b/c",
    got
  )

  -- Closed by other means than the toggle key: the collapse on open still runs.
  user_open("x")
  local winid = adapter.get_winid()
  if winid then vim.api.nvim_win_close(winid, true) end
  settle(200)
  vim.cmd("edit " .. vim.fn.fnameescape(work .. "/top.lua"))
  tt.toggle("left")
  vim.wait(6000, function()
    return adapter.get_node_line(work .. "/top.lua") ~= nil
  end, 50)
  settle()
  check(
    "closed with nvim_win_close, reopened on top.lua: nothing below the root open",
    names(open_dirs()) == "",
    names(open_dirs())
  )

  -- Directly, on a live tree, without a reveal after it: the chain itself is kept.
  open_on("a/b/c/deep.lua")
  user_open("x")
  user_open("x/y")
  local ok_keep = adapter.collapse_all(work .. "/a/b/c/deep.lua")
  settle()
  check(
    "collapse_all(keep) on a live tree: deep.lua's chain stays open, x and x/y close",
    ok_keep and names(open_dirs()) == "a,a/b,a/b/c",
    names(open_dirs())
  )
  local remembered = {}
  for id, on in pairs(manager.get_state("filesystem").explicitly_opened_nodes or {}) do
    if on then remembered[#remembered + 1] = key(id):sub(#key(work) + 2) end
  end
  table.sort(remembered)
  check(
    "...neo-tree no longer remembers x and x/y as opened by hand (only the kept chain)",
    not vim.tbl_contains(remembered, "x") and not vim.tbl_contains(remembered, "x/y"),
    table.concat(remembered, ",")
  )

  user_open("x")
  user_open("x/y")
  local outside = vim.fn.tempname() .. "-outside.lua"
  vim.fn.writefile({ "x" }, outside)
  local ok_out = adapter.collapse_all(outside)
  settle()
  check(
    "a file outside the root keeps nothing open",
    ok_out and names(open_dirs()) == "",
    names(open_dirs())
  )
  os.remove(outside)

  open_on("a/b/c/deep.lua")
  vim.api.nvim_set_current_win(adapter.get_winid())
  local line = adapter.get_node_line(work .. "/a/b/c/deep.lua")
  if line then vim.api.nvim_win_set_cursor(0, { line, 0 }) end
  local ok_all = adapter.collapse_all(nil)
  settle()
  check(
    "collapse_all(): every folder closed",
    ok_all and names(open_dirs()) == "",
    names(open_dirs())
  )
  local node = adapter.get_current_node()
  check(
    "...the cursor on the top-level entry it was under",
    node ~= nil and key(node.path) == key(work .. "/a"),
    node and node.path or "nil"
  )
  vim.cmd("wincmd p")

  -- Option off: folders opened by hand survive close and open, as before.
  require("filetree").setup({
    adapter = "neotree",
    features = { auto_reveal = { enabled = false }, tree_toggle = { enabled = true } },
  })
  tt = require("filetree.features.nav.tree_toggle")
  got = reopen_after_manual_opens()
  check(
    "collapse_on_toggle off: x and x/y stay open next to a's chain",
    got == "a,a/b,a/b/c,x,x/y",
    got
  )
  pcall(adapter.close)
end

-- ── nvim-tree ────────────────────────────────────────────────────────────────

local function run_nvimtree()
  print("\n== nvimtree ==")
  local work = make_project()
  vim.cmd("cd " .. vim.fn.fnameescape(work))
  require("nvim-tree").setup({ hijack_netrw = false, update_focused_file = { enable = false } })
  require("filetree").setup({
    adapter = "nvimtree",
    features = { auto_reveal = { enabled = false } },
  })
  local adapter = require("filetree.adapter.nvimtree")
  local api = require("nvim-tree.api")
  vim.cmd("edit " .. vim.fn.fnameescape(work .. "/x/y/z.lua"))
  api.tree.open({ path = work })
  api.tree.find_file({ buf = work .. "/x/y/z.lua" })
  settle()
  api.tree.find_file({ buf = work .. "/a/b/c/deep.lua" })
  settle()
  local ok = adapter.collapse_all(work .. "/a/b/c/deep.lua")
  settle()
  check("collapse_all(keep) runs", ok)
  check(
    "...z.lua is hidden again, deep.lua still shown",
    adapter.get_node_line(work .. "/x/y/z.lua") == nil
      and adapter.get_node_line(work .. "/a/b/c/deep.lua") ~= nil
  )
  pcall(api.tree.close)
end

local ran = 0
if has_neotree and has_nui then
  run_neotree()
  ran = ran + 1
else
  print("\nneo-tree: not installed -- skipping that pass.")
end
if has_nvimtree then
  run_nvimtree()
  ran = ran + 1
else
  print("\nnvim-tree: not installed -- skipping that pass.")
end
if ran == 0 then print("\ncollapse_all_backends: no backend available -- nothing ran.") end

print(("\ncollapse_all_backends: %d passed, %d failed"):format(passed, failed))
vim.cmd(failed > 0 and "cq" or "qa!")
