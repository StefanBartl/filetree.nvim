-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- Test doubles here implement only what the unit under test calls -- a full
-- FiletreeAdapter or FiletreeRef would be noise, not coverage.
-- gaps.lua — headless unit tests for modules TESTS/units.lua and TESTS/smoke.lua
-- had not reached yet (round 26 of the cross-plugin test-coverage campaign).
--
-- Same harness/conventions as TESTS/units.lua (its own header explains the
-- rtp/TMP_ROOT setup below in full); split into its own file rather than
-- appended to units.lua, which was already ~5000 lines before this pass.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/gaps.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root)

local lib_candidates = {}
for _, env in ipairs({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" then lib_candidates[#lib_candidates + 1] = v end
end
lib_candidates[#lib_candidates + 1] = vim.fn.fnamemodify(root, ":h") .. "/lib.nvim"
lib_candidates[#lib_candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"
for _, candidate in ipairs(lib_candidates) do
  if vim.fn.isdirectory(candidate .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(candidate)
    break
  end
end

-- ui.nvim: filetree.refs.ui / the marks feature require("ui.kit") unconditionally
-- at module load, and ft.setup() loads refs eagerly -- same candidate order as
-- lib.nvim above.
local ui_candidates = {}
for _, env in ipairs({ "FILETREE_UI_NVIM", "UI_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" then ui_candidates[#ui_candidates + 1] = v end
end
ui_candidates[#ui_candidates + 1] = vim.fn.fnamemodify(root, ":h") .. "/ui.nvim"
ui_candidates[#ui_candidates + 1] = vim.fn.stdpath("data") .. "/lazy/ui.nvim"
for _, candidate in ipairs(ui_candidates) do
  if vim.fn.isdirectory(candidate .. "/lua/ui") == 1 then
    vim.opt.rtp:prepend(candidate)
    break
  end
end

-- Cross-platform scratch-dir root, canonicalized -- see TESTS/units.lua's
-- header for why (8.3 short-name mismatch on Windows $TEMP).
local TMP_ROOT = vim.env.TEMP or vim.env.TMPDIR or vim.env.TMP or "/tmp"
do
  local uv = vim.uv or vim.loop
  TMP_ROOT = (uv.fs_realpath(TMP_ROOT) or TMP_ROOT):gsub("\\", "/")
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
local function eq(name, got, want)
  check(name, got == want, ("got %q want %q"):format(tostring(got), tostring(want)))
end

-- ── util.conflict ── destination-collision helpers (paste/move overwrite) ───
do
  local conflict = require("filetree.util.conflict")
  local tmp = (TMP_ROOT .. "/gaps-conflict"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")

  eq(
    "conflict.exists: false for a path that isn't there",
    conflict.exists(tmp .. "/nope.txt"),
    false
  )
  vim.fn.writefile({ "x" }, tmp .. "/a.txt")
  eq("conflict.exists: true for a file", conflict.exists(tmp .. "/a.txt"), true)
  eq("conflict.exists: true for a directory", conflict.exists(tmp), true)

  local claimed = {}
  local name1 = conflict.unique_name(tmp, "a.txt", claimed, false)
  eq("unique_name: first free slot is '(2)'", name1, "a (2).txt")
  eq("unique_name: claims the name it handed out", claimed["a (2).txt"], true)

  -- A name claimed earlier in the SAME batch is skipped even though nothing
  -- on disk collides with it yet (batch-wide dedup, not just an fs check).
  local claimed2 = { ["b (2).txt"] = true }
  local name2 = conflict.unique_name(tmp, "b.txt", claimed2, false)
  eq("unique_name: skips a name already claimed earlier in the batch", name2, "b (3).txt")

  -- A dotfile has no extension to preserve -- the naive regex would otherwise
  -- read the WHOLE name as "the extension" and produce " (2)" with nothing
  -- in front of it.
  local name3 = conflict.unique_name(tmp, ".gitignore", {}, false)
  eq("unique_name: a dotfile keeps its name as the base, no split", name3, ".gitignore (2)")

  -- Multi-dot name: only the LAST extension is preserved.
  local name4 = conflict.unique_name(tmp, "archive.tar.gz", {}, false)
  eq("unique_name: only the last extension is preserved", name4, "archive.tar (2).gz")

  -- Directories never get extension-splitting.
  vim.fn.mkdir(tmp .. "/sub.old", "p")
  local name5 = conflict.unique_name(tmp, "sub.old", {}, true)
  eq("unique_name: a directory name is never extension-split", name5, "sub.old (2)")

  eq("remove_existing: deletes a file", conflict.remove_existing(tmp .. "/a.txt"), true)
  eq("remove_existing: the file is actually gone", vim.fn.filereadable(tmp .. "/a.txt"), 0)
  vim.fn.mkdir(tmp .. "/dir1/nested", "p")
  eq("remove_existing: deletes a directory tree", conflict.remove_existing(tmp .. "/dir1"), true)
  eq("remove_existing: the directory is actually gone", vim.fn.isdirectory(tmp .. "/dir1"), 0)
end

-- ── refs.pathutil ── Windows-safe path core for the reference engine ────────
-- Every rename/move feature routes through this to decide whether a written
-- link target still points at a file that just moved. Deliberately lexical
-- (see the module's own header) -- these are pure string assertions, no fs.
do
  local pu = require("filetree.refs.pathutil")
  local platform = require("filetree.util.platform")
  local ftpath = require("filetree.util.path")

  local drive = TMP_ROOT:match("^(%a:)")
  if drive then
    eq(
      "pathutil.abs: backslash and forward-slash spellings key identically",
      pu.abs(drive .. "\\proj\\a.md"),
      pu.abs(drive .. "/proj/a.md")
    )
  end
  eq(
    "pathutil.abs: trailing slash is stripped",
    pu.abs(TMP_ROOT .. "/proj/"),
    pu.abs(TMP_ROOT .. "/proj")
  )

  local cwd = ((vim.uv or vim.loop).cwd() or vim.fn.getcwd()):gsub("\\", "/"):gsub("/+$", "")
  eq(
    "pathutil.abs: a relative path resolves against the real cwd",
    pu.abs("gaps-relfile.md"),
    cwd .. "/gaps-relfile.md"
  )

  local a = TMP_ROOT .. "/Proj/A.MD"
  local b = TMP_ROOT .. "/proj/a.md"
  if platform.is_windows() or platform.is_mac() then
    check("pathutil.same: case-insensitive on this platform", pu.same(a, b))
  else
    check("pathutil.same: case-SENSITIVE on this platform", not pu.same(a, b))
  end

  local base = TMP_ROOT .. "/proj/docs"
  check("pathutil.under: a directory is under itself", pu.under(base, base))
  check("pathutil.under: a child path is under its parent", pu.under(base .. "/x.md", base))
  check(
    "pathutil.under: a sibling sharing a string prefix is NOT under it (no 'docs-old' false hit)",
    not pu.under(TMP_ROOT .. "/proj/docs-old/x.md", base)
  )

  -- resolve_candidates(): the three target styles.
  local from_file = TMP_ROOT .. "/proj/docs/readme.md"
  local root_dir = TMP_ROOT .. "/proj"

  local rel_cands = pu.resolve_candidates("../assets/img.png", from_file, root_dir)
  eq("resolve_candidates: a relative target -> exactly one candidate", #rel_cands, 1)
  check(
    "resolve_candidates: a relative target resolves against the FILE's dir, not the root",
    pu.same(rel_cands[1], TMP_ROOT .. "/proj/assets/img.png")
  )

  local slash_cands = pu.resolve_candidates("/assets/img.png", from_file, root_dir)
  eq("resolve_candidates: a leading '/' -> two candidates (fs, root)", #slash_cands, 2)
  check(
    "resolve_candidates: the second reading is project-root-relative",
    pu.same(slash_cands[2], root_dir .. "/assets/img.png")
  )

  if drive then
    local fs_cands = pu.resolve_candidates(drive .. "/other/img.png", from_file, root_dir)
    eq("resolve_candidates: a drive-absolute target -> exactly one candidate", #fs_cands, 1)
  end

  -- match(): which reading actually points at the moved file, and which does not.
  local resolved, style =
    pu.match("../assets/img.png", from_file, root_dir, TMP_ROOT .. "/proj/assets/img.png", false)
  eq("match: a relative target reports the 'relative' style", style, "relative")
  check(
    "match: the resolved path keys the same as the target it matched",
    resolved ~= nil and pu.same(resolved, TMP_ROOT .. "/proj/assets/img.png")
  )
  local no_resolved, no_style = pu.match(
    "../assets/img.png",
    from_file,
    root_dir,
    TMP_ROOT .. "/proj/assets/renamed.png",
    false
  )
  eq("match: a target that does not point at `wanted` returns nil", no_resolved, nil)
  eq("match: ...and a nil style with it", no_style, nil)

  -- retarget(): each style reproduces its own spelling.
  eq(
    "retarget: 'relative' style keeps a bare (non-dotted) path bare",
    pu.retarget({
      style = "relative",
      target = "assets/img.png",
      from_file = from_file,
      root = root_dir,
      new_path = TMP_ROOT .. "/proj/docs/assets/renamed.png",
    }),
    "assets/renamed.png"
  )
  eq(
    "retarget: 'relative' style keeps an explicit './' prefix",
    pu.retarget({
      style = "relative",
      target = "./img.png",
      from_file = from_file,
      root = root_dir,
      new_path = TMP_ROOT .. "/proj/docs/renamed.png",
    }),
    "./renamed.png"
  )
  eq(
    "retarget: 'root' style re-adds the leading slash, project-root-relative",
    pu.retarget({
      style = "root",
      target = "/assets/img.png",
      from_file = from_file,
      root = root_dir,
      new_path = TMP_ROOT .. "/proj/assets/renamed.png",
    }),
    "/assets/renamed.png"
  )
  eq(
    "retarget: 'fs' style returns a plain absolute path (ftpath.to_unix)",
    pu.retarget({
      style = "fs",
      target = TMP_ROOT .. "/proj/assets/img.png",
      from_file = from_file,
      root = root_dir,
      new_path = TMP_ROOT .. "/proj/assets/renamed.png",
    }),
    ftpath.to_unix(TMP_ROOT .. "/proj/assets/renamed.png")
  )

  -- remap_under(): directory-move cascade for a path living underneath it.
  check(
    "remap_under: a nested path follows its ancestor directory's move",
    pu.same(
      pu.remap_under(
        TMP_ROOT .. "/proj/olddir/a/b.md",
        TMP_ROOT .. "/proj/olddir",
        TMP_ROOT .. "/proj/newdir"
      ),
      TMP_ROOT .. "/proj/newdir/a/b.md"
    )
  )
  check(
    "remap_under: the moved directory itself (rest == '.') maps to new_dir",
    pu.same(
      pu.remap_under(
        TMP_ROOT .. "/proj/olddir",
        TMP_ROOT .. "/proj/olddir",
        TMP_ROOT .. "/proj/newdir"
      ),
      TMP_ROOT .. "/proj/newdir"
    )
  )

  eq(
    "pathutil.relative: forward slashes regardless of OS",
    pu.relative(TMP_ROOT .. "/proj/a/b.md", TMP_ROOT .. "/proj"),
    "a/b.md"
  )
end

-- ── refs: outgoing_assets contract, pinned for fileops.nvim's soft bridge ───
-- fileops.nvim's integrations/filetree_assets.lua treats filetree.nvim as
-- present ONLY when both these resolve to real functions (see that module's
-- own `refs()` helper) -- a rename on either side silently turns cascade-
-- delete-assets into a permanent no-op on the fileops.nvim side, with
-- nothing on THAT side able to say so (it is a deliberately soft dependency).
-- Pinning the contract here is the other half.
do
  local refs = require("filetree.refs")
  check(
    "refs.outgoing_assets_mode is a function (fileops.nvim bridge contract)",
    type(refs.outgoing_assets_mode) == "function"
  )
  check(
    "refs.outgoing_assets is a function (fileops.nvim bridge contract)",
    type(refs.outgoing_assets) == "function"
  )
end

-- ── util.markdown_refs ── disk/buffer patch layer (soft dep on markdown.nvim) ─
do
  local refs_util = require("filetree.util.markdown_refs")

  check(
    "markdown_refs.available(): false without markdown.nvim installed",
    not refs_util.available()
  )
  eq("markdown_refs.find(): {} when markdown.nvim is absent", #refs_util.find("/nope.md"), 0)

  local done, got = false, nil
  refs_util.find_async("/nope.md", nil, function(refs)
    done, got = true, refs
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  check(
    "markdown_refs.find_async(): still calls back with {} when absent",
    done and got ~= nil and #got == 0
  )

  -- prefetch() rides find_async() underneath, which schedules its callback
  -- (vim.schedule) even in the "absent" fallback path -- not synchronous.
  local handle = refs_util.prefetch("/nope.md")
  local awaited
  handle.await(function(refs)
    awaited = refs
  end)
  vim.wait(1000, function()
    return awaited ~= nil
  end, 10)
  check(
    "markdown_refs.prefetch(): await() eventually fires with {} when absent",
    awaited ~= nil and #awaited == 0
  )

  -- await() called AFTER the handle already resolved must fire inline,
  -- immediately, with the exact same result -- no double scheduling.
  local awaited2
  handle.await(function(refs)
    awaited2 = refs
  end)
  check(
    "markdown_refs.prefetch(): a second await() after resolution fires inline",
    awaited2 ~= nil and #awaited2 == 0
  )

  -- unique_files(): dedup by slashified key, regardless of separator spelling.
  local cwd = vim.fn.getcwd():gsub("\\", "/")
  local f1 = cwd .. "/sub/a.md"
  local files = refs_util.unique_files({
    { file = f1, target = "x" },
    { file = f1:gsub("/", "\\"), target = "y" }, -- same file, backslash spelling
    { file = cwd .. "/sub/b.md", target = "z" },
  })
  eq("unique_files: two spellings of the same file dedup to one entry", #files, 2)

  -- update(): content-verified rewrite on disk.
  local tmp = (TMP_ROOT .. "/gaps-mdrefs"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local file_on_disk = tmp .. "/linker.md"
  vim.fn.writefile({ "# Linker", "See [old](old.md) for details." }, file_on_disk)

  local changed = refs_util.update({
    { file = file_on_disk, line = 2, target = "old.md", new_target = "new.md" },
  })
  eq("update(): reports one file changed", changed, 1)
  eq(
    "update(): the link target was rewritten on disk",
    vim.fn.readfile(file_on_disk)[2],
    "See [old](new.md) for details."
  )

  -- A line that drifted since the ref was scanned is left alone, not corrupted.
  vim.fn.writefile({ "# Linker", "This line no longer mentions the link at all." }, file_on_disk)
  local changed2 = refs_util.update({
    { file = file_on_disk, line = 2, target = "old.md", new_target = "new.md" },
  })
  eq("update(): a line that drifted since the scan is left untouched", changed2, 0)
  eq(
    "update(): the drifted line's content is unchanged",
    vim.fn.readfile(file_on_disk)[2],
    "This line no longer mentions the link at all."
  )

  -- An OPEN buffer with unsaved changes elsewhere is patched in memory and
  -- left modified -- disk must not be touched under the user's edits.
  vim.fn.writefile({ "# Linker", "See [old](old.md) for details." }, file_on_disk)
  vim.cmd("edit " .. vim.fn.fnameescape(file_on_disk))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "# Linker (draft)" }) -- unrelated unsaved edit
  check("update()/buffer setup: buffer starts out modified", vim.bo[bufnr].modified)

  local changed3 = refs_util.update({
    { file = file_on_disk, line = 2, target = "old.md", new_target = "new.md" },
  })
  eq("update(): still reports the file as changed for an open buffer", changed3, 1)
  eq(
    "update(): the open buffer's target line was patched in memory",
    vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1],
    "See [old](new.md) for details."
  )
  check("update(): a buffer with PRIOR unsaved changes stays modified", vim.bo[bufnr].modified)
  eq(
    "update(): disk is untouched when the buffer already had unsaved changes",
    vim.fn.readfile(file_on_disk)[2],
    "See [old](old.md) for details."
  )
  vim.cmd("bdelete! " .. bufnr)

  -- A CLEAN open buffer is patched AND persisted, staying unmodified.
  vim.fn.writefile({ "# Linker", "See [old](old.md) for details." }, file_on_disk)
  vim.cmd("edit " .. vim.fn.fnameescape(file_on_disk))
  local bufnr2 = vim.api.nvim_get_current_buf()
  check("update()/buffer setup (clean): buffer starts unmodified", not vim.bo[bufnr2].modified)
  refs_util.update({ { file = file_on_disk, line = 2, target = "old.md", new_target = "new.md" } })
  check(
    "update(): a clean buffer is written back and stays unmodified",
    not vim.bo[bufnr2].modified
  )
  eq(
    "update(): disk WAS updated for a clean buffer",
    vim.fn.readfile(file_on_disk)[2],
    "See [old](new.md) for details."
  )
  vim.cmd("bdelete! " .. bufnr2)
end

-- ── infra.hooks_api ── pure event bus ────────────────────────────────────────
do
  local hooks = require("filetree.features.infra.hooks_api")
  hooks.setup({ enabled = true }, nil)
  hooks.clear()

  local calls = {}
  local id1 = hooks.on("before_delete", function(data)
    calls[#calls + 1] = { "h1", data.path }
  end)
  hooks.on("before_delete", function(data)
    calls[#calls + 1] = { "h2", data.path }
  end)

  eq(
    "hooks_api.emit(): calls every handler registered for the event",
    hooks.emit("before_delete", { path = "/a" }),
    2
  )
  eq("hooks_api.emit(): first handler saw the right data", calls[1][1] .. calls[1][2], "h1/a")
  eq("hooks_api.emit(): second handler also fired", calls[2][1] .. calls[2][2], "h2/a")
  eq(
    "hooks_api.emit(): an event with no handlers calls zero, no error",
    hooks.emit("nothing_here"),
    0
  )

  check("hooks_api.off(): removes a handler by id", hooks.off(id1))
  calls = {}
  hooks.emit("before_delete", { path = "/b" })
  eq("hooks_api.off(): the removed handler no longer fires", #calls, 1)

  calls = {}
  hooks.once("tree_open", function()
    calls[#calls + 1] = true
  end)
  hooks.emit("tree_open")
  hooks.emit("tree_open")
  eq("hooks_api.once(): fires exactly once across two emits", #calls, 1)

  -- A handler that errors must not stop the OTHER handlers for the same event.
  hooks.clear()
  local order = {}
  hooks.on("x", function()
    error("boom")
  end)
  hooks.on("x", function()
    order[#order + 1] = "second"
  end)
  local n = hooks.emit("x")
  eq("hooks_api.emit(): still counts a handler that errored as called", n, 2)
  eq("hooks_api.emit(): a later handler still runs after an earlier one errors", order[1], "second")

  hooks.clear()
  hooks.on("a", function() end)
  hooks.on("a", function() end)
  hooks.on("b", function() end)
  eq("hooks_api.count('a'): counts handlers for one event", hooks.count("a"), 2)
  eq("hooks_api.count(): total across all events", hooks.count(), 3)
  local evs = hooks.events()
  table.sort(evs)
  eq(
    "hooks_api.events(): lists every event that still has a live handler",
    table.concat(evs, ","),
    "a,b"
  )

  hooks.clear("a")
  eq("hooks_api.clear(event): only clears that event", hooks.count("a"), 0)
  eq("hooks_api.clear(event): leaves other events alone", hooks.count("b"), 1)

  hooks.clear()
  eq("hooks_api.clear(): clears everything", hooks.count(), 0)
  hooks.teardown()
end

-- ── infra.watcher_quarantine ── EPERM suppression window, not a permanent ───
-- failure cache: is_active() self-expires, and exit() always restores the
-- exact vim.notify it captured, even across a second enter() in between.
do
  local wq = require("filetree.features.infra.watcher_quarantine")
  wq.teardown()

  wq.setup({ enabled = true, silent = true, duration_ms = 10000, patch_neotree_watch = false }, nil)

  check("watcher_quarantine: inactive before enter()", not wq.is_active())
  wq.enter()
  check("watcher_quarantine: active right after enter()", wq.is_active())
  check(
    "watcher_quarantine: with no path list, every path is quarantined (global window)",
    wq.is_path_quarantined("/anything")
  )

  wq.enter(10000, { "/only/this" })
  check("watcher_quarantine: a listed path is quarantined", wq.is_path_quarantined("/only/this"))
  check(
    "watcher_quarantine: an unlisted path is NOT quarantined",
    not wq.is_path_quarantined("/other")
  )
  wq.exit()

  -- EPERM suppression: vim.notify is patched while active, restored on exit.
  local probe_calls = {}
  local probe = function(msg, ...)
    probe_calls[#probe_calls + 1] = msg
  end
  local outer_orig = vim.notify
  vim.notify = probe
  wq.enter(10000)
  check("watcher_quarantine: vim.notify was replaced by the module's wrapper", vim.notify ~= probe)
  vim.notify("EPERM: something", vim.log.levels.ERROR)
  vim.notify("a normal message", vim.log.levels.INFO)
  eq(
    "watcher_quarantine: the EPERM line was swallowed, the normal one got through",
    #probe_calls,
    1
  )
  eq(
    "watcher_quarantine: the surviving message is the non-EPERM one",
    probe_calls[1],
    "a normal message"
  )
  wq.exit()
  check(
    "watcher_quarantine: exit() restores the probe it had captured as 'original'",
    vim.notify == probe
  )
  check("watcher_quarantine: inactive after exit()", not wq.is_active())
  vim.notify = outer_orig

  -- wrap(): runs fn inside a quarantine window; a wrapped fn's result and
  -- errors are both reported through, not swallowed silently.
  local ran = false
  local result = wq.wrap(function()
    ran = true
    return "ok"
  end, 5000)
  check("watcher_quarantine.wrap(): the wrapped fn actually ran", ran)
  eq("watcher_quarantine.wrap(): returns the fn's result", result, "ok")
  wq.exit()

  -- A wrapped fn that errors must not raise OUT of wrap() itself (pcall'd
  -- internally) -- but note what actually comes back: `result` is pcall's
  -- second return, which on failure is the STRINGIFIED ERROR MESSAGE, not
  -- nil. A caller cannot tell that apart from a genuine string result.
  local wrap_ok, result2 = pcall(wq.wrap, function()
    error("boom")
  end, 5000)
  check("watcher_quarantine.wrap(): a wrapped fn that errors does not raise out of wrap()", wrap_ok)
  check(
    "watcher_quarantine.wrap(): on error, the return value is the stringified error (not nil)",
    type(result2) == "string" and result2:find("boom", 1, true) ~= nil
  )
  wq.exit()

  check(
    "watcher_quarantine.patch_neotree_watch(): false without neo-tree on the runtime path, never throws",
    wq.patch_neotree_watch() == false
  )

  wq.teardown()
  check("watcher_quarantine: teardown() also exits an active quarantine", not wq.is_active())
end

-- ── infra.safety.backup ── real fs copy/prune, argv spawn stubbed at the seam ─
do
  local captured_argv
  package.loaded["lib.nvim.cross.run_argv"] = {
    run_blocking = function(cmd)
      captured_argv = cmd
      local src, dst = cmd[#cmd - 1], cmd[#cmd]
      if vim.fn.isdirectory(src) == 1 then
        vim.fn.mkdir(dst, "p")
        return true
      end
      return pcall(function()
        vim.fn.writefile(vim.fn.readfile(src, "b"), dst, "b")
      end)
    end,
  }
  package.loaded["filetree.features.infra.safety.backup"] = nil
  local backup = require("filetree.features.infra.safety.backup")

  local tmp = (TMP_ROOT .. "/gaps-backup"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  local dir = tmp .. "/store"

  backup.init({ backup_dir = dir, max_backups = 3, dry_run = false })
  check("backup.init(): creates the backup directory", vim.fn.isdirectory(dir) == 1)

  eq(
    "backup.create(): nil (no crash) for a source that doesn't exist",
    backup.create(tmp .. "/nope.txt"),
    nil
  )

  local src = tmp .. "/f1.txt"
  vim.fn.writefile({ "hello" }, src)
  local dst = backup.create(src)
  check("backup.create(): returns a destination path", dst ~= nil)
  if dst then
    eq("backup.create(): the backup file exists", vim.fn.filereadable(dst), 1)
    eq("backup.create(): the content was actually copied", vim.fn.readfile(dst)[1], "hello")
    check("backup.create(): the backup lands INSIDE the configured dir", vim.startswith(dst, dir))
  end
  check(
    "backup: shells out via the platform-appropriate copy command (xcopy/cp -r)",
    captured_argv ~= nil and (captured_argv[1] == "xcopy" or captured_argv[1] == "cp")
  )

  -- prune(): more than max_backups collapses back down to max_backups.
  for i = 2, 6 do
    local s = tmp .. "/f" .. i .. ".txt"
    vim.fn.writefile({ "x" }, s)
    backup.create(s)
  end
  eq("backup.list(): never exceeds max_backups after prune()", #backup.list(), 3)

  package.loaded["lib.nvim.cross.run_argv"] = nil
  package.loaded["filetree.features.infra.safety.backup"] = nil
end

-- ── adapter.mini_files ── pure translation helpers, mini.files stubbed ──────
do
  local tmp = (TMP_ROOT .. "/gaps-minifiles"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")

  vim.cmd("silent! only")
  local mf_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(mf_buf, 0, -1, false, { "a.lua", "sub" })
  vim.api.nvim_set_current_buf(mf_buf)
  local mf_win = vim.api.nvim_get_current_win()

  -- `path` deliberately carries mini.files' own doubled-slash-after-drive
  -- quirk (documented in the adapter's normalize_key comment) -- the point
  -- of get_node_line() is that it survives this.
  local ENTRIES = {
    [1] = { fs_type = "file", name = "a.lua", path = tmp .. "//a.lua" },
    [2] = { fs_type = "directory", name = "sub", path = tmp .. "//sub" },
  }

  package.loaded["mini.files"] = {
    get_explorer_state = function()
      return { anchor = tmp, windows = { { win_id = mf_win, path = tmp } } }
    end,
    get_fs_entry = function(buf, line)
      if buf == nil and line == nil then return ENTRIES[1] end -- cursor-based call
      return ENTRIES[line]
    end,
    open = function() end,
    close = function() end,
  }
  package.loaded["filetree.adapter.mini_files"] = nil
  local mfa = require("filetree.adapter.mini_files")

  check("mini_files.is_available(): true once mini.files resolves", mfa.is_available())
  eq("mini_files.get_root_path(): reports the explorer's anchor", mfa.get_root_path(), tmp)

  local is_open, bufnr = mfa.is_open()
  check("mini_files.is_open(): true with a valid tracked window", is_open)
  eq("mini_files.is_open(): reports that window's buffer", bufnr, mf_buf)
  eq("mini_files.get_winid(): the tracked window id", mfa.get_winid(), mf_win)

  local node = mfa.get_current_node()
  check("mini_files.get_current_node(): resolves via the cursor-based get_fs_entry()", node ~= nil)
  if node then eq("mini_files.get_current_node(): fs_type mapped to 'file'", node.type, "file") end

  local nodes = mfa.get_visible_nodes()
  eq("mini_files.get_visible_nodes(): one node per buffer line", #nodes, 2)
  eq("mini_files.get_visible_nodes(): file type mapped from fs_type", nodes[1].type, "file")
  eq(
    "mini_files.get_visible_nodes(): directory type mapped from fs_type",
    nodes[2].type,
    "directory"
  )

  local files_only = mfa.get_visible_nodes("files")
  eq("mini_files.get_visible_nodes('files'): filters out directories", #files_only, 1)
  eq(
    "mini_files.get_visible_nodes('files'): the surviving entry is the file",
    files_only[1].name,
    "a.lua"
  )

  eq(
    "mini_files.get_node_line(): finds the line despite the doubled-slash quirk",
    mfa.get_node_line(tmp .. "/a.lua"),
    1
  )
  eq(
    "mini_files.get_node_line(): a path with no matching node is nil",
    mfa.get_node_line(tmp .. "/nope.lua"),
    nil
  )

  check(
    "mini_files.highlight_node(): sets an extmark on the node's line",
    mfa.highlight_node(tmp .. "/a.lua", "Comment")
  )
  check("mini_files.unhighlight_node(): removes it again", mfa.unhighlight_node(tmp .. "/a.lua"))
  check(
    "mini_files.unhighlight_node(): a path never highlighted is a no-op success",
    mfa.unhighlight_node(tmp .. "/never.lua")
  )

  local target = tmp .. "/a.lua"
  vim.fn.writefile({ "x" }, target)
  check("mini_files.open_file(): edits the target path", mfa.open_file(target, "edit"))
  vim.api.nvim_set_current_win(mf_win)
  check(
    "mini_files.scroll_to_line(): moves the cursor in the tracked window",
    mfa.scroll_to_line(1)
  )

  vim.cmd("silent! only")
  package.loaded["mini.files"] = nil
  package.loaded["filetree.adapter.mini_files"] = nil
end

-- ── fileops.buffer_save ── force-save without leaving the tree window ──────
do
  local bsave = require("filetree.features.fileops.buffer_save")
  local tmp = (TMP_ROOT .. "/gaps-buffersave"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local file1 = tmp .. "/adjacent.txt"
  vim.fn.writefile({ "one" }, file1)

  vim.cmd("silent! only")
  vim.cmd("edit " .. vim.fn.fnameescape(file1))
  local editor_buf = vim.api.nvim_get_current_buf()
  vim.cmd("botright vsplit")
  local tree_win = vim.api.nvim_get_current_win()
  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(tree_win, tree_buf)
  vim.api.nvim_set_current_win(tree_win)

  local stub = {
    name = "gaps-buffersave-stub",
    get_current_node = function()
      return nil
    end,
  }
  bsave.setup({ enabled = true, force = true }, stub)

  vim.api.nvim_set_current_win(tree_win)
  vim.api.nvim_buf_set_lines(editor_buf, 0, -1, false, { "two" })
  check(
    "buffer_save.save_adjacent(): the target buffer starts out modified",
    vim.bo[editor_buf].modified
  )
  bsave.save_adjacent()
  check(
    "buffer_save.save_adjacent(): saved the adjacent editor buffer",
    not vim.bo[editor_buf].modified
  )
  eq(
    "buffer_save.save_adjacent(): the content is actually on disk",
    vim.fn.readfile(file1)[1],
    "two"
  )

  -- save_node(): saves whatever buffer matches the node under the cursor,
  -- even though focus never left the tree window.
  local file2 = tmp .. "/node.txt"
  vim.fn.writefile({ "a" }, file2)
  vim.cmd("edit " .. vim.fn.fnameescape(file2))
  local node_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_win(tree_win)
  stub.get_current_node = function()
    return { path = file2, type = "file" }
  end
  vim.api.nvim_buf_set_lines(node_buf, 0, -1, false, { "b" })
  bsave.save_node()
  check(
    "buffer_save.save_node(): saved the buffer matching the node",
    not vim.bo[node_buf].modified
  )
  eq("buffer_save.save_node(): content on disk matches", vim.fn.readfile(file2)[1], "b")

  stub.get_current_node = function()
    return nil
  end
  local ok_call = pcall(bsave.save_node)
  check("buffer_save.save_node(): no node under cursor never throws", ok_call)

  stub.get_current_node = function()
    return { path = tmp .. "/never-opened.txt", type = "file" }
  end
  local ok_call2 = pcall(bsave.save_node)
  check("buffer_save.save_node(): a node whose file isn't loaded anywhere never throws", ok_call2)

  vim.cmd("silent! only")
end

-- ── fileops.open_replace ── replace/swap into the adjacent editor window ───
do
  local orepl = require("filetree.features.fileops.open_replace")
  local tmp = (TMP_ROOT .. "/gaps-openreplace"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local file_a = tmp .. "/a.txt"
  local file_b = tmp .. "/b.txt"
  vim.fn.writefile({ "a" }, file_a)
  vim.fn.writefile({ "b" }, file_b)

  vim.cmd("silent! only")
  vim.cmd("edit " .. vim.fn.fnameescape(file_a))
  local editor_win = vim.api.nvim_get_current_win()
  vim.cmd("botright vsplit")
  local tree_win = vim.api.nvim_get_current_win()
  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(tree_win, tree_buf)

  local cur_node = { path = file_b, type = "file" }
  local stub = {
    name = "gaps-openreplace-stub",
    get_winid = function()
      return tree_win
    end,
    get_current_node = function()
      return cur_node
    end,
    close = function() end,
  }
  orepl.setup({ enabled = true, close_tree = false, swap_close_tree = false }, stub)

  -- open_replace(): the previous buffer stays in the buffer list.
  vim.api.nvim_set_current_win(tree_win)
  local old_buf_a = vim.fn.bufnr(file_a)
  orepl.open_replace()
  check(
    "open_replace(): focus lands in the editor window",
    vim.api.nvim_get_current_win() == editor_win
  )
  eq(
    "open_replace(): the editor window now shows the node's file",
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor_win)), ":t"),
    "b.txt"
  )
  check(
    "open_replace(): the previous buffer is still in the buffer list",
    vim.fn.buflisted(old_buf_a) == 1
  )

  -- open_swap(): refuses (does nothing) when the target buffer is modified.
  vim.api.nvim_set_current_win(editor_win)
  vim.cmd("edit " .. vim.fn.fnameescape(file_a))
  local buf_a = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf_a, 0, -1, false, { "unsaved" })
  cur_node.path = file_b
  vim.api.nvim_set_current_win(tree_win)
  orepl.open_swap()
  check(
    "open_swap(): refuses to close a MODIFIED buffer -- no swap happens",
    vim.api.nvim_win_get_buf(editor_win) == buf_a
  )

  -- open_swap(): the already-open file is just focused, not reopened.
  -- Clear the modified flag via the BUFFER, not `:write` on whatever window
  -- happens to be current (that's the tree window right now).
  vim.api.nvim_buf_call(buf_a, function()
    vim.cmd("write")
  end)
  cur_node.path = file_a
  vim.api.nvim_set_current_win(tree_win)
  local buf_before = vim.api.nvim_win_get_buf(editor_win)
  orepl.open_swap()
  eq(
    "open_swap(): focusing the ALREADY-open file doesn't reopen it",
    vim.api.nvim_win_get_buf(editor_win),
    buf_before
  )
  check(
    "open_swap(): focus moved to the editor window",
    vim.api.nvim_get_current_win() == editor_win
  )

  -- open_swap(): a real swap closes the old buffer and takes its slot.
  cur_node.path = file_b
  vim.api.nvim_set_current_win(tree_win)
  local old_buf = vim.api.nvim_win_get_buf(editor_win)
  orepl.open_swap()
  local new_buf = vim.api.nvim_win_get_buf(editor_win)
  check("open_swap(): the editor window now shows the new file", new_buf ~= old_buf)
  check("open_swap(): the previous buffer was closed", not vim.api.nvim_buf_is_valid(old_buf))

  vim.cmd("silent! only")
end

-- ── nav.layout_guard ── an editor window always exists next to the tree ────
do
  local lg = require("filetree.features.nav.layout_guard")
  vim.cmd("silent! only")
  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(tree_buf)
  local tree_win = vim.api.nvim_get_current_win()
  local is_open = true
  local stub = {
    name = "gaps-layoutguard-stub",
    get_winid = function()
      return tree_win
    end,
    is_open = function()
      return is_open
    end,
    get_position = function()
      return "left"
    end,
  }

  lg.setup({ enabled = true, delay_ms = 10 }, stub)

  vim.cmd("botright vsplit")
  local editor_win = vim.api.nvim_get_current_win()

  -- Closing the last editor window leaves the tree alone -> the guard opens
  -- a new empty one next to it.
  vim.api.nvim_set_current_win(editor_win)
  vim.cmd("close")
  local ok_wait = vim.wait(1000, function()
    return #vim.api.nvim_list_wins() > 1
  end, 10)
  check("layout_guard: a new editor window appears after the last one closes", ok_wait)

  -- No-op when the adapter reports the tree itself as closed.
  is_open = false
  local count_before = #vim.api.nvim_list_wins()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= tree_win then pcall(vim.api.nvim_win_close, w, true) end
  end
  vim.wait(200, function()
    return false
  end, 20)
  local count_after = #vim.api.nvim_list_wins()
  check(
    "layout_guard: no-op when the adapter reports the tree as closed",
    count_after <= count_before
  )

  lg.teardown()
  vim.cmd("silent! only")
end

-- ── compare.diff ── side-by-side file diff, no external process ────────────
do
  local diff = require("filetree.features.compare.diff")
  local marks = require("filetree.features.org.marks")

  local tmp = (TMP_ROOT .. "/gaps-diff"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local file_a = tmp .. "/a.txt"
  local file_b = tmp .. "/b.txt"
  local file_c = tmp .. "/c.txt"
  vim.fn.writefile({ "one", "two" }, file_a)
  vim.fn.writefile({ "one", "three" }, file_b)
  vim.fn.writefile({ "one", "four" }, file_c)

  eq("diff.staged(): nothing staged initially", diff.staged(), nil)

  diff.stage(tmp .. "/does-not-exist.txt")
  eq("diff.stage(): an unreadable path is never staged", diff.staged(), nil)

  diff.stage(file_a)
  eq("diff.stage(): records the staged path", diff.staged(), file_a)

  diff.clear_stage()
  eq("diff.diff(): with nothing staged, reports false", diff.diff(file_b), false)

  diff.stage(file_a)
  local ok = diff.diff(file_b)
  check("diff.diff(): opens successfully for two readable files", ok)
  eq("diff.diff(): clears the stage once the diff opened", diff.staged(), nil)
  check(
    "diff.diff(): the resulting window is in diff mode",
    vim.wo[vim.api.nvim_get_current_win()].diff
  )
  diff.close()
  check("diff.close(): turns diff mode back off", not vim.wo[vim.api.nvim_get_current_win()].diff)

  -- diff_marked(): needs exactly two marks.
  marks.clear_all()
  check("diff.diff_marked(): fewer than 2 marks fails", diff.diff_marked() == false)
  marks.toggle(file_a)
  marks.toggle(file_b)
  eq("diff_marked setup: exactly two marks staged", marks.count(), 2)
  local ok2 = diff.diff_marked()
  check("diff.diff_marked(): opens the diff for exactly 2 marks", ok2)
  eq("diff.diff_marked(): clears the marks it consumed", marks.count(), 0)
  diff.close()

  marks.toggle(file_a)
  marks.toggle(file_b)
  marks.toggle(file_c)
  check(
    "diff.diff_marked(): three marks is refused, not silently narrowed to two",
    diff.diff_marked() == false
  )
  marks.clear_all()

  vim.cmd("silent! only")
end

-- ── lsp.lsp_diagnostics ── severity aggregation + per-node rendering ───────
-- No subprocess: vim.diagnostic is Neovim's own built-in API.
do
  local lspdiag = require("filetree.features.lsp.lsp_diagnostics")
  local tmp = (TMP_ROOT .. "/gaps-lspdiag"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp .. "/sub", "p")
  local file1 = tmp .. "/a.lua"
  local file2 = tmp .. "/sub/b.lua"
  vim.fn.writefile({ "-- a" }, file1)
  vim.fn.writefile({ "-- b" }, file2)

  vim.cmd("edit " .. vim.fn.fnameescape(file1))
  local buf1 = vim.api.nvim_get_current_buf()
  vim.cmd("edit " .. vim.fn.fnameescape(file2))
  local buf2 = vim.api.nvim_get_current_buf()

  local diag_ns = vim.api.nvim_create_namespace("gaps_lspdiag_test")
  vim.diagnostic.set(diag_ns, buf1, {
    { lnum = 0, col = 0, message = "err1", severity = vim.diagnostic.severity.ERROR },
  })
  vim.diagnostic.set(diag_ns, buf2, {
    { lnum = 0, col = 0, message = "warn1", severity = vim.diagnostic.severity.WARN },
    { lnum = 0, col = 0, message = "warn2", severity = vim.diagnostic.severity.WARN },
  })

  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(tree_buf, 0, -1, false, { "a.lua", "sub/b.lua", "sub" })
  local NODE_AT = {
    [0] = { path = file1, type = "file" },
    [1] = { path = file2, type = "file" },
    [2] = { path = tmp .. "/sub", type = "directory" },
  }
  local stub = {
    name = "gaps-lspdiag-stub",
    get_bufnr = function()
      return tree_buf
    end,
    get_node_at_line = function(_, linenr)
      return NODE_AT[linenr]
    end,
  }

  local function extmarks_of(line)
    return vim.api.nvim_buf_get_extmarks(
      tree_buf,
      -1,
      { line, 0 },
      { line, -1 },
      { details = true }
    )
  end

  lspdiag.setup({ enabled = true, debounce_ms = 10 }, stub)
  local ok_wait = vim.wait(2000, function()
    return #extmarks_of(0) > 0 or #extmarks_of(1) > 0
  end, 20)
  check("lsp_diagnostics: the initial deferred render populated the tree buffer", ok_wait)

  local m1 = extmarks_of(0)
  check("lsp_diagnostics: file1's error count rendered on its own line", #m1 > 0)
  if #m1 > 0 then
    check(
      "lsp_diagnostics: file1 shows E:1 (one error)",
      m1[1][4].virt_text[1][1]:find("E:1", 1, true) ~= nil
    )
  end

  local m2 = extmarks_of(1)
  check("lsp_diagnostics: file2's warning count rendered on its own line", #m2 > 0)
  if #m2 > 0 then
    check(
      "lsp_diagnostics: file2 shows W:2 (two warnings)",
      m2[1][4].virt_text[1][1]:find("W:2", 1, true) ~= nil
    )
  end

  local m3 = extmarks_of(2)
  check("lsp_diagnostics: a directory node AGGREGATES its children's counts", #m3 > 0)
  if #m3 > 0 then
    check(
      "lsp_diagnostics: the 'sub' directory shows the same W:2 its child carries",
      m3[1][4].virt_text[1][1]:find("W:2", 1, true) ~= nil
    )
  end

  lspdiag.teardown()
  vim.diagnostic.reset(diag_ns)
  pcall(vim.api.nvim_buf_delete, buf1, { force = true })
  pcall(vim.api.nvim_buf_delete, buf2, { force = true })
  pcall(vim.api.nvim_buf_delete, tree_buf, { force = true })
end

-- ── git.git_status ── porcelain parsing, no real git process ────────────────
do
  local orig_system = vim.system
  local captured_argv
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, _opts, on_done)
    captured_argv = cmd
    local stdout = table.concat({
      "M  modified.lua",
      "A  added.lua",
      "D  deleted.lua",
      "?? untracked.lua",
      "!! ignored.lua",
      "UU conflict.lua",
      'R  "old name.lua" -> "new name.lua"',
    }, "\n") .. "\n"
    vim.schedule(function()
      on_done({ code = 0, stdout = stdout, stderr = "" })
    end)
    return { wait = function() end }
  end

  local gitstat = require("filetree.features.git.git_status")
  local tmp = (TMP_ROOT .. "/gaps-gitstatus"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp .. "/.git", "p")

  local tree_buf = vim.api.nvim_create_buf(false, true)
  local NODE_AT = {
    [0] = { path = tmp .. "/modified.lua" },
    [1] = { path = tmp .. "/added.lua" },
    [2] = { path = tmp .. "/deleted.lua" },
    [3] = { path = tmp .. "/untracked.lua" },
    [4] = { path = tmp .. "/ignored.lua" },
    [5] = { path = tmp .. "/conflict.lua" },
    [6] = { path = tmp .. "/new name.lua" },
  }
  vim.api.nvim_buf_set_lines(tree_buf, 0, -1, false, {
    "modified.lua",
    "added.lua",
    "deleted.lua",
    "untracked.lua",
    "ignored.lua",
    "conflict.lua",
    "new name.lua",
  })
  local stub = {
    name = "gaps-gitstatus-stub",
    get_bufnr = function()
      return tree_buf
    end,
    get_node_at_line = function(_, linenr)
      return NODE_AT[linenr]
    end,
  }

  gitstat.setup({ enabled = true, debounce_ms = 10, show_ignored = true }, stub)

  -- util.root.find() (which M.refresh() uses to locate the git root) prefers
  -- the CURRENT BUFFER's path over cwd -- chdir() alone is not enough while
  -- some earlier section's buffer (elsewhere entirely) is still focused.
  local anchor = tmp .. "/anchor.lua"
  vim.fn.writefile({ "-- anchor" }, anchor)
  vim.cmd("edit " .. vim.fn.fnameescape(anchor))
  local anchor_buf = vim.api.nvim_get_current_buf()

  local prev_cwd = vim.fn.getcwd()
  vim.fn.chdir(tmp)
  gitstat.refresh()
  vim.fn.chdir(prev_cwd)

  check(
    "git_status: ran `git status --porcelain -u` with a -C root",
    captured_argv ~= nil
      and captured_argv[1] == "git"
      and captured_argv[2] == "-C"
      and type(captured_argv[3]) == "string"
  )
  if captured_argv then
    check(
      "git_status: --ignored is added when show_ignored=true",
      vim.tbl_contains(captured_argv, "--ignored")
    )
  end

  local function extmarks_of(line)
    return vim.api.nvim_buf_get_extmarks(
      tree_buf,
      -1,
      { line, 0 },
      { line, -1 },
      { details = true }
    )
  end
  local ok_wait = vim.wait(1000, function()
    return #extmarks_of(0) > 0
  end, 10)
  check("git_status: rendered something for the modified file", ok_wait)

  local function sign_of(line)
    local m = extmarks_of(line)
    if #m == 0 then return nil end
    return m[1][4].virt_text[1][1]
  end

  eq("git_status: 'M ' parses as modified", sign_of(0), " ●")
  eq("git_status: 'A ' parses as added", sign_of(1), " +")
  eq("git_status: 'D ' parses as deleted", sign_of(2), " -")
  eq("git_status: '??' parses as untracked", sign_of(3), " ?")
  eq("git_status: '!!' parses as ignored", sign_of(4), " ·")
  eq("git_status: 'UU' parses as conflict", sign_of(5), " ✗")
  eq(
    "git_status: a rename line ('old' -> 'new') keys the status by the NEW name",
    sign_of(6),
    " »"
  )

  gitstat.teardown()
  pcall(vim.api.nvim_buf_delete, tree_buf, { force = true })
  pcall(vim.api.nvim_buf_delete, anchor_buf, { force = true })
  vim.system = orig_system
end

-- ── filetree.health ── composer pre-flight must not crash when lib.nvim's ───
-- command-layer module is unavailable. `health.check()` already reports that
-- exact condition gracefully via `vim.health.error()` near the top of the
-- function (checked with the same pcall) -- this pins that the FINAL
-- unguarded `require(...).checkhealth(...)` call this round found and fixed
-- (see health.lua) stays fixed: a health check crashing is worse than
-- useless, since it hides every other section's report below it too. This
-- "dependency missing" branch calling unconditionally into the missing
-- dependency has now been found in three repos across this campaign.
do
  local modname = "lib.nvim.bindings.usercmd.composer"
  local prev_loaded = package.loaded[modname]
  package.loaded[modname] = nil
  package.preload[modname] = function()
    error("simulated: " .. modname .. " unavailable")
  end

  package.loaded["filetree.health"] = nil
  local health = require("filetree.health")
  local ok_call = pcall(health.check)

  package.preload[modname] = nil
  package.loaded[modname] = prev_loaded

  check("health.check(): does not throw when lib.nvim's composer module is unavailable", ok_call)
end

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nfiletree.nvim gaps: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
