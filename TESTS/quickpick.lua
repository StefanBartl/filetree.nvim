-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil, missing-fields, duplicate-set-field
-- Test doubles here implement only what the unit under test calls -- a full
-- FiletreeAdapter would be noise, not coverage.
--
-- quickpick.lua -- headless tests for `features/nav/quickpick`, the numbered
-- quick-pick mode.
--
-- Four parts, each pinning something different:
--
--   1. Pure logic (`quickpick.logic`, `quickpick.keys.silence_candidates`):
--      numbering, ordering, the content filter, the viewport range, the cap,
--      the input state machine, the indicator text and geometry. No tree, no
--      window, no key pressed.
--   2. The order `get_visible_nodes` hands over, per adapter. mini.files, oil
--      and netrw run their REAL adapter modules against stand-ins for the
--      underlying plugin (the same seams `gaps.lua` uses); neo-tree and
--      nvim-tree -- whose real plugins only the opt-in `adapter_lines.lua`
--      suite can load -- are shaped doubles of what their adapters emit
--      (neo-tree walks its nui tree depth first, nvim-tree sorts its line map).
--      Whatever the backend does, the numbers must follow the rendered order.
--   3. The mode's lifecycle against a fake adapter that owns a real buffer and
--      window and redraws it like a tree does: keys are pressed with
--      `nvim_feedkeys` through the real buffer-local mappings. Covers start,
--      the open-mode prefixes, directory toggling, content cycling, Esc,
--      the idle timeout (and its restart on a key), silencing and the exact
--      restore of a mapping the tree had on that very key, focus loss,
--      scroll/resize/expand renumbering, boot of a closed tree, and that
--      nothing -- timer, autocmd, extmark, float, key -- outlives the mode.
--   4. The wiring: `filetree.setup()` with the feature on, the global keys
--      (a count roots the tree), `:Filetree quickpick`, config validation.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/quickpick.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)

local lib_candidates = {}
for _, env in ipairs({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" then lib_candidates[#lib_candidates + 1] = v end
end
lib_candidates[#lib_candidates + 1] = vim.fn.fnamemodify(root_dir, ":h") .. "/lib.nvim"
lib_candidates[#lib_candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"
for _, candidate in ipairs(lib_candidates) do
  if vim.fn.isdirectory(candidate .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(candidate)
    break
  end
end

-- ui.nvim: `filetree.setup()` loads refs eagerly and refs requires `ui.kit`.
local ui_candidates = {}
for _, env in ipairs({ "FILETREE_UI_NVIM", "UI_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" then ui_candidates[#ui_candidates + 1] = v end
end
ui_candidates[#ui_candidates + 1] = vim.fn.fnamemodify(root_dir, ":h") .. "/ui.nvim"
ui_candidates[#ui_candidates + 1] = vim.fn.stdpath("data") .. "/lazy/ui.nvim"
for _, candidate in ipairs(ui_candidates) do
  if vim.fn.isdirectory(candidate .. "/lua/ui") == 1 then
    vim.opt.rtp:prepend(candidate)
    break
  end
end

local uv = vim.uv or vim.loop

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
  check(name, got == want, ("got %s want %s"):format(vim.inspect(got), vim.inspect(want)))
end
local function same(name, got, want)
  check(
    name,
    vim.deep_equal(got, want),
    ("got %s want %s"):format(vim.inspect(got), vim.inspect(want))
  )
end

---Run one section; an error inside it is a failed check, not the end of the file
---(one thrown assertion must not leave a stubbed adapter behind for the next).
---@param name string
---@param fn fun()
local function section(name, fn)
  print("-- " .. name)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then check(name .. ": no error", false, tostring(err)) end
end

local logic = require("filetree.features.nav.quickpick.logic")
local keys_mod = require("filetree.features.nav.quickpick.keys")

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Pure logic
-- ═══════════════════════════════════════════════════════════════════════════════

---@param name string
---@param type_ "file"|"directory"
---@param line integer?
---@param depth integer?
---@param expanded boolean?
local function node(name, type_, line, depth, expanded)
  return {
    id = "/p/" .. name,
    name = name,
    path = "/p/" .. name,
    type = type_,
    depth = depth or 1,
    line_number = line,
    is_expanded = expanded,
  }
end

section("logic: labels and capacity", function()
  eq("format_label pads to the width", logic.format_label(7, 2), "07")
  eq("format_label width 3", logic.format_label(7, 3), "007")
  eq("format_label width 1", logic.format_label(7, 1), "7")
  eq("capacity(2) is 100", logic.capacity(2), 100)
  eq("capacity(3) is 1000", logic.capacity(3), 1000)
  eq("next_content all -> files", logic.next_content("all"), "files")
  eq("next_content files -> folders", logic.next_content("files"), "folders")
  eq("next_content folders -> all", logic.next_content("folders"), "all")
  eq("next_content of garbage restarts at all", logic.next_content("bogus"), "all")
  eq("next_content of nil restarts at all", logic.next_content(nil), "all")
  check(
    "is_content accepts the three kinds",
    logic.is_content("all") and logic.is_content("files") and logic.is_content("folders")
  )
  check("is_content rejects others", not logic.is_content("both") and not logic.is_content(nil))
  check(
    "is_open_mode accepts edit/split/vsplit/tab",
    logic.is_open_mode("edit")
      and logic.is_open_mode("split")
      and logic.is_open_mode("vsplit")
      and logic.is_open_mode("tab")
  )
  check(
    "is_open_mode rejects preview and nonsense",
    not logic.is_open_mode("preview") and not logic.is_open_mode("float")
  )
end)

section("logic: assign", function()
  local nodes = {
    node("a", "directory", 1, 1, true),
    node("a1.lua", "file", 2, 2),
    node("b.lua", "file", 3, 1),
    node("c", "directory", 4, 1, false),
  }
  local all = logic.assign(nodes)
  eq("all: four entries", #all, 4)
  eq("numbers start at 0", all[1].index, 0)
  eq("label of the first is 00", all[1].label, "00")
  eq("last index is 3", all[4].index, 3)
  eq("entry carries the rendered line", all[3].line, 3)
  eq("entry carries the node", all[2].node.name, "a1.lua")

  local files = logic.assign(nodes, { content = "files" })
  same(
    "files: only files, renumbered from 0",
    vim.tbl_map(function(e)
      return e.node.name .. "=" .. e.label
    end, files),
    { "a1.lua=00", "b.lua=01" }
  )
  local folders = logic.assign(nodes, { content = "folders" })
  same(
    "folders: only directories, renumbered from 0",
    vim.tbl_map(function(e)
      return e.node.name .. "=" .. e.label
    end, folders),
    { "a=00", "c=01" }
  )

  local ranged = logic.assign(nodes, { range = { 2, 3 } })
  same(
    "range keeps only nodes inside the viewport",
    vim.tbl_map(function(e)
      return e.node.name
    end, ranged),
    { "a1.lua", "b.lua" }
  )
  eq("range: numbering restarts at 0 inside the viewport", ranged[1].label, "00")
  eq("range: empty viewport gives no entries", #logic.assign(nodes, { range = { 10, 20 } }), 0)

  local wide = logic.assign(nodes, { width = 3 })
  eq("width 3: three-digit labels", wide[2].label, "001")
end)

section("logic: assign orders by rendered line, not by array order", function()
  -- Backends disagree on array order; the number must follow the screen.
  local shuffled = {
    node("c.lua", "file", 3),
    node("a.lua", "file", 1),
    node("b.lua", "file", 2),
  }
  local out = logic.assign(shuffled)
  same(
    "sorted by line",
    vim.tbl_map(function(e)
      return e.node.name
    end, out),
    { "a.lua", "b.lua", "c.lua" }
  )

  -- Two nodes on one line (a grouped chain): the adapter's relative order holds.
  local grouped = {
    node("first", "directory", 5),
    node("second", "directory", 5),
    node("above", "file", 4),
  }
  local g = logic.assign(grouped)
  same(
    "equal lines keep adapter order",
    vim.tbl_map(function(e)
      return e.node.name
    end, g),
    { "above", "first", "second" }
  )
end)

section("logic: assign skips nodes that cannot be drawn", function()
  local nodes = {
    node("noline", "file", nil),
    node("zero", "file", 0),
    node("negative", "file", -3),
    node("ok", "file", 1),
  }
  local out = logic.assign(nodes)
  eq("only the node with a real line survives", #out, 1)
  eq("... and is numbered 00", out[1].label, "00")
  eq("nil node list is tolerated", #logic.assign(nil), 0)
end)

section("logic: the tree's own root is never numbered", function()
  local function nm(entries)
    return vim.tbl_map(function(e)
      return e.label .. ":" .. e.node.name
    end, entries)
  end
  local nodes = {
    node("root", "directory", 1, 1, true),
    node("a.lua", "file", 2, 2),
    node("b.lua", "file", 3, 2),
  }
  nodes[1].path = "E:\\proj\\Root\\"
  same(
    "root skipped (case/slash spelling differ)",
    nm(logic.assign(nodes, { skip_path = "e://proj/root", ignore_case = true })),
    { "00:a.lua", "01:b.lua" }
  )
  nodes[1].path = "/p/root"
  same(
    "root skipped, rest numbered from 0",
    nm(logic.assign(nodes, { skip_path = "/p/root/" })),
    { "00:a.lua", "01:b.lua" }
  )
  eq("without skip_path the root is numbered", #logic.assign(nodes), 3)
  eq(
    "case differs and ignore_case is off: not skipped",
    #logic.assign(nodes, { skip_path = "/P/ROOT" }),
    3
  )
  eq("path_key collapses slashes and trims the end", logic.path_key("C:\\a\\\\b/"), "C:/a/b")
  eq("path_key keeps a lone slash", logic.path_key("/"), "/")
end)

section("logic: assign caps at the label capacity", function()
  local nodes = {}
  for i = 1, 150 do
    nodes[i] = node("f" .. i, "file", i)
  end
  local out, truncated = logic.assign(nodes, { width = 2 })
  eq("two digits label 100 entries", #out, 100)
  eq("last label is 99", out[100].label, "99")
  eq("truncated is reported", truncated, true)
  local out3, truncated3 = logic.assign(nodes, { width = 3 })
  eq("three digits label all 150", #out3, 150)
  eq("not truncated at width 3", truncated3, false)
  local _, exact = logic.assign({ node("a", "file", 1) }, { width = 1 })
  eq("one entry at width 1 is not truncated", exact, false)
  local ten = {}
  for i = 1, 11 do
    ten[i] = node("g" .. i, "file", i)
  end
  local o1, t1 = logic.assign(ten, { width = 1 })
  eq("width 1 labels 10", #o1, 10)
  eq("width 1 truncates the 11th", t1, true)
end)

section("logic: find / matches_prefix", function()
  local out = logic.assign({ node("a", "file", 1), node("b", "file", 2) })
  eq("find 1 -> b", logic.find(out, 1).node.name, "b")
  eq("find 5 -> nil", logic.find(out, 5), nil)
  check("matches_prefix empty digits matches all", logic.matches_prefix("07", ""))
  check("matches_prefix '0' matches 07", logic.matches_prefix("07", "0"))
  check("matches_prefix '1' does not match 07", not logic.matches_prefix("07", "1"))
  check("matches_prefix full label matches", logic.matches_prefix("07", "07"))
end)

section("logic: input state machine", function()
  local i = logic.new_input()
  eq("new_input defaults to edit", i.mode, "edit")
  eq("new_input digits empty", i.digits, "")
  eq("new_input keeps a valid mode", logic.new_input("vsplit").mode, "vsplit")
  eq("new_input falls back for a bad mode", logic.new_input("preview").mode, "edit")

  local n, r = logic.feed(i, { kind = "digit", value = "4" }, 2)
  eq("first digit is incomplete", r.kind, "digit")
  eq("... and kept", n.digits, "4")
  eq("feed does not mutate its argument", i.digits, "")

  local n2, r2 = logic.feed(n, { kind = "digit", value = "2" }, 2)
  eq("second digit completes", r2.kind, "select")
  eq("... as number 42", r2.number, 42)
  eq("... and resets the digits", n2.digits, "")
  eq("... keeping the mode", n2.mode, "edit")

  local _, lead = logic.feed(
    logic.feed(i, { kind = "digit", value = "0" }, 2),
    { kind = "digit", value = "7" },
    2
  )
  eq("leading zero parses to 7", lead.number, 7)

  local m, rm = logic.feed(i, { kind = "mode", value = "split" }, 2)
  eq("mode key before a digit switches", rm.kind, "mode")
  eq("... to split", m.mode, "split")
  local m2 = logic.feed(m, { kind = "mode", value = "tab" }, 2)
  eq("modes can be switched again", m2.mode, "tab")

  local d1 = logic.feed(m, { kind = "digit", value = "3" }, 2)
  local locked, rl = logic.feed(d1, { kind = "mode", value = "vsplit" }, 2)
  eq("mode key after a digit is refused", rl.kind, "locked")
  eq("... mode unchanged", locked.mode, "split")
  eq("... digits unchanged", locked.digits, "3")

  local b, rb = logic.feed(d1, { kind = "backspace" }, 2)
  eq("backspace drops the digit", rb.kind, "backspace")
  eq("... leaving none", b.digits, "")
  local _, rb2 = logic.feed(b, { kind = "backspace" }, 2)
  eq("backspace on nothing is a no-op", rb2.kind, "none")
  local unlocked = logic.feed(b, { kind = "mode", value = "tab" }, 2)
  eq("after backspace the mode is selectable again", unlocked.mode, "tab")

  local _, bad = logic.feed(i, { kind = "digit", value = "x" }, 2)
  eq("a non-digit 'digit' is ignored", bad.kind, "none")
  local _, multi = logic.feed(i, { kind = "digit", value = "12" }, 2)
  eq("a two-character 'digit' is ignored", multi.kind, "none")
  local _, badmode = logic.feed(i, { kind = "mode", value = "preview" }, 2)
  eq("an unknown open mode is ignored", badmode.kind, "none")
  local _, unknown = logic.feed(i, { kind = "wat" }, 2)
  eq("an unknown event is ignored", unknown.kind, "none")

  -- width 1: a single digit completes; width 3: three
  local _, w1 = logic.feed(i, { kind = "digit", value = "9" }, 1)
  eq("width 1 completes on one digit", w1.number, 9)
  local s = logic.new_input()
  local sel
  for _, d in ipairs({ "1", "2", "3" }) do
    s, sel = logic.feed(s, { kind = "digit", value = d }, 3)
  end
  eq("width 3 completes on the third digit", sel.number, 123)
end)

section("logic: indicator text and position", function()
  eq(
    "text pads the typed digits",
    logic.indicator_text({ mode = "split", digits = "4" }, "files", 2),
    " split | files | 4_ "
  )
  eq(
    "text with nothing typed",
    logic.indicator_text({ mode = "edit", digits = "" }, "all", 2),
    " edit | all | __ "
  )
  eq(
    "text width 3",
    logic.indicator_text({ mode = "tab", digits = "12" }, "folders", 3),
    " tab | folders | 12_ "
  )

  same("default position", logic.normalize_position(nil), { "nvim", "top", "center" })
  local p, ok = logic.normalize_position({ "filetree", "bottom", "right" })
  same("a valid position is kept", p, { "filetree", "bottom", "right" })
  eq("... and reported ok", ok, true)
  local p2, ok2 = logic.normalize_position({ "filetree", "middle", "left" })
  same("an invalid slot falls back for that slot only", p2, { "filetree", "top", "left" })
  eq("... and is reported", ok2, false)
  local p3, ok3 = logic.normalize_position({ "nvim" })
  same("a short tuple is filled from the default", p3, { "nvim", "top", "center" })
  eq("... and reported", ok3, false)
  local _, ok4 = logic.normalize_position("top")
  eq("a non-table is reported", ok4, false)
  local _, ok5 = logic.normalize_position({ "nvim", "top", "left", "extra" })
  eq("a too-long tuple is reported", ok5, false)

  local row, col, w = logic.indicator_geometry({ "nvim", "top", "center" }, 100, 30, 20)
  same("top/center", { row, col, w }, { 0, 40, 20 })
  row, col, w = logic.indicator_geometry({ "nvim", "bottom", "right" }, 100, 30, 20)
  same("bottom/right", { row, col, w }, { 29, 80, 20 })
  row, col, w = logic.indicator_geometry({ "filetree", "top", "left" }, 40, 10, 12)
  same("top/left", { row, col, w }, { 0, 0, 12 })
  row, col, w = logic.indicator_geometry({ "filetree", "bottom", "center" }, 10, 5, 30)
  same("wider than the area: clamped, never off to the left", { row, col, w }, { 4, 0, 10 })
  row = logic.indicator_geometry({ "nvim", "bottom", "left" }, 80, 0, 5)
  eq("zero-height area does not go negative", row, 0)
end)

section("keys: silence_candidates", function()
  local all = keys_mod.silence_candidates({})
  local set = {}
  for _, k in ipairs(all) do
    set[k] = true
  end
  check(
    "covers letters, digits, punctuation",
    set["a"] and set["Z"] and set["5"] and set["#"] and set["~"]
  )
  check(
    "`<` `|` `\\` are spelled as key names",
    set["<lt>"] and set["<Bar>"] and set["<Bslash>"] and not set["<"] and not set["|"]
  )
  check("covers space, enter, tab", set["<Space>"] and set["<CR>"] and set["<Tab>"])
  check("covers Ctrl+letter", set["<C-a>"] and set["<C-w>"] and set["<C-z>"])
  check("Esc is never silenced", not set["<Esc>"])
  check("<C-i> / <C-m> fall out: same bytes as Tab / CR", not set["<C-i>"] and not set["<C-m>"])

  local taken = keys_mod.silence_candidates({ "s", "<C-d>", "<c-U>", "<Esc>" })
  local tset = {}
  for _, k in ipairs(taken) do
    tset[k] = true
  end
  check("a taken key is not silenced", not tset["s"])
  check(
    "a taken Ctrl key is not silenced, whatever the case it was spelled in",
    not tset["<C-d>"] and not tset["<C-u>"]
  )
  check("untaken neighbours still are", tset["a"] and tset["<C-a>"])
  eq("no duplicates by bytes", #taken, #vim.tbl_keys(tset))
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. The order get_visible_nodes hands over, per adapter
-- ═══════════════════════════════════════════════════════════════════════════════

---@param entries FiletreeQuickpickEntry[]
---@return string[]
local function names(entries)
  return vim.tbl_map(function(e)
    return e.label .. ":" .. e.node.name
  end, entries)
end

section("adapter order: neo-tree shape (depth-first walk, expanded folders inline)", function()
  -- What adapter/neotree.lua emits: a depth-first walk with the root (depth 0)
  -- left out, line numbers counted as it goes.
  local nodes = {
    node("src", "directory", 1, 1, true),
    node("init.lua", "file", 2, 2),
    node("util", "directory", 3, 2, true),
    node("path.lua", "file", 4, 3),
    node("README.md", "file", 5, 1),
    node("tests", "directory", 6, 1, false),
  }
  same(
    "numbers follow the walk",
    names(logic.assign(nodes)),
    { "00:src", "01:init.lua", "02:util", "03:path.lua", "04:README.md", "05:tests" }
  )
  same(
    "files only",
    names(logic.assign(nodes, { content = "files" })),
    { "00:init.lua", "01:path.lua", "02:README.md" }
  )
  same(
    "folders only",
    names(logic.assign(nodes, { content = "folders" })),
    { "00:src", "01:util", "02:tests" }
  )
  -- expanding `tests` inserts its children right after it and renumbers
  local expanded = vim.deepcopy(nodes)
  expanded[6].is_expanded = true
  expanded[7] = node("a_spec.lua", "file", 7, 2)
  same("after expanding the last folder its children follow it", names(logic.assign(expanded)), {
    "00:src",
    "01:init.lua",
    "02:util",
    "03:path.lua",
    "04:README.md",
    "05:tests",
    "06:a_spec.lua",
  })
end)

section(
  "adapter order: nvim-tree shape (line map sorted by line, a hole for the root label)",
  function()
    -- adapter/nvimtree.lua builds from `pairs()` over a line map, then sorts by
    -- line; the root label occupies line 1, so the first node sits on line 2.
    local nodes = {
      node("lib", "directory", 2, 1, true),
      node("a.lua", "file", 3, 2),
      node("b.lua", "file", 4, 2),
      node("z.txt", "file", 5, 1),
    }
    same(
      "the root-label hole does not shift the numbers",
      names(logic.assign(nodes)),
      { "00:lib", "01:a.lua", "02:b.lua", "03:z.txt" }
    )
    eq("the first entry keeps its real line", logic.assign(nodes)[1].line, 2)
  end
)

local function reset_buffers()
  vim.cmd("silent! %bwipeout!")
  vim.cmd("silent! only")
end

section("adapter order: mini.files (real adapter, mini.files stubbed)", function()
  reset_buffers()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "docs", "a.lua", "b.lua" })
  vim.api.nvim_set_current_buf(buf)
  local win = vim.api.nvim_get_current_win()
  local entries = {
    { fs_type = "directory", name = "docs", path = "/m/docs" },
    { fs_type = "file", name = "a.lua", path = "/m/a.lua" },
    { fs_type = "file", name = "b.lua", path = "/m/b.lua" },
  }
  local saved = package.loaded["mini.files"]
  package.loaded["mini.files"] = {
    get_explorer_state = function()
      return { anchor = "/m", windows = { { win_id = win, path = "/m" } } }
    end,
    get_fs_entry = function(_, line)
      return entries[line]
    end,
    open = function() end,
    close = function() end,
  }
  package.loaded["filetree.adapter.mini_files"] = nil
  local ok, err = pcall(function()
    local mf = require("filetree.adapter.mini_files")
    local out = logic.assign(mf.get_visible_nodes())
    same(
      "one flat column, numbered top to bottom",
      names(out),
      { "00:docs", "01:a.lua", "02:b.lua" }
    )
    same(
      "files only",
      names(logic.assign(mf.get_visible_nodes(), { content = "files" })),
      { "00:a.lua", "01:b.lua" }
    )
    local d = logic.find(out, 0)
    eq("a folder has no expansion state on this backend", d.node.is_expanded, nil)
  end)
  package.loaded["mini.files"] = saved
  package.loaded["filetree.adapter.mini_files"] = nil
  check("mini_files section ran", ok, tostring(err))
end)

section(
  "adapter order: oil (real adapter, oil stubbed; ids stripped by oil's own parser)",
  function()
    reset_buffers()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "oil"
    -- oil prepends an internal id to every real line; the adapter must go
    -- through `get_entry_on_line`, so the numbering sees names, not raw text.
    vim.api.nvim_buf_set_lines(
      buf,
      0,
      -1,
      false,
      { "/002 beta.lua", "/001 alpha", "/003 gamma.lua" }
    )
    vim.api.nvim_set_current_buf(buf)
    local rows = {
      { name = "beta.lua", type = "file" },
      { name = "alpha", type = "directory" },
      { name = "gamma.lua", type = "file" },
    }
    local saved = package.loaded["oil"]
    package.loaded["oil"] = {
      get_current_dir = function()
        return "/o/"
      end,
      get_entry_on_line = function(_, line)
        return rows[line]
      end,
      get_cursor_entry = function()
        return rows[1]
      end,
    }
    package.loaded["filetree.adapter.oil"] = nil
    local ok, err = pcall(function()
      local oil = require("filetree.adapter.oil")
      local out = logic.assign(oil.get_visible_nodes())
      same(
        "rendered order, whatever the oil ids say",
        names(out),
        { "00:beta.lua", "01:alpha", "02:gamma.lua" }
      )
      same(
        "folders only",
        names(logic.assign(oil.get_visible_nodes(), { content = "folders" })),
        { "00:alpha" }
      )
    end)
    package.loaded["oil"] = saved
    package.loaded["filetree.adapter.oil"] = nil
    check("oil section ran", ok, tostring(err))
  end
)

section(
  "adapter order: netrw (real adapter, a real buffer; banner lines are not entries)",
  function()
    reset_buffers()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "netrw"
    vim.b[buf].netrw_curdir = "/n"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '" ============================',
      '" Netrw Directory Listing',
      '" ============================',
      "",
      "../",
      "sub/",
      "main.lua",
      "notes.md",
    })
    vim.api.nvim_set_current_buf(buf)
    package.loaded["filetree.adapter.netrw"] = nil
    local netrw = require("filetree.adapter.netrw")
    local out = logic.assign(netrw.get_visible_nodes())
    same(
      "banner skipped, numbers start at the first real entry",
      names(out),
      { "00:..", "01:sub", "02:main.lua", "03:notes.md" }
    )
    eq("the first entry's line is its real buffer line", out[1].line, 5)
    same(
      "files only",
      names(logic.assign(netrw.get_visible_nodes(), { content = "files" })),
      { "00:main.lua", "01:notes.md" }
    )
    package.loaded["filetree.adapter.netrw"] = nil
  end
)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Lifecycle against a fake tree
-- ═══════════════════════════════════════════════════════════════════════════════

local qp = require("filetree.features.nav.quickpick")

---@param keys string
local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
end

---Count of armed libuv timers; only compared against a baseline taken in the
---same stretch, so unrelated timers cancel out.
local function active_timers()
  local n = 0
  uv.walk(function(h)
    if h:get_type() == "timer" and h:is_active() then n = n + 1 end
  end)
  return n
end

local function floats()
  local n = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then n = n + 1 end
  end
  return n
end

local function group_exists(name)
  return pcall(vim.api.nvim_get_autocmds, { group = name })
    and #vim.api.nvim_get_autocmds({ group = name }) > 0
end

---@class FakeTree
---@field buf integer
---@field win integer?
---@field rows table
---@field expanded table<string, boolean>
---@field opened { path: string, mode: string, win: integer }[]
---@field reveals table[]
---@field adapter FiletreeAdapter
---@field renders integer

---Build a fake tree adapter that owns a real buffer and window and redraws
---it the way a tree does: `expand_node` rewrites the buffer lines.
---@param rows table  nested { name, dir?, children? }
---@param opts? { height?: integer, open_delay?: integer, on_render?: boolean }
---@return FakeTree
local function make_tree(rows, opts)
  opts = opts or {}
  local T = { rows = rows, expanded = {}, opened = {}, reveals = {}, renders = 0, listeners = {} }

  T.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[T.buf].filetype = "faketree"
  vim.bo[T.buf].bufhidden = "hide"

  local function walk(list, depth, prefix, out)
    for _, r in ipairs(list) do
      local path = prefix .. "/" .. r.name
      out[#out + 1] = { row = r, path = path, depth = depth }
      if r.children and T.expanded[path] then walk(r.children, depth + 1, path, out) end
    end
  end

  function T.flat()
    local out = {}
    walk(T.rows, 1, "/fake", out)
    return out
  end

  function T.redraw()
    local lines = {}
    for _, f in ipairs(T.flat()) do
      lines[#lines + 1] = ("%s%s%s"):format(
        ("  "):rep(f.depth - 1),
        f.row.children and (T.expanded[f.path] and "v " or "> ") or "- ",
        f.row.name
      )
    end
    vim.bo[T.buf].modifiable = true
    vim.api.nvim_buf_set_lines(T.buf, 0, -1, false, lines)
    vim.bo[T.buf].modifiable = false
    T.renders = T.renders + 1
    for _, cb in ipairs(T.listeners) do
      cb(T.buf)
    end
  end

  function T.open_window()
    if T.win and vim.api.nvim_win_is_valid(T.win) then return end
    vim.cmd("topleft vsplit")
    T.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(T.win, T.buf)
    vim.api.nvim_win_set_width(T.win, 30)
    if opts.height then vim.api.nvim_win_set_height(T.win, opts.height) end
    T.redraw()
  end

  local adapter = {
    name = "fake",
    filetypes = { "faketree" },
    is_available = function()
      return true
    end,
    is_open = function()
      if T.win and vim.api.nvim_win_is_valid(T.win) then return true, T.buf end
      return false, nil
    end,
    get_winid = function()
      if T.win and vim.api.nvim_win_is_valid(T.win) then return T.win end
      return nil
    end,
    get_bufnr = function()
      return T.buf
    end,
    get_visible_nodes = function(filter, _)
      local out = {}
      for i, f in ipairs(T.flat()) do
        local ntype = f.row.children and "directory" or "file"
        if
          filter == nil
          or filter == "all"
          or (filter == "files" and ntype == "file")
          or (filter == "folders" and ntype == "directory")
        then
          out[#out + 1] = {
            id = f.path,
            name = f.row.name,
            path = f.path,
            type = ntype,
            depth = f.depth,
            line_number = i,
            is_expanded = ntype == "directory" and (T.expanded[f.path] == true) or nil,
          }
        end
      end
      return out
    end,
    expand_node = function(n)
      T.expanded[n.path] = true
      T.redraw()
      return true
    end,
    collapse_node = function(n)
      T.expanded[n.path] = nil
      T.redraw()
      return true
    end,
    open_file = function(path, mode)
      T.opened[#T.opened + 1] = { path = path, mode = mode, win = vim.api.nvim_get_current_win() }
      return true
    end,
    open_reveal = function(path, levels, root)
      T.reveals[#T.reveals + 1] = { path = path, levels = levels, root = root }
      local function show()
        -- a deferred open can outlive its section; the world it belonged to is gone
        if not vim.api.nvim_buf_is_valid(T.buf) then return end
        T.open_window()
        vim.api.nvim_set_current_win(T.win)
      end
      if opts.open_delay then
        vim.defer_fn(show, opts.open_delay)
      else
        show()
      end
      return true
    end,
    open_cwd = function()
      T.reveals[#T.reveals + 1] = { cwd = true }
      if opts.open_delay then
        vim.defer_fn(T.open_window, opts.open_delay)
      else
        T.open_window()
      end
      return true
    end,
  }
  if opts.on_render then
    adapter.on_render = function(cb)
      T.listeners[#T.listeners + 1] = cb
      return function()
        T.listeners = vim.tbl_filter(function(x)
          return x ~= cb
        end, T.listeners)
      end
    end
  end
  T.adapter = adapter
  return T
end

local TREE_ROWS = function()
  return {
    {
      name = "docs",
      children = { { name = "guide.md" }, { name = "deep", children = { { name = "x.txt" } } } },
    },
    { name = "a.lua" },
    { name = "b.lua" },
    { name = "src", children = { { name = "main.lua" } } },
    { name = "c.lua" },
  }
end

local EDITOR_FILE = "/fake/proj/editor.lua"

---Fresh world: one editor window (a named buffer) and, when `open`, the tree
---on its left; the feature is set up against the fake adapter.
---@param cfg? table
---@param tree_opts? table
---@param open? boolean  Default true.
---@return FakeTree T, integer editor_win
local function world(cfg, tree_opts, open)
  qp.teardown()
  -- Shrinking a window that spans the whole height (the scroll and resize
  -- sections do) gives the rows to 'cmdheight' instead; undo that per world,
  -- before the windows are collapsed so the single survivor gets the rows.
  vim.o.cmdheight = 1
  reset_buffers()
  pcall(vim.cmd, "resize 1000") -- the survivor takes every row again
  for _, lhs in ipairs({ "<leader>;", "<leader>:" }) do
    pcall(vim.keymap.del, "n", lhs)
  end
  local editor = vim.api.nvim_get_current_win()
  local eb = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(eb, EDITOR_FILE)
  vim.api.nvim_win_set_buf(editor, eb)
  local T = make_tree(TREE_ROWS(), tree_opts)
  qp.setup(vim.tbl_extend("force", { enabled = true, timeout_ms = 0 }, cfg or {}), T.adapter)
  if open ~= false then
    T.open_window()
    vim.api.nvim_set_current_win(editor)
  end
  return T, editor
end

local function ns_marks(T)
  local ns = vim.api.nvim_get_namespaces()["filetree_quickpick"]
  if not ns then return {} end
  return vim.api.nvim_buf_get_extmarks(T.buf, ns, 0, -1, { details = true })
end

---Labels currently drawn, by 1-based line.
local function drawn(T)
  local out = {}
  for _, m in ipairs(ns_marks(T)) do
    local text = ""
    for _, chunk in ipairs(m[4].virt_text) do
      text = text .. chunk[1]
    end
    out[m[2] + 1] = text
  end
  return out
end

section("lifecycle: start numbers the visible entries and takes the keys", function()
  local T, editor = world()
  local timers0 = active_timers()
  eq("start succeeds", qp.start(), true)
  check("mode is active", qp.is_active())
  local snap = qp.snapshot()
  eq("focus moved to the tree window", vim.api.nvim_get_current_win(), T.win)
  eq("snapshot: edit by default", snap.mode, "edit")
  eq("snapshot: all content", snap.content, "all")
  eq("snapshot: five entries", snap.count, 5)
  local d = drawn(T)
  eq("line 1 is 00", d[1], "00")
  eq("line 5 is 04", d[5], "04")
  eq("one extmark per entry", #ns_marks(T), 5)
  eq("the badge float is up", floats(), 1)
  check("autocmd group exists", group_exists("filetree_quickpick"))
  local map = vim.api.nvim_buf_call(T.buf, function()
    return vim.fn.maparg("5", "n", false, true)
  end)
  check("digits are mapped buffer-locally", map.buffer == 1 and map.nowait == 1)
  qp.cancel()
  check("cancel ends the mode", not qp.is_active())
  eq("cancel returns to the origin window", vim.api.nvim_get_current_win(), editor)
  eq("no extmarks left", #ns_marks(T), 0)
  eq("badge float closed", floats(), 0)
  check("autocmd group gone", not group_exists("filetree_quickpick"))
  eq("no timer left armed", active_timers(), timers0)
  local map2 = vim.api.nvim_buf_call(T.buf, function()
    return vim.fn.maparg("5", "n", false, true)
  end)
  check("the digit key is unmapped again", next(map2) == nil)
end)

section("lifecycle: a folder number never opens anything", function()
  local T = world()
  qp.start()
  press("00") -- docs is a folder
  eq("nothing was opened", #T.opened, 0)
  eq("the folder was expanded instead", T.expanded["/fake/docs"], true)
  check("and the mode is still running", qp.is_active())
  qp.cancel()
end)

section("lifecycle: files open in an editor window with the chosen mode", function()
  local T, editor = world()
  qp.start()
  -- entries: 00 docs, 01 a.lua, 02 b.lua, 03 src, 04 c.lua
  press("01")
  eq("exactly one open", #T.opened, 1)
  eq("the right path", T.opened[1].path, "/fake/a.lua")
  eq("edit by default", T.opened[1].mode, "edit")
  eq("opened from the editor window, not the tree", T.opened[1].win, editor)
  check("mode ended", not qp.is_active())

  T.opened = {}
  qp.start()
  press("s02")
  eq("s prefix -> split", T.opened[1].mode, "split")
  eq("... b.lua", T.opened[1].path, "/fake/b.lua")

  T.opened = {}
  qp.start()
  press("v04")
  eq("v prefix -> vsplit", T.opened[1].mode, "vsplit")
  eq("... c.lua", T.opened[1].path, "/fake/c.lua")

  T.opened = {}
  qp.start()
  press("t01")
  eq("t prefix -> tab", T.opened[1].mode, "tab")

  T.opened = {}
  qp.start()
  press("s")
  eq("the badge follows the prefix", qp.snapshot().mode, "split")
  press("v")
  eq("prefixes can be changed before a digit", qp.snapshot().mode, "vsplit")
  press("e")
  eq("e returns to edit", qp.snapshot().mode, "edit")
  press("t")
  press("0")
  eq("a digit is typed", qp.snapshot().digits, "0")
  press("s")
  eq("a prefix after a digit does not change the mode", qp.snapshot().mode, "tab")
  eq("... nor the digits", qp.snapshot().digits, "0")
  press("<BS>")
  eq("backspace drops the digit", qp.snapshot().digits, "")
  press("s")
  eq("... and unlocks the prefix", qp.snapshot().mode, "split")
  qp.cancel()
end)

section("lifecycle: opening without an editor window makes one", function()
  local T = world()
  vim.cmd("silent! only") -- tree window survives only if it is the one kept; rebuild instead
  T.win = nil
  T.open_window()
  vim.cmd("wincmd o") -- the tree is now the only window
  T.win = vim.api.nvim_get_current_win()
  local wins_before = #vim.api.nvim_list_wins()
  qp.start()
  press("01")
  eq("one open", #T.opened, 1)
  check("a window other than the tree took the open", T.opened[1].win ~= T.win)
  check("a window was created for it", #vim.api.nvim_list_wins() > wins_before)
end)

section("lifecycle: a folder number expands, then collapses; labels are redrawn", function()
  local T = world({}, { on_render = true })
  qp.start()
  press("00") -- docs
  eq("docs is expanded", T.expanded["/fake/docs"], true)
  check("mode still running after a folder", qp.is_active())
  -- let the scheduled render run
  vim.wait(300, function()
    return qp.snapshot().count == 7
  end)
  eq("the children are numbered now", qp.snapshot().count, 7)
  eq("line 2 (guide.md) carries 01", drawn(T)[2], "01")
  eq("line 7 carries 06", drawn(T)[7], "06")

  press("03") -- "deep" inside docs? entries: 00 docs 01 guide 02 deep 03 a.lua
  eq(
    "number 03 is a.lua after the expansion -> opened",
    T.opened[1] and T.opened[1].path,
    "/fake/a.lua"
  )
  check("mode ended on the file", not qp.is_active())

  T.opened = {}
  qp.start()
  press("00") -- docs again: it is expanded, so this collapses it
  eq("docs collapsed again", T.expanded["/fake/docs"], nil)
  vim.wait(300, function()
    return qp.snapshot() and qp.snapshot().count == 5
  end)
  eq("back to five entries", qp.snapshot().count, 5)
  qp.cancel()
end)

section("lifecycle: nested folder, wrong number, folder-only expand reachable", function()
  local T = world()
  qp.start()
  press("00")
  vim.wait(300, function()
    return qp.snapshot().count == 7
  end)
  press("02") -- deep
  eq("deep expanded", T.expanded["/fake/docs/deep"], true)
  vim.wait(300, function()
    return qp.snapshot().count == 8
  end)
  eq("eight entries", qp.snapshot().count, 8)
  eq("the last one is numbered 07", drawn(T)[8], "07")
  qp.cancel()
end)

section("lifecycle: an unknown number keeps the mode and resets the digits", function()
  local T = world()
  qp.start()
  press("99")
  check("still active", qp.is_active())
  eq("digits reset", qp.snapshot().digits, "")
  eq("nothing opened", #T.opened, 0)
  press("4")
  eq("a digit is typed afterwards", qp.snapshot().digits, "4")
  qp.cancel()
end)

section("lifecycle: typed digits narrow the labels", function()
  local T = world()
  -- grow the tree to > 10 entries so labels 00..09 and 10..11 differ in first digit
  T.rows = {}
  for i = 1, 12 do
    T.rows[i] = { name = ("f%02d.lua"):format(i) }
  end
  T.redraw()
  qp.start()
  eq("twelve labels", #ns_marks(T), 12)
  press("1")
  eq("only labels starting with 1 stay", #ns_marks(T), 2)
  local first = ns_marks(T)[1][4].virt_text
  eq("the typed digit is highlighted separately", first[1][1], "1")
  eq("... in the typed group", first[1][2], "FiletreeQuickpickTyped")
  eq("... and the rest in the number group", first[2][2], "FiletreeQuickpickNumber")
  press("<BS>")
  eq("backspace brings them all back", #ns_marks(T), 12)
  qp.cancel()
end)

section("lifecycle: content cycle (all -> files -> folders -> all)", function()
  local T = world()
  qp.start()
  press("c")
  eq("files", qp.snapshot().content, "files")
  eq("files only: three file entries... a, b, c", qp.snapshot().count, 3)
  eq("labelled from 00", drawn(T)[2], "00")
  press("c")
  eq("folders", qp.snapshot().content, "folders")
  eq("two folders", qp.snapshot().count, 2)
  press("c")
  eq("all again", qp.snapshot().content, "all")
  eq("five entries", qp.snapshot().count, 5)
  press("1")
  press("c")
  eq("cycling drops a half-typed number", qp.snapshot().digits, "")
  eq("(files again after the drop)", qp.snapshot().content, "files")
  press("01") -- files: 00 a, 01 b, 02 c
  eq("the number refers to the current content kind", T.opened[1].path, "/fake/b.lua")
  qp.cancel()
end)

section("lifecycle: content = folders at start; a folder number still toggles", function()
  local T = world({ content = "folders" })
  qp.start()
  eq("two entries", qp.snapshot().count, 2)
  press("01") -- src
  eq("src expanded", T.expanded["/fake/src"], true)
  qp.cancel()
end)

section("lifecycle: Esc and Ctrl-C leave; keys are restored exactly", function()
  local T, editor = world()
  -- the tree plugin's own buffer-local mappings on keys the mode also wants:
  -- a Lua callback with desc/nowait/silent, and a plain rhs one.
  local hits = {}
  vim.api.nvim_buf_set_keymap(T.buf, "n", "s", "", {
    callback = function()
      hits[#hits + 1] = "s"
    end,
    desc = "tree split",
    nowait = true,
    silent = true,
  })
  vim.api.nvim_buf_set_keymap(T.buf, "n", "x", "<Cmd>let g:qp_x = 1<CR>", { noremap = true })
  vim.api.nvim_buf_set_keymap(T.buf, "n", "<CR>", "", {
    callback = function()
      hits[#hits + 1] = "cr"
    end,
    desc = "tree open",
  })
  vim.api.nvim_buf_set_keymap(T.buf, "n", "<Esc>", "", {
    callback = function()
      hits[#hits + 1] = "esc"
    end,
    desc = "tree esc",
  })
  vim.g.qp_x = nil
  local global_hits = 0
  vim.keymap.set("n", "Q", function()
    global_hits = global_hits + 1
  end, { desc = "global Q" })

  qp.start()
  press("s")
  eq("in the mode, s is the open mode, not the tree's action", #hits, 0)
  eq("... it switched the mode", qp.snapshot().mode, "split")
  press("x")
  eq("in the mode, a silenced key runs nothing", vim.g.qp_x, nil)
  press("<CR>")
  eq("... nor does Enter", #hits, 0)
  press("Q")
  eq("... nor a global mapping", global_hits, 0)
  check("... and the mode is still up", qp.is_active())

  press("<Esc>")
  check("Esc leaves", not qp.is_active())
  eq("the Esc did not reach the tree's own Esc mapping", #hits, 0)
  eq("back in the origin window", vim.api.nvim_get_current_win(), editor)

  -- everything the tree had is back, byte for byte
  vim.api.nvim_set_current_win(T.win)
  press("s")
  eq("the tree's own `s` works again", hits[#hits], "s")
  press("x")
  eq("the tree's own `x` works again", vim.g.qp_x, 1)
  press("<CR>")
  eq("the tree's own Enter works again", hits[#hits], "cr")
  press("<Esc>")
  eq("the tree's own Esc works again", hits[#hits], "esc")
  local m = vim.api.nvim_buf_call(T.buf, function()
    return vim.fn.maparg("s", "n", false, true)
  end)
  eq("the restored mapping keeps its desc", m.desc, "tree split")
  eq("... its nowait", m.nowait, 1)
  eq("... its silent", m.silent, 1)
  local mx = vim.api.nvim_buf_call(T.buf, function()
    return vim.fn.maparg("x", "n", false, true)
  end)
  eq("a plain rhs mapping returns as it was", mx.rhs, "<Cmd>let g:qp_x = 1<CR>")
  eq("... noremap", mx.noremap, 1)
  press("Q")
  eq("the global mapping was never touched", global_hits, 1)
  local anyk = vim.api.nvim_buf_call(T.buf, function()
    return vim.fn.maparg("a", "n", false, true)
  end)
  check("a key that only we silenced is unmapped again", next(anyk) == nil)

  vim.api.nvim_set_current_win(editor)
  qp.start()
  press("<C-c>")
  check("Ctrl-C leaves too", not qp.is_active())
  pcall(vim.keymap.del, "n", "Q")
end)

section("lifecycle: silence_nvim_mappings = false leaves other keys alone", function()
  local T = world({ silence_nvim_mappings = false })
  local global_hits = 0
  vim.keymap.set("n", "Q", function()
    global_hits = global_hits + 1
  end)
  qp.start()
  press("Q")
  eq("a global mapping still fires", global_hits, 1)
  local m = vim.api.nvim_buf_call(T.buf, function()
    return vim.fn.maparg("a", "n", false, true)
  end)
  check("no <Nop> was put on an unrelated key", next(m) == nil)
  press("1")
  eq("the mode's own keys still work", qp.snapshot().digits, "1")
  qp.cancel()
  pcall(vim.keymap.del, "n", "Q")
end)

section("lifecycle: idle timeout ends the mode, a key restarts it", function()
  local T = world({ timeout_ms = 700 })
  local timers0 = active_timers()
  qp.start()
  check("active at start", qp.is_active())
  check("a timer is armed", active_timers() > timers0)
  vim.wait(400, function()
    return false
  end)
  press("1") -- restarts the countdown
  vim.wait(450, function()
    return false
  end)
  check("still active 850ms in: the key restarted the countdown", qp.is_active())
  local ok = vim.wait(3000, function()
    return not qp.is_active()
  end, 20)
  check("the timeout ended the mode", ok)
  eq("extmarks cleared by the timeout", #ns_marks(T), 0)
  eq("badge closed by the timeout", floats(), 0)
  check("autocmds gone after the timeout", not group_exists("filetree_quickpick"))
  eq("no timer left armed after the timeout", active_timers(), timers0)
  local m = vim.api.nvim_buf_call(T.buf, function()
    return vim.fn.maparg("1", "n", false, true)
  end)
  check("keys restored after the timeout", next(m) == nil)
end)

section("lifecycle: timeout_ms = 0 never times out and arms no timer", function()
  world({ timeout_ms = 0 })
  local timers0 = active_timers()
  qp.start()
  eq("no timer armed", active_timers(), timers0)
  vim.wait(200, function()
    return false
  end)
  check("still active", qp.is_active())
  qp.cancel()
end)

section("lifecycle: one mode at a time", function()
  local T, editor = world()
  vim.api.nvim_buf_set_keymap(
    T.buf,
    "n",
    "s",
    "",
    { callback = function() end, desc = "tree split" }
  )
  qp.start()
  vim.api.nvim_set_current_win(editor) -- (WinLeave ends it; start again anyway)
  qp.start()
  qp.start()
  check("one mode is active", qp.is_active())
  eq("one set of labels, never doubled", #ns_marks(T), 5)
  eq("one badge", floats(), 1)
  qp.cancel()
  local m = vim.api.nvim_buf_call(T.buf, function()
    return vim.fn.maparg("s", "n", false, true)
  end)
  eq("the tree's mapping survived three starts", m.desc, "tree split")
  eq("nothing left", floats() + #ns_marks(T), 0)
end)

section(
  "lifecycle: leaving the tree window / closing it / wiping its buffer ends the mode",
  function()
    local T, editor = world()
    qp.start()
    vim.api.nvim_set_current_win(editor)
    check("focus moving away ends the mode", not qp.is_active())
    eq("labels cleared", #ns_marks(T), 0)
    eq("badge closed", floats(), 0)

    qp.start()
    vim.api.nvim_win_close(T.win, true)
    check("closing the tree window ends the mode", not qp.is_active())
    eq("badge closed with it", floats(), 0)
    check("autocmds gone", not group_exists("filetree_quickpick"))

    local T2 = world()
    qp.start()
    vim.api.nvim_buf_delete(T2.buf, { force = true })
    check("wiping the tree buffer ends the mode", not qp.is_active())
    eq("badge closed", floats(), 0)
  end
)

section("lifecycle: renumbers on scroll", function()
  local T, editor = world({}, { height = 8 })
  T.rows = {}
  for i = 1, 40 do
    T.rows[i] = { name = ("f%02d.lua"):format(i) }
  end
  T.redraw()
  vim.api.nvim_set_current_win(editor)
  qp.start()
  local info = vim.fn.getwininfo(T.win)[1]
  local visible = info.botline - info.topline + 1
  eq("only the visible lines are numbered", qp.snapshot().count, visible)
  eq("first visible line is 00", drawn(T)[info.topline], "00")
  press("<C-d>")
  local after = vim.fn.getwininfo(T.win)[1]
  check("the window scrolled", after.topline > info.topline)
  vim.wait(300, function()
    return drawn(T)[after.topline] == "00"
  end)
  eq("numbering restarted at the new top line", drawn(T)[after.topline], "00")
  eq("the old top line carries no label any more", drawn(T)[info.topline], nil)
  eq("count follows the viewport", qp.snapshot().count, after.botline - after.topline + 1)
  press("<C-u>")
  press("j")
  press("k")
  check("line keys work too and the mode stays", qp.is_active())
  qp.cancel()
end)

section("lifecycle: resize re-places the badge and renumbers", function()
  local T = world({ indicator_position = { "filetree", "bottom", "right" } }, { height = 10 })
  vim.api.nvim_set_current_win(T.win)
  qp.start()
  local ind
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then ind = w end
  end
  local c = vim.api.nvim_win_get_config(ind)
  eq("badge is relative to the tree window", c.relative, "win")
  eq("... that window", c.win, T.win)
  eq("... on its last row", c.row, vim.api.nvim_win_get_height(T.win) - 1)
  vim.api.nvim_win_set_height(T.win, 4)
  vim.api.nvim_exec_autocmds("WinResized", {})
  vim.wait(300, function()
    return vim.api.nvim_win_get_config(ind).row == 3
  end)
  eq("the badge followed the new height", vim.api.nvim_win_get_config(ind).row, 3)
  eq("count follows the new height", qp.snapshot().count, 4)
  qp.cancel()
end)

section("lifecycle: badge text and position", function()
  world({ indicator_position = { "nvim", "bottom", "left" } })
  qp.start()
  local ind
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then ind = w end
  end
  local text = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(ind), 0, -1, false)[1]
  eq("badge shows mode, content, empty number", text, " edit | all | __ ")
  eq("editor-relative", vim.api.nvim_win_get_config(ind).relative, "editor")
  eq("left column", vim.api.nvim_win_get_config(ind).col, 0)
  press("v")
  press("c")
  press("3")
  text = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(ind), 0, -1, false)[1]
  eq("badge follows mode, content and digits", text, " vsplit | files | 3_ ")
  check("the badge is not focusable", vim.api.nvim_win_get_config(ind).focusable == false)
  qp.cancel()

  world({ indicator = false })
  qp.start()
  eq("indicator = false opens no float", floats(), 0)
  qp.cancel()
end)

section("lifecycle: width and open_mode and label_pos options", function()
  local T = world({ width = 1, open_mode = "vsplit", label_pos = "right_align" })
  qp.start()
  eq("start mode comes from open_mode", qp.snapshot().mode, "vsplit")
  eq("one-digit labels", drawn(T)[1], "0")
  eq("label_pos is applied", ns_marks(T)[1][4].virt_text_pos, "right_align")
  press("1")
  eq("one digit completes (a.lua)", T.opened[1].path, "/fake/a.lua")
  eq("... in the configured mode", T.opened[1].mode, "vsplit")

  local T3 = world({ width = 3 })
  qp.start()
  eq("three-digit labels", drawn(T3)[1], "000")
  press("00")
  check("two digits do not complete a width-3 number", qp.is_active())
  press("1")
  eq("the third does", T3.opened[1].path, "/fake/a.lua")
end)

section("lifecycle: remapped keys, disabled keys", function()
  world({ keys = { cancel = "q", cycle = false, split = { "S", "<C-s>" }, edit = false } })
  qp.start()
  press("c")
  eq("a disabled key does nothing (c is silenced, not the cycle)", qp.snapshot().content, "all")
  press("S")
  eq("a remapped mode key works", qp.snapshot().mode, "split")
  press("<C-s>")
  eq("... and so does its second spelling", qp.snapshot().mode, "split")
  press("<Esc>")
  check("<Esc> is not a cancel key any more (and not silenced): the mode stays up", qp.is_active())
  press("q")
  check("the remapped cancel key leaves", not qp.is_active())
end)

section("lifecycle: an adapter's own re-render renumbers (on_render + buffer watcher)", function()
  local T = world({}, { on_render = true })
  qp.start()
  T.rows[#T.rows + 1] = { name = "z.lua" }
  T.redraw() -- the tree changed under us (a file appeared)
  vim.wait(300, function()
    return qp.snapshot().count == 6
  end)
  eq("the new entry is numbered", qp.snapshot().count, 6)
  eq("on its line", drawn(T)[6], "05")
  qp.cancel()
  eq("the on_render subscription is dropped", #T.listeners, 0)
end)

section("lifecycle: nothing to number", function()
  local T = world()
  T.rows = {}
  T.redraw()
  eq("start refuses an empty tree", qp.start(), false)
  check(
    "and leaves nothing behind",
    not qp.is_active() and floats() == 0 and not group_exists("filetree_quickpick")
  )
end)

section("lifecycle: adapters that cannot expand folders say so", function()
  local T = world()
  T.adapter.expand_node = function()
    return false
  end
  qp.start()
  press("00")
  check("mode survives the refusal", qp.is_active())
  eq("nothing opened", #T.opened, 0)
  qp.cancel()
end)

section("lifecycle: boot of a closed tree", function()
  local T, editor = world({}, { open_delay = 120 }, false)
  local timers0 = active_timers()
  eq("start accepts the request", qp.start(), true)
  eq("the tree was asked to reveal the current file", T.reveals[1].path, EDITOR_FILE)
  eq("... one level (the file's own folder)", T.reveals[1].levels, 0)
  check("the mode waits for the tree", not qp.is_active())
  local ok = vim.wait(3000, function()
    return qp.is_active()
  end, 20)
  check("the mode starts once the tree has rendered", ok)
  eq("with the tree focused", vim.api.nvim_get_current_win(), T.win)
  qp.cancel()
  eq("back in the editor", vim.api.nvim_get_current_win(), editor)
  check("the boot poll left no timer", active_timers() <= timers0)

  -- levels and cwd
  T.reveals = {}
  vim.api.nvim_win_close(T.win, true)
  qp.start({ parent_levels = 2 })
  eq("a count roots the tree that many folders up", T.reveals[1].levels, 2)
  vim.wait(3000, function()
    return qp.is_active()
  end, 20)
  qp.cancel()

  T.reveals = {}
  vim.api.nvim_win_close(T.win, true)
  qp.start({ cwd = true })
  eq("cwd mode roots at the cwd", T.reveals[1].root, uv.cwd())
  eq("... still revealing the file", T.reveals[1].path, EDITOR_FILE)
  vim.wait(3000, function()
    return qp.is_active()
  end, 20)
  qp.cancel()

  -- an already-open tree is numbered as it is: no reveal
  T.reveals = {}
  T.open_window()
  vim.api.nvim_set_current_win(editor)
  qp.start()
  eq("an open tree is not re-revealed", #T.reveals, 0)
  check("... and numbered at once", qp.is_active())
  qp.cancel()

  -- ...but an explicit root is honoured even then
  qp.start({ parent_levels = 1 })
  eq("an explicit root re-roots an open tree", T.reveals[1] and T.reveals[1].levels, 1)
  vim.wait(3000, function()
    return qp.is_active()
  end, 20)
  qp.cancel()
end)

section("lifecycle: a tree that never opens fails cleanly", function()
  local T = world({}, {}, false)
  T.adapter.open_reveal = function()
    return true -- accepted, but nothing ever shows
  end
  local timers0 = active_timers()
  local warned = false
  local orig = vim.notify
  vim.notify = function(m, l)
    if tostring(m):find("did not show") and l == vim.log.levels.WARN then warned = true end
  end
  qp.start()
  vim.wait(5000, function()
    return warned
  end, 50)
  vim.notify = orig
  check("it warns after a while", warned)
  check("no mode", not qp.is_active())
  check("no polling timer left", active_timers() <= timers0)

  T.adapter.open_reveal = function()
    return false
  end
  eq("a refused open is a failed start", qp.start(), false)
end)

section("lifecycle: cancel during boot stops the poll", function()
  world({}, { open_delay = 400 }, false)
  qp.start()
  local armed = active_timers()
  check("polling (the fake's own delayed open is one timer, the poll another)", armed >= 2)
  qp.cancel()
  eq("cancel stopped exactly the poll timer", active_timers(), armed - 1)
  vim.wait(700, function()
    return false
  end)
  check("the late-opening tree did not start a mode", not qp.is_active())
end)

section("lifecycle: teardown cleans a running mode and the global keys", function()
  local T = world()
  qp.start()
  qp.teardown()
  check("teardown ends the mode", not qp.is_active())
  eq("labels cleared", #ns_marks(T), 0)
  check("autocmds gone", not group_exists("filetree_quickpick"))
  check("the global trigger is unmapped", vim.fn.maparg("<leader>;", "n") == "")
  eq("start is refused after teardown", qp.start(), false)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Wiring: setup(), global keys, command, config validation
-- ═══════════════════════════════════════════════════════════════════════════════

section("wiring: filetree.setup() enables the feature, binds the keys, runs the command", function()
  qp.teardown()
  reset_buffers()
  local ft = require("filetree")
  local T = make_tree(TREE_ROWS(), {})
  ft.register_adapter(T.adapter)

  ft.setup({ adapter = "fake" })
  check("off by default", ft.feature("quickpick") == nil)
  eq("no trigger mapped by default", vim.fn.maparg("<leader>;", "n"), "")

  ft.setup({ adapter = "fake", features = { quickpick = { enabled = true, timeout_ms = 0 } } })
  check("on when enabled", ft.feature("quickpick") ~= nil)
  check("<leader>; is mapped", vim.fn.maparg("<leader>;", "n") ~= "")
  check("<leader>: is mapped", vim.fn.maparg("<leader>:", "n") ~= "")

  local eb = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(eb, EDITOR_FILE)
  vim.api.nvim_win_set_buf(0, eb)
  T.reveals = {}
  press("2<leader>;")
  eq("a count before the key roots the tree two levels up", T.reveals[1] and T.reveals[1].levels, 2)
  vim.wait(3000, function()
    return ft.feature("quickpick").is_active()
  end, 20)
  check("... and the mode runs", ft.feature("quickpick").is_active())
  ft.feature("quickpick").cancel()

  vim.api.nvim_win_close(T.win, true)
  T.reveals = {}
  vim.cmd("Filetree quickpick 3")
  eq(":Filetree quickpick N passes the levels", T.reveals[1] and T.reveals[1].levels, 3)
  vim.wait(3000, function()
    return ft.feature("quickpick").is_active()
  end, 20)
  vim.cmd("Filetree quickpick cancel")
  check(":Filetree quickpick cancel ends it", not ft.feature("quickpick").is_active())

  vim.api.nvim_win_close(T.win, true)
  T.reveals = {}
  vim.cmd("Filetree quickpick cwd")
  eq(":Filetree quickpick cwd roots at the cwd", T.reveals[1] and T.reveals[1].root, uv.cwd())
  vim.wait(3000, function()
    return ft.feature("quickpick").is_active()
  end, 20)
  vim.cmd("Filetree quickpick cancel")

  ft.setup({
    adapter = "fake",
    features = { quickpick = { enabled = true, keymap = false, keymap_cwd = "<leader>x" } },
  })
  eq("keymap = false leaves the trigger unmapped", vim.fn.maparg("<leader>;", "n"), "")
  check("keymap_cwd is remappable", vim.fn.maparg("<leader>x", "n") ~= "")
  ft.setup({ adapter = "fake" })
  eq("re-setup with the feature off removes the keys", vim.fn.maparg("<leader>x", "n"), "")
end)

section("wiring: the command and the binding catalog say so when the feature is off", function()
  local ft = require("filetree")
  ft.setup({ adapter = "fake" })
  local warned = false
  local orig = vim.notify
  vim.notify = function(m)
    if tostring(m):find("quickpick is off") then warned = true end
  end
  vim.cmd("Filetree quickpick")
  vim.notify = orig
  check(":Filetree quickpick explains that it is off", warned)

  local cat = require("filetree.bindings").catalog()
  local found = 0
  for _, b in ipairs(cat.keymaps.nav) do
    if b.feature == "quickpick" and b.opt_in and b.scope == "global" then found = found + 1 end
  end
  eq("the catalog lists both triggers as global opt-in", found, 2)
  local paths = table.concat(cat.usercommands, " ")
  check(
    "the command paths include quickpick, quickpick cwd and cancel",
    paths:find("quickpick", 1, true)
      and paths:find("quickpick cwd", 1, true)
      and paths:find("quickpick cancel", 1, true)
  )
end)

section("wiring: config validation", function()
  local config = require("filetree.config")
  local function issues_for(body)
    config.setup({ adapter = "fake", features = { quickpick = body } })
    local out = config.issues()
    config.setup({})
    return out
  end
  eq("a valid body has no issues", #issues_for({
    enabled = true,
    width = 3,
    content = "files",
    keys = { cancel = { "q", "<Esc>" } },
  }), 0)
  check("width out of range is reported", #issues_for({ width = 5 }) == 1)
  check("width 0 is reported", #issues_for({ width = 0 }) == 1)
  check("an unknown content is reported", #issues_for({ content = "both" }) == 1)
  check("an unknown open_mode is reported", #issues_for({ open_mode = "preview" }) == 1)
  check("a bad label_pos is reported", #issues_for({ label_pos = "middle" }) == 1)
  check("a negative timeout is reported", #issues_for({ timeout_ms = -1 }) == 1)
  check(
    "a non-boolean silence flag is reported",
    #issues_for({ silence_nvim_mappings = "yes" }) == 1
  )
  local typo = issues_for({ silence_nvim_mapping = true })
  check(
    "a typo is reported with a hint",
    #typo == 1 and typo[1]:find("silence_nvim_mappings", 1, true) ~= nil,
    vim.inspect(typo)
  )
  check("an unknown key in `keys` is reported", #issues_for({ keys = { cancle = "q" } }) == 1)
  check("a non-string key is reported", #issues_for({ keys = { cancel = 5 } }) == 1)
  check(
    "a key list with a non-string is reported",
    #issues_for({ keys = { cancel = { "q", 5 } } }) == 1
  )
  check(
    "`false` unmaps a key without complaint",
    #issues_for({ keys = { cycle = false }, keymap = false }) == 0
  )

  -- the position tuple is validated at setup, with a warning, not by the schema
  local warned = false
  local orig = vim.notify
  vim.notify = function(m)
    if tostring(m):find("indicator_position", 1, true) then warned = true end
  end
  qp.teardown()
  qp.setup(
    { enabled = true, indicator_position = { "nvim", "middle", "left" } },
    make_tree(TREE_ROWS(), {}).adapter
  )
  vim.notify = orig
  check("a bad indicator_position warns", warned)
  qp.teardown()
end)

print(("\nfiletree.nvim quickpick: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
