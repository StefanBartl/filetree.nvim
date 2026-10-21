---@diagnostic disable: need-check-nil, missing-fields
-- smart_create_cursor_spec.lua -- after `a` creates a folder, the tree cursor
-- is on the new folder, not on the node it was on before.
--
-- Two halves of the same bug:
--   1. smart_create only refreshed the tree. A refresh keeps the cursor on the
--      node it was on, so with folders sorted first a new folder landed lines
--      above the cursor ("5-6 lines below the new folder").
--   2. On neo-tree the refresh did nothing at all: the adapter's state lookup
--      created neo-tree's filesystem state during filetree's own setup, before
--      neo-tree merged the user's config. The merge then replaced that state in
--      `state_by_tab` but left the old one in `all_states`, the only list
--      `manager.refresh` walks -- so it never reached the visible tree.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/smart_create_cursor_spec.lua
--
-- Exit 0 = all passed, 1 = a check failed.

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
      return
    end
  end
end
prepend_dep(
  { "FILETREE_LIB_NVIM", "LIB_NVIM_PATH", "LIB_NVIM_DIR" },
  "lib.nvim",
  "lib.nvim",
  "/lua/lib"
)

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
  check(name, got == want, ("got %s want %s"):format(vim.inspect(got), vim.inspect(want)))
end

local function slash(p)
  return (p:gsub("\\", "/"))
end

-- ── 1. smart_create puts the cursor on what it created ──────────────────────

local work = slash(vim.fn.tempname())
vim.fn.mkdir(work .. "/beta", "p")
vim.fn.writefile({ "x" }, work .. "/f.txt")

-- A tree window with a fake adapter. Its refresh renders later (asynchronously)
-- and then puts the cursor back where it was: on the same NODE ("node", like
-- most trees), or on the same LINE ("line", like neo-tree, which saves `lnum`)
-- -- also when the cursor was moved in between.
local restore = "node"
local tree_buf = vim.api.nvim_create_buf(false, true)
local tree_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(tree_win, tree_buf)

local rows ---@type string[]  rendered paths, one per line
local function render()
  vim.api.nvim_buf_set_lines(tree_buf, 0, -1, false, rows)
end

local current ---@type FiletreeNode
local expanded = {} ---@type FiletreeNode[]
local adapter = {
  name = "fake",
  get_winid = function()
    return tree_win
  end,
  get_current_node = function()
    return current
  end,
  get_node_line = function(p)
    for i, r in ipairs(rows) do
      if r == p then return i end
    end
  end,
  scroll_to_line = function(line)
    return (pcall(vim.api.nvim_win_set_cursor, tree_win, { line, 0 }))
  end,
  expand_node = function(node)
    expanded[#expanded + 1] = node
    return true
  end,
  refresh = function()
    local saved_line = vim.api.nvim_win_get_cursor(tree_win)[1]
    local cursor_path = rows[saved_line]
    vim.defer_fn(function()
      -- folders first, then files -- each sorted by name
      local dirs, files = {}, {}
      for name, kind in vim.fs.dir(work, { depth = 2 }) do
        local p = work .. "/" .. name
        if kind == "directory" then
          dirs[#dirs + 1] = p
        else
          files[#files + 1] = p
        end
      end
      table.sort(dirs)
      table.sort(files)
      rows = vim.list_extend(dirs, files)
      render()
      if restore == "line" then
        vim.api.nvim_win_set_cursor(tree_win, { math.min(saved_line, #rows), 0 })
      else
        for i, r in ipairs(rows) do
          if r == cursor_path then vim.api.nvim_win_set_cursor(tree_win, { i, 0 }) end
        end
      end
    end, 80)
    return true
  end,
}

rows = { work .. "/beta", work .. "/f.txt" }
render()

local answer
package.loaded["ui.kit"] = {
  input = function(opts)
    opts.on_submit(answer)
  end,
}
local smart_create = require("filetree.features.fileops.smart_create")
smart_create.setup({ enabled = true, keymap = false, notify_level = "off" }, adapter)

local function line_name()
  local p = rows[vim.api.nvim_win_get_cursor(tree_win)[1]]
  return p and vim.fn.fnamemodify(p, ":t")
end

-- Cursor on the file below the folders; the new folder sorts above it.
vim.api.nvim_win_set_cursor(tree_win, { 2, 0 })
current = { id = work .. "/f.txt", name = "f.txt", path = work .. "/f.txt", type = "file" }
answer = "alpha/"
smart_create.create()
vim.wait(1500, function()
  return line_name() == "alpha"
end, 10)
eq("cursor on the new folder, not on the node it was on", line_name(), "alpha")
eq("no folder expanded for a create next to a file", #expanded, 0)

-- Cursor on a collapsed folder: the new folder is created inside it, which is
-- only rendered once that folder is open.
vim.api.nvim_win_set_cursor(tree_win, { 2, 0 }) -- beta
current = {
  id = work .. "/beta",
  name = "beta",
  path = work .. "/beta",
  type = "directory",
  is_expanded = false,
}
answer = "inside/"
smart_create.create()
vim.wait(1500, function()
  return line_name() == "inside"
end, 10)
eq("cursor on the folder created inside the collapsed one", line_name(), "inside")
eq("the collapsed folder was opened", expanded[1] and expanded[1].path, work .. "/beta")

-- An expanded folder is left as it is (nvim-tree's expand_node toggles).
expanded = {}
current.is_expanded = true
answer = "second/"
smart_create.create()
vim.wait(1500, function()
  return line_name() == "second"
end, 10)
eq("an already open folder is not toggled", #expanded, 0)

-- An empty new file is written at once: only a file on disk is in the tree.
vim.api.nvim_win_set_cursor(tree_win, { 1, 0 })
current = { id = work .. "/f.txt", name = "f.txt", path = work .. "/f.txt", type = "file" }
answer = "new.txt"
smart_create.create()
eq("the empty file is on disk right away", vim.fn.getfsize(work .. "/new.txt"), 0)
vim.wait(1500, function()
  return line_name() == "new.txt"
end, 10)
eq("cursor on the new file", line_name(), "new.txt")
check(
  "the file is open in an editor window, not the tree",
  vim.api.nvim_get_current_win() ~= tree_win
)

-- A name that already exists opens that file and leaves it alone, also with a
-- template that would otherwise be written into a new one.
vim.fn.writefile({ "keep me" }, work .. "/keep.lua")
smart_create.setup(
  { enabled = true, keymap = false, notify_level = "off", auto_module_annot = true },
  adapter
)
answer = "keep.lua"
smart_create.create()
eq(
  "an existing file keeps its content",
  table.concat(vim.fn.readfile(work .. "/keep.lua"), "\n"),
  "keep me"
)
-- Compared resolved: on macOS the temp dir is under /var, a symlink to /private/var,
-- and the buffer name comes back resolved.
eq(
  "and is the one opened",
  vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)),
  vim.uv.fs_realpath(work .. "/keep.lua")
)

local function settle_all()
  vim.wait(1800, function()
    return false
  end, 10)
end
local function line_of(name)
  for i, r in ipairs(rows) do
    if vim.fn.fnamemodify(r, ":t") == name then return i end
  end
end
local function on_file()
  current = { id = work .. "/f.txt", name = "f.txt", path = work .. "/f.txt", type = "file" }
  vim.api.nvim_win_set_cursor(tree_win, { line_of("f.txt"), 0 })
end
smart_create.setup({ enabled = true, keymap = false, notify_level = "off" }, adapter)

for _, mode in ipairs({ "node", "line" }) do
  restore = mode
  -- A folder that already exists is in the tree before the refresh draws: the
  -- cursor goes there at once, and the refresh puts it back where it was.
  on_file()
  answer = "beta/"
  smart_create.create()
  settle_all()
  eq(mode .. " restore: an existing folder keeps the cursor after the refresh", line_name(), "beta")

  -- A new one, with the refresh putting the cursor back after it was placed.
  on_file()
  answer = "new_" .. mode .. "/"
  smart_create.create()
  settle_all()
  eq(mode .. " restore: a new folder keeps the cursor", line_name(), "new_" .. mode)
end

-- Moved by the user once it is there: left where the user put it.
on_file()
answer = "gamma/"
smart_create.create()
vim.wait(1500, function()
  return line_name() == "gamma"
end, 10)
vim.api.nvim_win_set_cursor(tree_win, { 1, 0 })
local moved_to = line_name()
settle_all()
eq("a cursor the user moved is not pulled back", line_name(), moved_to)

-- Nested: the new folders under the first one show up collapsed in a real
-- tree, so the cursor goes to the outermost new one.
on_file()
answer = "n1/n2/"
smart_create.create()
settle_all()
eq("a nested create puts the cursor on its outermost new folder", line_name(), "n1")

-- Spelled the way the tree spells paths: `./x` is `x`.
on_file()
answer = "./dot/"
smart_create.create()
settle_all()
eq("./dot/ is normalized and gets the cursor", line_name(), "dot")

-- A buffer still loaded for a file deleted outside Neovim is that old file:
-- creating the name anew must not write the old text back.
-- Loaded but not on screen (a hidden buffer): `:edit` then switches to it as it
-- is, without reading the (gone) file again.
vim.fn.writefile({ "old secret" }, work .. "/gone.txt")
local gone_buf = vim.fn.bufadd(work .. "/gone.txt")
vim.fn.bufload(gone_buf)
vim.bo[gone_buf].buflisted = true
os.remove(work .. "/gone.txt")
answer = "gone.txt"
smart_create.create()
eq(
  "a stale buffer does not bring the deleted content back",
  vim.fn.getfsize(work .. "/gone.txt"),
  0
)
-- ... and one with changes of the user's in it is left alone, nothing written.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "typed, not saved" })
os.remove(work .. "/gone.txt")
smart_create.create()
eq("a modified buffer for the name: nothing is written", vim.fn.getfsize(work .. "/gone.txt"), -1)
eq(
  "... and its text is still there",
  vim.api.nvim_buf_get_lines(0, 0, -1, false)[1],
  "typed, not saved"
)
vim.bo.modified = false

-- ask_clipboard does not ask about a file that exists: it is only opened.
local asked = 0
package.loaded["filetree.util.confirm_choice"] = function()
  asked = asked + 1
end
package.loaded["filetree.features.fileops.smart_create"] = nil
smart_create = require("filetree.features.fileops.smart_create")
smart_create.setup(
  { enabled = true, keymap = false, notify_level = "off", ask_clipboard = true },
  adapter
)
local real_getreg = vim.fn.getreg
vim.fn.getreg = function(r, ...)
  if r == "+" then return "from the clipboard" end
  return real_getreg(r, ...)
end
answer = "keep.lua"
smart_create.create()
eq("no clipboard question for a file that exists", asked, 0)
answer = "fresh.txt"
smart_create.create()
vim.fn.getreg = real_getreg
eq("... but for a new one", asked, 1)

-- ── 2. the neo-tree adapter never creates neo-tree's state ──────────────────

-- A fake `neo-tree.sources.manager` with neo-tree's own semantics: get_state
-- lazily creates a state, and every state goes into `all_states`.
local all_states, by_tab, created = {}, {}, 0
package.loaded["neo-tree.sources.manager"] = {
  get_state = function(name, tabid)
    tabid = tabid or vim.api.nvim_get_current_tabpage()
    if not by_tab[tabid] then
      created = created + 1
      by_tab[tabid] = { name = name, tabid = tabid }
      all_states[#all_states + 1] = by_tab[tabid]
    end
    return by_tab[tabid]
  end,
  _get_all_states = function()
    return all_states
  end,
}
local neotree = require("filetree.adapter.neotree")
-- A `position = "current"` tree has a window-only state (`id` = its window):
-- it is no tab state, and asking for the tab's must not create one.
local tab0 = vim.api.nvim_get_current_tabpage()
all_states[1] = { name = "filesystem", tabid = tab0, id = 4242, winid = tree_win }
eq("a window-only state is not the tab's tree", neotree.get_winid(), nil)
eq("... and no tab state is created for it", created, 0)
all_states[1] = nil
eq("no tree yet: no window", neotree.get_winid(), nil)
eq("no tree yet: position falls back to left", neotree.get_position(), "left")
eq("asking for the tree before it was shown creates no neo-tree state", created, 0)

-- Once neo-tree tracks a state with a live window, it is found.
local tab = vim.api.nvim_get_current_tabpage()
by_tab[tab] = { name = "filesystem", tabid = tab, winid = tree_win, current_position = "right" }
all_states[#all_states + 1] = by_tab[tab]
eq("a tracked state with a live window is found", neotree.get_winid(), tree_win)
eq("and its position is read", neotree.get_position(), "right")
eq("still nothing created", created, 0)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
