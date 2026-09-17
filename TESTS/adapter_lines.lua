---@diagnostic disable: missing-fields
-- Test doubles/config here fill in only what the unit under test reads — a
-- complete feature config would be noise, not coverage.
-- adapter_lines.lua — the adapter's line->node mapping, against REAL trees.
--
-- `get_node_at_line(bufnr, linenr)` is what lets git_status, lsp_diagnostics,
-- size_info and copy_move's clipboard marker draw an extmark on a node's own
-- line. Getting it merely non-nil is not the bar: an off-by-one resolves every
-- line too, just to its neighbour, and the result is another file's git status
-- next to your file. So every assertion here resolves the line an extmark
-- actually sits on and compares it against the node that mark is about.
--
-- Unlike the other suites this one needs real backends: the whole point is the
-- mapping between what a backend DREW and what it reports, which a stub
-- adapter cannot have. It runs neo-tree and nvim-tree, and skips whichever is
-- not installed.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/adapter_lines.lua
--
-- $FILETREE_ADAPTER_LINES limits it to one backend, e.g. "nvimtree".
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

local passed, failed, skipped = 0, 0, 0
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

---A real little project, with a real git repo: one committed-then-modified
---file and one untracked file, both at the ROOT so no expansion is needed for
---git_status to have something to decorate.
---@param tag string
---@return string work
local function make_project(tag)
  local work = slash((vim.env.TEMP or "/tmp") .. "/filetree-lines-" .. tag)
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
  return work
end

-- ── One backend's pass ───────────────────────────────────────────────────────

---@class BackendSpec
---@field name string             Adapter name, e.g. "neotree".
---@field open fun(work: string)  Open that backend's tree on `work`.
---@field native_filter_prompts boolean  Whether its native filter opens a UI prompt.

---@param spec BackendSpec
local function run_backend(spec)
  print(("\n%s\n== %s ==\n%s"):format(("="):rep(66), spec.name, ("="):rep(66)))

  local work = make_project(spec.name)
  vim.cmd("cd " .. vim.fn.fnameescape(work))

  require("filetree").setup({
    adapter = spec.name,
    features = {
      git_status = { enabled = true },
      lsp_diagnostics = { enabled = true },
      size_info = { enabled = true, show_files = true, show_dirs = false },
      copy_move = { enabled = true },
      filter = { enabled = true },
    },
  })

  local adapter = require("filetree.adapter." .. spec.name)
  spec.open(work)
  vim.wait(6000, function()
    local b = adapter.get_bufnr()
    return b ~= nil and vim.api.nvim_buf_line_count(b) > 2
  end, 50)
  vim.wait(800, function()
    return false
  end, 50)

  local bufnr = adapter.get_bufnr()
  check(
    "the tree buffer exists",
    bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr),
    tostring(bufnr)
  )
  if not bufnr then return end

  ---Re-read the rendered buffer and resolve every line through the adapter.
  ---Done fresh per feature: both backends re-render on their own schedule (an
  ---async git fetch, a watcher event), so a snapshot taken earlier can
  ---describe a layout that no longer exists.
  local function snapshot()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local by_line = {}
    for i = 0, #lines - 1 do
      by_line[i] = adapter.get_node_at_line(bufnr, i)
    end
    return lines, by_line
  end

  local function marks(ns_name)
    local ns = vim.api.nvim_get_namespaces()[ns_name]
    if not ns then return {} end
    return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  end

  local function mark_text(m)
    local d = m[4] or {}
    local txt = ""
    for _, chunk in ipairs(d.virt_text or {}) do
      txt = txt .. chunk[1]
    end
    return txt ~= "" and txt or (d.hl_group or "?")
  end

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

  -- ── The mapping itself ─────────────────────────────────────────────────────
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
  check("it resolved nodes for the rendered lines", resolved >= 4, "resolved=" .. resolved)

  -- The mapping must be RIGHT, not merely non-nil. Both backends render the
  -- root line as a path label rather than the node's `name`, so line 0 is
  -- compared by path instead.
  local misaligned = {}
  for i = 0, #lines - 1 do
    local n = by_line[i]
    if n and i > 0 then
      local text = lines[i + 1] or ""
      if not text:find(n.name, 1, true) then
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
    "line 0 resolves to the tree's own root directory",
    by_line[0] ~= nil and by_line[0].type == "directory" and slash(by_line[0].path) == slash(work),
    by_line[0] and slash(by_line[0].path) or "nil"
  )

  -- A line the backend drew that is NOT a node must resolve to nil. neo-tree's
  -- `(N hidden items)` notice is one: it carries a synthetic id that looks
  -- enough like a path to fool a caller into statting it once per render and,
  -- through the same conversion, into aiming a delete at it.
  local notice_line
  for i = 0, #lines - 1 do
    local text = lines[i + 1] or ""
    if text:find("hidden item", 1, true) or text:find("empty folder", 1, true) then
      notice_line = i
      break
    end
  end
  if notice_line then
    check(
      "a notice line resolves to nil, not to a pseudo-node",
      by_line[notice_line] == nil,
      "line "
        .. notice_line
        .. " -> "
        .. tostring(by_line[notice_line] and by_line[notice_line].path)
    )
  else
    print("  --   (this backend rendered no notice line; nothing to check)")
    skipped = skipped + 1
  end

  -- `get_node_line` is the inverse: it answers "which line is this path on",
  -- and reveal/scroll_to_line steer the cursor with it. The two must agree, or
  -- revealing a file parks the cursor on its neighbour.
  local gl_bad = {}
  for i = 0, #lines - 1 do
    local n = by_line[i]
    if n then
      local got = adapter.get_node_line(n.path)
      if got ~= i + 1 then
        gl_bad[#gl_bad + 1] =
          string.format("%s is on line %d, get_node_line says %s", n.name, i + 1, tostring(got))
      end
    end
  end
  check(
    "get_node_line is the exact inverse of get_node_at_line",
    #gl_bad == 0,
    table.concat(gl_bad, "; ")
  )

  check(
    "a bufnr that is not the tree buffer resolves to nil",
    adapter.get_node_at_line(vim.api.nvim_create_buf(false, true), 0) == nil
  )
  check("a line past the end resolves to nil", adapter.get_node_at_line(bufnr, #lines + 50) == nil)

  -- Every decorating feature calls this once per rendered line, so a per-call
  -- cost in the tens of microseconds is tens of milliseconds per render on a
  -- large tree. It was exactly that on neo-tree until the conversion stopped
  -- routing through a helper that stats the filesystem for an is-directory
  -- flag it discards. The bound is loose on purpose -- this guards against a
  -- regression of that shape, not against machine-to-machine variance.
  local reps = 2000
  adapter.get_node_at_line(bufnr, 1)
  local t0 = vim.uv.hrtime()
  for _ = 1, reps do
    adapter.get_node_at_line(bufnr, 1)
  end
  local us = (vim.uv.hrtime() - t0) / reps / 1000
  print(string.format("    cost: %.2f us/call (~%.1f ms per 1000 lines x 4 features)", us, us * 4))
  check("one lookup stays well under a filesystem stat (~20us here)", us < 5, us .. " us/call")

  local features = require("filetree.features")

  -- ── git_status ─────────────────────────────────────────────────────────────
  print("\n  -- git_status --")
  local _, git_status = features.load("git_status")
  git_status.refresh()
  -- refresh() runs git in the background and renders from its callback, so the
  -- first marks can describe a layout the backend has already replaced. Wait
  -- for the status to have landed, let the tree settle, then render once more
  -- against the buffer we are about to read.
  vim.wait(4000, function()
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

  -- ── size_info ──────────────────────────────────────────────────────────────
  print("\n  -- size_info --")
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

  -- ── lsp_diagnostics ────────────────────────────────────────────────────────
  print("\n  -- lsp_diagnostics --")
  -- No language server here, so publish diagnostics directly -- the feature
  -- reads vim.diagnostic.get(nil), not any particular client.
  local diag_buf = vim.fn.bufadd(work .. "/src/b.lua")
  vim.fn.bufload(diag_buf)
  vim.diagnostic.set(vim.api.nvim_create_namespace("live_test_diag_" .. spec.name), diag_buf, {
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
  local target = slash(work .. "/src/b.lua")
  for _, m in ipairs(dm) do
    local n = d_by_line[m[2]]
    local p = n and slash(n.path) or ""
    -- src/b.lua itself, or a directory containing it (the feature aggregates).
    local ok = p == target or (n and n.type == "directory" and target:sub(1, #p + 1) == p .. "/")
    if p == target then saw_file = true end
    if not ok then
      d_bad[#d_bad + 1] = string.format("line %d -> %s", m[2], p ~= "" and p or "<nil>")
    end
  end
  check(
    "every diagnostic marker is on b.lua or a directory above it",
    #d_bad == 0,
    table.concat(d_bad, "; ")
  )

  -- Only meaningful when the file is on screen at all: the two backends
  -- differ in whether opening the tree leaves `src/` expanded, and a marker
  -- cannot land on a line that was never drawn. The aggregation onto the
  -- parent directories above is checked either way.
  local b_rendered = false
  for _, n in pairs(d_by_line) do
    if n and slash(n.path) == target then b_rendered = true end
  end
  if b_rendered then
    check("the file with the diagnostic got its own marker", saw_file)
  else
    print("  --   (src/ is collapsed here, so b.lua has no line; parents checked above)")
    skipped = skipped + 1
  end

  -- ── copy_move clipboard marker ─────────────────────────────────────────────
  print("\n  -- copy_move clipboard marker --")
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
      #cm > 0 and c2_by_line[cm[1][2]] and vim.fn.fnamemodify(c2_by_line[cm[1][2]].path, ":t")
        or "?"
    )
  )
  copy_move.clear()

  -- ── filter ─────────────────────────────────────────────────────────────────
  print("\n  -- filter (native) --")
  local _, filter = features.load("filter")

  local function rendered()
    return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  end

  -- The native path has to actually narrow the listing. Both branches used to
  -- call an API that no longer exists (neo-tree) or that takes no argument and
  -- prompts (nvim-tree), and reported success either way -- so `/` did nothing
  -- at all and the dim fallback was never reached. "Nothing was dimmed" alone
  -- would still pass for that; the listing itself has to change.
  check(
    "the unfiltered listing shows untracked.txt",
    rendered():find("untracked.txt", 1, true) ~= nil
  )

  filter.apply("a.lua")
  vim.wait(2000, function()
    return rendered():find("untracked.txt", 1, true) == nil
  end, 50)
  check(
    "the backend's own filter really narrowed the listing",
    rendered():find("untracked.txt", 1, true) == nil,
    rendered()
  )
  check(
    "the native filter handled it, so nothing was dimmed",
    #marks("filetree_filter") == 0,
    "dimmed " .. #marks("filetree_filter") .. " line(s)"
  )

  filter.clear()
  vim.wait(2000, function()
    return rendered():find("untracked.txt", 1, true) ~= nil
  end, 50)
  check(
    "clearing the filter restores the listing",
    rendered():find("untracked.txt", 1, true) ~= nil,
    rendered()
  )

  print("\n  -- filter (dim fallback) --")
  -- Force the fallback to exercise the branch that uses get_node_at_line at
  -- all. try_native_filter dispatches on _adapter.name, so renaming the
  -- adapter for one call is exactly the "backend with no native filter" case,
  -- which is what netrw/oil/mini.files are.
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

  pcall(adapter.close)
  vim.wait(500, function()
    return false
  end, 50)
end

-- ── Run ──────────────────────────────────────────────────────────────────────

local wanted = vim.env.FILETREE_ADAPTER_LINES
local function want(name)
  return wanted == nil or wanted == "" or wanted:find(name, 1, true) ~= nil
end

local ran = 0

if has_neotree and has_nui and want("neotree") then
  require("neo-tree").setup({
    close_if_last_window = false,
    filesystem = { use_libuv_file_watcher = false, follow_current_file = { enabled = false } },
    window = { position = "left", width = 40 },
  })
  run_backend({
    name = "neotree",
    open = function(work)
      -- The :Neotree command lives in neo-tree's plugin/ file, which an rtp
      -- prepended after startup never sources -- drive its command module.
      require("neo-tree.command").execute({ action = "show", source = "filesystem", dir = work })
    end,
  })
  ran = ran + 1
else
  print("\nneo-tree: not installed (or excluded) -- skipping that pass.")
end

if has_nvimtree and want("nvimtree") then
  require("nvim-tree").setup({
    hijack_netrw = false,
    update_focused_file = { enable = false },
    renderer = { group_empty = true },
    view = { width = 40 },
  })
  run_backend({
    name = "nvimtree",
    open = function(work)
      require("nvim-tree.api").tree.open({ path = work })
    end,
  })
  ran = ran + 1
else
  print("\nnvim-tree: not installed (or excluded) -- skipping that pass.")
end

if ran == 0 then
  print("\nadapter_lines: no backend available -- nothing ran (not a failure).")
  print("  $FILETREE_NEOTREE / $FILETREE_NVIMTREE point at checkouts.")
end

print(("\nadapter_lines: %d passed, %d failed, %d n/a"):format(passed, failed, skipped))
vim.cmd(failed > 0 and "cq" or "qa!")
