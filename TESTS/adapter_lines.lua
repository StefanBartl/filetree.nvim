---@diagnostic disable: missing-fields
-- Test doubles/config here fill in only what the unit under test reads — a
-- complete feature config would be noise, not coverage.
-- adapter_lines.lua — the adapter's line->node mapping, against a REAL tree.
--
-- `get_node_at_line(bufnr, linenr)` is what lets git_status, lsp_diagnostics,
-- size_info and copy_move's clipboard marker draw an extmark on a node's own
-- line. Getting it merely non-nil is not the bar: an off-by-one resolves every
-- line too, just to its neighbour, and the result is another file's git status
-- next to your file. So every assertion here resolves the line an extmark
-- actually sits on and compares it against the node that mark is about.
--
-- Unlike the other suites this one needs a real backend: the whole point is
-- the mapping between what the backend DREW and what it reports, which a stub
-- adapter cannot have. It drives neo-tree (plus nui/plenary/devicons) and
-- skips cleanly when they are not installed.
--
-- nvim-tree is NOT covered here. Its implementation goes through
-- `utils.get_nodes_by_line` + `core.get_nodes_starting_line()`, and a second
-- backend means a second set of plugins to resolve; a reader with nvim-tree
-- installed can port this file by swapping the setup block.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/adapter_lines.lua
--
-- Exit 0 = all passed (or skipped), 1 = a check failed.

-- Line-buffered, so a run that has to be killed still shows how far it got.
io.stdout:setvbuf("line")
-- A leftover swap file from an interrupted run turns bufload() into a prompt
-- that a headless session can never answer -- it just hangs.
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
---@param env string[]  Env vars to honour first.
---@param names string[]  Directory names to look for beside the repo / in lazy.
---@param probe string  Path under the candidate that must exist.
---@return string?
local function resolve(env, names, probe)
  local candidates = {}
  for _, e in ipairs(env) do
    local v = vim.env[e]
    if v and v ~= "" then candidates[#candidates + 1] = v end
  end
  for _, name in ipairs(names) do
    candidates[#candidates + 1] = vim.fn.fnamemodify(root_dir, ":h") .. "/" .. name
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

if not (has_nui and has_neotree) then
  print("adapter_lines: neo-tree and/or nui not found -- skipping (not a failure).")
  print("  set $FILETREE_NEOTREE to a neo-tree.nvim checkout to run this suite.")
  vim.cmd("qa!")
  return
end

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

local function slash(p)
  return (tostring(p):gsub("\\", "/"))
end

-- ── A real little project, with a real git repo ──────────────────────────────
local work = slash((vim.env.TEMP or "/tmp") .. "/filetree-live-gnal")
vim.fn.delete(work, "rf")
vim.fn.mkdir(work .. "/src", "p")
vim.fn.writefile({ "-- committed" }, work .. "/src/a.lua")
vim.fn.writefile({ "-- committed" }, work .. "/src/b.lua")
vim.fn.writefile({ "# Readme" }, work .. "/README.md")

local function git(...)
  vim.fn.system({ "git", "-C", work, ... })
end
git("init", "-q")
git("config", "user.email", "t@t")
git("config", "user.name", "t")
git("add", "-A")
git("commit", "-qm", "init")
vim.fn.writefile({ "# Readme", "modified now" }, work .. "/README.md")
vim.fn.writefile({ "brand new" }, work .. "/untracked.txt")

vim.cmd("cd " .. vim.fn.fnameescape(work))

require("neo-tree").setup({
  close_if_last_window = false,
  filesystem = {
    use_libuv_file_watcher = false,
    follow_current_file = { enabled = false },
    filtered_items = { visible = true, hide_dotfiles = false, hide_gitignored = false },
  },
  window = { position = "left", width = 40 },
})

require("filetree").setup({
  adapter = "neotree",
  features = {
    git_status = { enabled = true },
    lsp_diagnostics = { enabled = true },
    size_info = { enabled = true, show_files = true, show_dirs = false },
    copy_move = { enabled = true },
    filter = { enabled = true },
  },
})

-- The :Neotree command lives in neo-tree's plugin/ file, which an rtp
-- prepended after startup never sources -- drive its command module directly.
local nt_cmd = require("neo-tree.command")
nt_cmd.execute({ action = "show", source = "filesystem", dir = work })
vim.wait(3000, function()
  local ok, a = pcall(require, "filetree.adapter.neotree")
  return ok and a.get_bufnr() ~= nil
end, 50)

local adapter = require("filetree.adapter.neotree")
local bufnr = adapter.get_bufnr()

-- Expand src/ so nested lines exist too -- a flat tree would not catch a
-- depth-dependent off-by-one.
nt_cmd.execute({
  action = "show",
  source = "filesystem",
  dir = work,
  reveal_file = work .. "/src/a.lua",
})
vim.wait(1200, function()
  return false
end, 50)

---Re-read the rendered buffer and resolve every line through the adapter.
---Done fresh per feature: neo-tree re-renders on its own schedule (an async
---git fetch, a watcher event), so a snapshot taken earlier can describe a
---layout that no longer exists.
---@return string[] lines, table<integer, FiletreeNode?> by_line
local function snapshot()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local by_line = {}
  for i = 0, #lines - 1 do
    by_line[i] = adapter.get_node_at_line(bufnr, i)
  end
  return lines, by_line
end

---@param ns_name string
---@return table[]
local function marks(ns_name)
  local ns = vim.api.nvim_get_namespaces()[ns_name]
  if not ns then return {} end
  return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
end

---@param m table
---@return string
local function mark_text(m)
  local d = m[4] or {}
  local txt = ""
  for _, chunk in ipairs(d.virt_text or {}) do
    txt = txt .. chunk[1]
  end
  return txt ~= "" and txt or (d.hl_group or "?")
end

---Print what a feature drew, next to the node the adapter says is on that line.
---@param label string
---@param ms table[]
---@param by_line table<integer, FiletreeNode?>
local function report(label, ms, by_line)
  for _, m in ipairs(ms) do
    local n = by_line[m[2]]
    print(
      string.format(
        "    %s line %2d: %-8s -> %s",
        label,
        m[2],
        mark_text(m),
        n and (n.type:sub(1, 3) .. " " .. vim.fn.fnamemodify(n.path, ":t")) or "nil"
      )
    )
  end
end

print("\n== adapter.get_node_at_line against a real neo-tree render ==")
check("the tree buffer exists", bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr), tostring(bufnr))

local lines, by_line = snapshot()
local resolved = 0
for i = 0, #lines - 1 do
  if by_line[i] then resolved = resolved + 1 end
end

print("  -- rendered buffer (line: text -> resolved node) --")
for i = 0, #lines - 1 do
  local n = by_line[i]
  print(
    string.format(
      "  [%02d] %-40s -> %s",
      i,
      (lines[i + 1] or ""):gsub("%s+$", ""),
      n and (n.type .. " " .. vim.fn.fnamemodify(n.path, ":t")) or "nil"
    )
  )
end
check("it resolved nodes for the rendered lines", resolved >= 5, "resolved=" .. resolved)

-- The mapping must be RIGHT, not merely non-nil. Neo-tree truncates the root
-- label to the window width, so that one line is compared by prefix.
local misaligned = {}
for i = 0, #lines - 1 do
  local n = by_line[i]
  if n then
    local text = lines[i + 1] or ""
    local hit = text:find(n.name, 1, true) ~= nil
    if not hit and i == 0 then
      hit = text:find(n.name:sub(1, math.max(8, #text - 6)), 1, true) ~= nil
    end
    if not hit then
      misaligned[#misaligned + 1] = string.format("[%d] %q vs node %q", i, text, n.name)
    end
  end
end
check(
  "every resolved node's name is the text drawn on that line",
  #misaligned == 0,
  table.concat(misaligned, "; ")
)
check(
  "a bufnr that is not the tree buffer resolves to nil",
  adapter.get_node_at_line(vim.api.nvim_create_buf(false, true), 0) == nil
)
check("a line past the end resolves to nil", adapter.get_node_at_line(bufnr, #lines + 50) == nil)

local features = require("filetree.features")

-- ── git_status ───────────────────────────────────────────────────────────────
print("\n== git_status ==")
local _, git_status = features.load("git_status")
git_status.refresh()
-- refresh() runs git in the background and renders from its callback, so the
-- first marks can describe a layout neo-tree has already replaced. Wait for the
-- status to have landed, let the tree settle, then render once more against the
-- buffer we are about to read.
vim.wait(3000, function()
  return #marks("filetree_git_status") > 0
end, 50)
vim.wait(500, function()
  return false
end, 50)
git_status._render()
local gm = marks("filetree_git_status")
local _, g_by_line = snapshot()
report("git", gm, g_by_line)
check("git_status placed signs", #gm > 0)

local dirty = { ["README.md"] = true, ["untracked.txt"] = true, ["src"] = true, [""] = true }
local g_bad, g_files = {}, {}
for _, m in ipairs(gm) do
  local n = g_by_line[m[2]]
  local rel = n and slash(n.path):gsub("^" .. vim.pesc(work) .. "/?", "") or "<nil>"
  g_files[#g_files + 1] = rel
  if not dirty[rel] then g_bad[#g_bad + 1] = string.format("line %d -> %s", m[2], rel) end
end
check(
  "every git sign sits on a line whose node really is dirty",
  #g_bad == 0,
  table.concat(g_bad, "; ")
)
check(
  "the modified file got a sign",
  vim.tbl_contains(g_files, "README.md"),
  table.concat(g_files, ", ")
)
check(
  "the untracked file got one too",
  vim.tbl_contains(g_files, "untracked.txt"),
  table.concat(g_files, ", ")
)

-- ── size_info ────────────────────────────────────────────────────────────────
print("\n== size_info ==")
local _, size_info = features.load("size_info")
size_info._render()
local sm = marks("filetree_size_info")
local _, s_by_line = snapshot()
report("size", sm, s_by_line)
check("size_info placed sizes", #sm > 0)

local s_bad = {}
for _, m in ipairs(sm) do
  local n = s_by_line[m[2]]
  -- " 9 B" for an on-disk 9-byte file: the number in the virt_text has to be
  -- the size of the file the adapter says is on that line, not a neighbour's.
  local want = n and vim.fn.getfsize(n.path) or -1
  local got = tonumber(mark_text(m):match("(%d+)%s*B") or "")
  if not n or got ~= want then
    s_bad[#s_bad + 1] = string.format(
      "line %d: drew %s, node %s is %d B",
      m[2],
      mark_text(m),
      n and vim.fn.fnamemodify(n.path, ":t") or "<nil>",
      want
    )
  end
end
check(
  "every size is the size of the file on that very line",
  #s_bad == 0,
  table.concat(s_bad, "; ")
)

-- ── lsp_diagnostics ──────────────────────────────────────────────────────────
print("\n== lsp_diagnostics ==")
-- No language server here, so publish diagnostics directly -- the feature
-- reads vim.diagnostic.get(nil), not any particular client.
local diag_buf = vim.fn.bufadd(work .. "/src/b.lua")
vim.fn.bufload(diag_buf)
vim.diagnostic.set(vim.api.nvim_create_namespace("live_test_diag"), diag_buf, {
  { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "boom" },
})
local _, lsp_diagnostics = features.load("lsp_diagnostics")
-- The counts are recomputed from a DiagnosticChanged autocmd, not inside
-- _render -- so rendering in the same tick as vim.diagnostic.set draws nothing.
vim.wait(800, function()
  return false
end, 50)
lsp_diagnostics._render()
local dm = marks("filetree_lsp_diagnostics")
local _, d_by_line = snapshot()
report("diag", dm, d_by_line)
check("lsp_diagnostics placed markers", #dm > 0)

local d_bad, saw_file = {}, false
for _, m in ipairs(dm) do
  local n = d_by_line[m[2]]
  local p = n and slash(n.path) or ""
  -- src/b.lua itself, or a directory containing it (the feature aggregates).
  local ok = p == slash(work .. "/src/b.lua")
    or (n and n.type == "directory" and slash(work .. "/src/b.lua"):sub(1, #p + 1) == p .. "/")
  if p == slash(work .. "/src/b.lua") then saw_file = true end
  if not ok then
    d_bad[#d_bad + 1] = string.format("line %d -> %s", m[2], p ~= "" and p or "<nil>")
  end
end
check(
  "every diagnostic marker is on b.lua or a directory above it",
  #d_bad == 0,
  table.concat(d_bad, "; ")
)
check("the file with the diagnostic got its own marker", saw_file)

-- ── copy_move clipboard marker ───────────────────────────────────────────────
print("\n== copy_move clipboard marker ==")
local _, copy_move = features.load("copy_move")
local c_lines, c_by_line = snapshot()
local cut_node, cut_line
for i = 0, #c_lines - 1 do
  local n = c_by_line[i]
  if n and n.type == "file" then
    cut_node, cut_line = n, i
    break
  end
end
local winid = adapter.get_winid()
if winid and cut_line then
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_win_set_cursor(winid, { cut_line + 1, 0 })
end
copy_move.stage_cut()
local cm = marks("filetree_copy_move")
local _, c2_by_line = snapshot()
report("cut", cm, c2_by_line)
check("copy_move drew the clipboard marker", #cm > 0)
check(
  "the marker is on the node that was actually cut",
  #cm == 1 and c2_by_line[cm[1][2]] ~= nil and c2_by_line[cm[1][2]].path == cut_node.path,
  string.format(
    "cut %s, marker on %s",
    cut_node and vim.fn.fnamemodify(cut_node.path, ":t") or "?",
    #cm > 0 and c2_by_line[cm[1][2]] and vim.fn.fnamemodify(c2_by_line[cm[1][2]].path, ":t") or "?"
  )
)
copy_move.clear()

-- ── filter's dim fallback ────────────────────────────────────────────────────
print("\n== filter (dim fallback) ==")
local _, filter = features.load("filter")
filter.apply("a.lua")
check(
  "on neo-tree the NATIVE filter runs, so nothing is dimmed (see report)",
  #marks("filetree_filter") == 0,
  "unexpectedly dimmed " .. #marks("filetree_filter") .. " line(s)"
)
filter.clear()

-- Force the fallback to exercise the branch that uses get_node_at_line at all.
-- try_native_filter dispatches on _adapter.name, so renaming the adapter for
-- one call is exactly the "backend with no native filter" case -- and, unlike
-- breaking require for neo-tree's own manager module, it disturbs nothing else.
local real_name = adapter.name
adapter.name = "no-native-filter"
filter.apply("a.lua")
adapter.name = real_name

local fm = marks("filetree_filter")
local f_lines, f_by_line = snapshot()
report("dim", fm, f_by_line)
check("with the native filter unavailable, the dim fallback runs", #fm > 0)

local dimmed = {}
for _, m in ipairs(fm) do
  dimmed[m[2]] = true
end
local f_bad = {}
for i = 0, #f_lines - 1 do
  local n = f_by_line[i]
  local matches = n ~= nil and n.name:lower():find("a.lua", 1, true) ~= nil
  if matches and dimmed[i] then
    f_bad[#f_bad + 1] = string.format("line %d (%s) matched but was dimmed", i, n.name)
  elseif n and not matches and not dimmed[i] then
    f_bad[#f_bad + 1] = string.format("line %d (%s) did not match but was not dimmed", i, n.name)
  end
end
check("exactly the non-matching node lines were dimmed", #f_bad == 0, table.concat(f_bad, "; "))
filter.clear()

print(string.format("\nlive: %d passed, %d failed", passed, failed))
vim.cmd(failed > 0 and "cq" or "qa!")
