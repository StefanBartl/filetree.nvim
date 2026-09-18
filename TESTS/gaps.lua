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

  -- BUG (test isolation, found while adding round 27's coverage below): if
  -- "filetree" (the top-level module) had never been `require()`d before this
  -- point in the process, `health.check()`'s own `pcall(require, "filetree")`
  -- -- reached while composer is deliberately broken above -- is the FIRST
  -- load attempt. That pcall swallows the failure fine, but Lua's module
  -- loader permanently caches "filetree" (and "filetree.commands", which
  -- requires composer unconditionally -- see commands.lua's own header) as
  -- `false`, so every LATER `require("filetree")` in this same process fails
  -- with "loop or previous error loading module" even once composer is
  -- restored above. Clearing the cache entries for the two modules this
  -- specifically poisons lets a later section load them fresh.
  package.loaded["filetree"] = nil
  package.loaded["filetree.commands"] = nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Round 27 (follow-up to round 26's gap pass): the files round 26 explicitly
-- deferred rather than reached -- see TESTS/README.md's "gaps.lua" section for
-- the up-to-date list. Same framework, same rtp/TMP_ROOT setup as above.
-- ═══════════════════════════════════════════════════════════════════════════

---@internal
---Replace special keys with their real codes, for nvim_feedkeys.
---@param s string
---@return string
local function keys(s)
  return vim.api.nvim_replace_termcodes(s, true, false, true)
end

---@internal
---Register `stub` as the active adapter and run a real, top-level
---`filetree.setup()` with exactly the given feature config, then create a
---real scratch buffer, make it current, and give it a tree filetype -- which
---fires a real `FileType` autocmd and drives `tree_attach`'s dispatch. Used by
---every feature below whose actual behaviour lives behind a keymap or an
---autocmd registered through `tree_attach`/`bufevents`, rather than an
---exported `M.xxx` function.
---@param stub table
---@param features table
---@return integer buf, integer win
local function setup_tree_buffer(stub, features)
  vim.cmd("silent! only")
  features.no_name_guard = features.no_name_guard or { enabled = false }
  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({ adapter = stub.name, features = features })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  local win = vim.api.nvim_get_current_win()
  vim.bo[buf].filetype = "neo-tree"
  vim.wait(300, function()
    return false
  end)
  return buf, win
end

-- ── infra.file_watcher ── libuv fs_event watch + debounced adapter.refresh ──
do
  local fw = require("filetree.features.infra.file_watcher")
  local watch_dir = (TMP_ROOT .. "/gaps27-filewatcher"):gsub("\\", "/")
  vim.fn.delete(watch_dir, "rf")
  vim.fn.mkdir(watch_dir, "p")

  local refresh_count = 0
  local stub = {
    name = "gaps27-filewatcher-stub",
    refresh = function()
      refresh_count = refresh_count + 1
    end,
  }

  fw.setup({ enabled = true, debounce_ms = 20, watch_recursive = true }, stub)

  fw.enter(watch_dir)
  check("file_watcher.enter(): is_active() true after watching a real directory", fw.is_active())
  eq("file_watcher.watched_path(): records the watched directory", fw.watched_path(), watch_dir)

  -- A real filesystem change inside the watched directory fires the
  -- debounced refresh -- real libuv fs_event, no stub.
  vim.fn.writefile({ "x" }, watch_dir .. "/new.txt")
  local ok_wait = vim.wait(2000, function()
    return refresh_count > 0
  end, 20)
  check("file_watcher: a real fs change triggers a debounced adapter.refresh()", ok_wait)

  fw.exit()
  check("file_watcher.exit(): is_active() false after exit", not fw.is_active())
  eq("file_watcher.exit(): watched_path() cleared", fw.watched_path(), nil)

  -- A non-existent path is a silent no-op (isdirectory guard), not a crash.
  fw.enter(watch_dir .. "/does-not-exist")
  check("file_watcher.enter(): a non-existent path leaves the watcher inactive", not fw.is_active())

  -- setup() manages its own augroup (del_group then group(name, true)) --
  -- calling it again must not double the DirChanged autocmd. The pattern this
  -- campaign keeps finding is a wrapper reusing a group WITHOUT clearing it.
  fw.setup({ enabled = true, debounce_ms = 20, watch_recursive = true }, stub)
  fw.setup({ enabled = true, debounce_ms = 20, watch_recursive = true }, stub)
  local acmds = vim.api.nvim_get_autocmds({ group = "filetree_file_watcher", event = "DirChanged" })
  eq("file_watcher.setup(): re-setup does not double the DirChanged autocmd", #acmds, 1)

  fw.teardown()
  check("file_watcher.teardown(): is_active() false", not fw.is_active())
end

-- ── nav.auto_reveal ── follow the current buffer in the tree, root-scoped ──
do
  local ar = require("filetree.features.nav.auto_reveal")
  local root_dir = (TMP_ROOT .. "/gaps27-autoreveal"):gsub("\\", "/")
  vim.fn.delete(root_dir, "rf")
  vim.fn.mkdir(root_dir .. "/inside", "p")
  local inside_file = root_dir .. "/inside/a.lua"
  vim.fn.writefile({ "x" }, inside_file)
  local outside_dir = vim.fn.fnamemodify(root_dir, ":h") .. "/gaps27-autoreveal-outside"
  vim.fn.mkdir(outside_dir, "p")
  local outside_file = outside_dir .. "/b.lua"
  vim.fn.writefile({ "x" }, outside_file)

  local open_reveal_calls = {}
  local tree_win_valid = true
  local tree_win
  local stub = setmetatable({
    name = "gaps27-autoreveal-stub",
    get_winid = function()
      return tree_win_valid and tree_win or -1
    end,
    get_node_line = function()
      return nil
    end, -- force the "slow path" every time
    get_root_path = function()
      return root_dir
    end,
    open_reveal = function(path)
      open_reveal_calls[#open_reveal_calls + 1] = path
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  })

  vim.cmd("silent! only")
  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.cmd("botright vsplit")
  vim.api.nvim_set_current_buf(tree_buf)
  tree_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd p")
  local editor_win = vim.api.nvim_get_current_win()

  ar.setup({ enabled = true, debounce_ms = 10, only_if_open = true }, stub)

  eq("auto_reveal: not paused right after setup", ar.is_paused(), false)
  ar.pause(50)
  check("auto_reveal.pause(): is_paused() true immediately after pause()", ar.is_paused())
  vim.wait(500, function()
    return not ar.is_paused()
  end, 10)
  check("auto_reveal.pause(): is_paused() false again once the window elapses", not ar.is_paused())

  vim.cmd("edit " .. vim.fn.fnameescape(inside_file))
  ar.reveal_current()
  eq(
    "auto_reveal.reveal_current(): a file under the tree's current root triggers open_reveal()",
    open_reveal_calls[1],
    inside_file
  )

  open_reveal_calls = {}
  vim.cmd("edit " .. vim.fn.fnameescape(outside_file))
  ar.reveal_current()
  eq(
    "auto_reveal.reveal_current(): a file OUTSIDE the tree's current root is silently skipped",
    #open_reveal_calls,
    0
  )

  -- Windows-separator robustness of under_root(): the adapter's root comes
  -- back with native backslashes (as a real Windows adapter might report),
  -- while the buffer path (from nvim_buf_get_name) uses forward slashes.
  open_reveal_calls = {}
  stub.get_root_path = function()
    return root_dir:gsub("/", "\\")
  end
  vim.cmd("edit " .. vim.fn.fnameescape(inside_file))
  ar.reveal_current()
  eq(
    "auto_reveal.under_root(): a backslash-spelled root still recognizes a forward-slash file path as inside it",
    open_reveal_calls[1],
    inside_file
  )
  stub.get_root_path = function()
    return root_dir
  end

  -- cursor_in_tree guard: the tree window itself shows the file (loaded into
  -- it directly) and is the current window -- even a forced reveal_current()
  -- must not call open_reveal, or leaving the tree would immediately drag the
  -- cursor away from wherever the user just navigated to (see the module's
  -- own header on why this guard exists at all).
  open_reveal_calls = {}
  local inside_buf = vim.fn.bufadd(inside_file)
  vim.fn.bufload(inside_buf)
  vim.api.nvim_win_set_buf(tree_win, inside_buf)
  vim.api.nvim_set_current_win(tree_win)
  ar.reveal_current()
  eq(
    "auto_reveal.reveal_current(): refuses when the cursor is in the tree window itself",
    #open_reveal_calls,
    0
  )
  vim.api.nvim_set_current_win(editor_win)

  -- only_if_open=true: the adapter reporting the tree as closed refuses too.
  open_reveal_calls = {}
  tree_win_valid = false
  vim.cmd("edit " .. vim.fn.fnameescape(inside_file))
  ar.reveal_current()
  eq(
    "auto_reveal: only_if_open=true refuses when the adapter reports the tree as closed",
    #open_reveal_calls,
    0
  )
  tree_win_valid = true

  ar.teardown()
  vim.cmd("silent! only")
end

-- ── nav.buffer_cycle ── <C-n>/<C-p> cycle the ADJACENT editor window ────────
do
  local bc = require("filetree.features.nav.buffer_cycle")
  vim.cmd("silent! only")

  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(tree_buf)
  local tree_win = vim.api.nvim_get_current_win()

  vim.cmd("botright vsplit")
  local editor_win = vim.api.nvim_get_current_win()
  local tmp = (TMP_ROOT .. "/gaps27-buffercycle"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  vim.fn.writefile({ "a" }, tmp .. "/a.txt")
  vim.fn.writefile({ "b" }, tmp .. "/b.txt")
  vim.cmd("edit " .. vim.fn.fnameescape(tmp .. "/a.txt"))
  vim.cmd("edit " .. vim.fn.fnameescape(tmp .. "/b.txt"))
  -- editor_win's buffer list is now a.txt, b.txt (current = b.txt).

  vim.api.nvim_set_current_win(tree_win)
  bc.setup({ enabled = true }, nil)

  bc.prev()
  eq(
    "buffer_cycle.prev(): the ADJACENT editor window cycled back to a.txt",
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor_win)), ":t"),
    "a.txt"
  )
  eq(
    "buffer_cycle.prev(): focus stayed in the tree window",
    vim.api.nvim_get_current_win(),
    tree_win
  )

  bc.next()
  eq(
    "buffer_cycle.next(): cycles the adjacent window forward again to b.txt",
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor_win)), ":t"),
    "b.txt"
  )
  eq(
    "buffer_cycle.next(): focus stayed in the tree window",
    vim.api.nvim_get_current_win(),
    tree_win
  )

  vim.cmd("only")
  vim.api.nvim_set_current_buf(tree_buf)
  local warned = false
  local orig_notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    if tostring(msg):find("No editor window", 1, true) then warned = true end
  end
  bc.next()
  vim.notify = orig_notify
  check("buffer_cycle: with no adjacent editor window, warns instead of erroring", warned)

  bc.teardown()
  vim.cmd("silent! only")
end

-- ── nav.reveal_alt ── `B` reveals the alternate buffer (`#`) in the tree ────
do
  local tmp = (TMP_ROOT .. "/gaps27-revealalt"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp, "p")
  local alt_file = tmp .. "/alt.txt"
  vim.fn.writefile({ "alt" }, alt_file)

  local reveal_calls = {}
  local stub = setmetatable({
    name = "gaps27-revealalt-stub",
    is_available = function()
      return true
    end,
    open_reveal = function(path)
      reveal_calls[#reveal_calls + 1] = path
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  })

  -- Real alternate-file ('#') bookkeeping needs a genuine buffer switch in
  -- the SAME window -- edited BEFORE the tree buffer becomes current, since
  -- `:edit {file}` silently RECYCLES the current buffer's number when it is
  -- empty/unnamed/unmodified (exactly what a fresh scratch tree buffer is);
  -- doing it the other way round would wipe the tree buffer's own just-bound
  -- keymaps the moment a second file is edited in the same window.
  vim.cmd("edit " .. vim.fn.fnameescape(alt_file))

  local tree_buf, _ = setup_tree_buffer(stub, {
    reveal_alt = { enabled = true, keymap = "B" },
  })
  -- setup_tree_buffer() switched into tree_buf via the low-level API (not
  -- :edit, so no reuse-trap), leaving alt_file's buffer as '#' for this window.

  local km = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(tree_buf, "n")) do
    km[m.lhs] = m
  end
  check("reveal_alt: 'B' bound on the tree buffer", km["B"] ~= nil and km["B"].callback ~= nil)
  km["B"].callback()
  eq(
    "reveal_alt: open_reveal() called with the alternate buffer's real path",
    reveal_calls[1],
    alt_file
  )

  -- The alternate resolves to a real path, but the file vanished meanwhile --
  -- filereadable() must catch it before open_reveal is ever called. Switched
  -- in via bufadd()+:buffer (existing buffer numbers, no new-buffer-reuse
  -- heuristic) rather than :edit, for the same reason as above -- tree_buf is
  -- current and still empty/unnamed/unmodified at this point.
  local gone_file = tmp .. "/gone.txt"
  vim.fn.writefile({ "x" }, gone_file)
  local gone_buf = vim.fn.bufadd(gone_file)
  vim.fn.bufload(gone_buf)
  vim.cmd("buffer " .. gone_buf)
  vim.cmd("buffer " .. tree_buf)
  vim.fn.delete(gone_file)

  reveal_calls = {}
  local warned = false
  local orig_notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    if tostring(msg):find("not a readable file", 1, true) then warned = true end
  end
  km["B"].callback()
  vim.notify = orig_notify
  check("reveal_alt: an alternate whose file vanished warns instead of calling open_reveal", warned)
  eq("reveal_alt: open_reveal was NOT called for an unreadable alternate", #reveal_calls, 0)

  require("filetree.features.nav.reveal_alt").teardown()
  vim.cmd("silent! only")
end

-- ── nav.tree_traverse ── up/down re-root, filesystem-root guard, cwd_mode ──
do
  local tt = require("filetree.features.nav.tree_traverse")
  local root_dir = (TMP_ROOT .. "/gaps27-treetraverse"):gsub("\\", "/")
  vim.fn.delete(root_dir, "rf")
  vim.fn.mkdir(root_dir .. "/child", "p")

  local current_root = root_dir .. "/child"
  local set_root_calls = {}
  local cur_node
  local stub = setmetatable({
    name = "gaps27-treetraverse-stub",
    get_root_path = function()
      return current_root
    end,
    set_root = function(p)
      set_root_calls[#set_root_calls + 1] = p
      current_root = p
    end,
    get_current_node = function()
      return cur_node
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  })

  tt.setup({ sync_cwd = false }, stub)

  tt.up()
  eq("tree_traverse.up(): set_root() called with the parent directory", set_root_calls[1], root_dir)
  eq("tree_traverse.up(): the adapter's root now reports the parent", current_root, root_dir)

  set_root_calls = {}
  cur_node = { path = root_dir .. "/child", type = "directory" }
  tt.down()
  eq(
    "tree_traverse.down(): set_root() called with the current directory node",
    set_root_calls[1],
    root_dir .. "/child"
  )

  cur_node = { path = root_dir .. "/child/file.txt", type = "file" }
  set_root_calls = {}
  tt.down()
  eq("tree_traverse.down(): a non-directory node is refused (no set_root call)", #set_root_calls, 0)

  -- Filesystem-root guard: fnamemodify(root, ":h") of the OS root returns
  -- itself, and that must stop the traversal rather than looping forever.
  local fs_root = vim.fn.fnamemodify(TMP_ROOT, ":h")
  while vim.fn.fnamemodify(fs_root, ":h") ~= fs_root do
    fs_root = vim.fn.fnamemodify(fs_root, ":h")
  end
  current_root = fs_root
  set_root_calls = {}
  tt.up()
  eq(
    "tree_traverse.up(): already-at-filesystem-root is a no-op (no set_root call)",
    #set_root_calls,
    0
  )

  -- cwd_mode is notified of every manual re-root, so its own cwd lock does
  -- not fight the re-root the user just asked for (see go_to()'s own comment).
  current_root = root_dir .. "/child"
  local notified_paths = {}
  package.loaded["filetree.features.nav.cwd_mode"] = {
    notify_manual_root = function(p)
      notified_paths[#notified_paths + 1] = p
    end,
  }
  set_root_calls = {}
  tt.up()
  eq("tree_traverse.up(): notifies cwd_mode of the new manual root", notified_paths[1], root_dir)
  package.loaded["filetree.features.nav.cwd_mode"] = nil

  tt.teardown()
end

-- ── paths.lua_require_copy ── copy node(s) as require('module.path') ───────
do
  local lrc = require("filetree.features.paths.lua_require_copy")
  local lrc_root = (TMP_ROOT .. "/gaps27-luareqcopy"):gsub("\\", "/")
  vim.fn.delete(lrc_root, "rf")
  vim.fn.mkdir(lrc_root .. "/plugin/lua/myplug/sub", "p")
  vim.fn.writefile({ "return {}" }, lrc_root .. "/plugin/lua/myplug/foo.lua")
  vim.fn.writefile({ "return {}" }, lrc_root .. "/plugin/lua/myplug/sub/bar.lua")
  vim.fn.writefile({ "return {}" }, lrc_root .. "/plugin/lua/myplug/init.lua")
  vim.fn.mkdir(lrc_root .. "/outside", "p")
  vim.fn.writefile({ "x" }, lrc_root .. "/outside/orphan.lua")

  local cur_node
  local stub = {
    name = "gaps27-luareqcopy-stub",
    get_current_node = function()
      return cur_node
    end,
  }
  lrc.setup({ enabled = true }, stub)

  vim.fn.setreg("+", "")
  cur_node = { path = lrc_root .. "/plugin/lua/myplug/foo.lua", type = "file" }
  lrc.copy_require()
  eq(
    "copy_require: a single file resolves to its module string",
    vim.fn.getreg("+"),
    "require('myplug.foo')"
  )

  vim.fn.setreg("+", "")
  cur_node = { path = lrc_root .. "/plugin/lua/myplug/init.lua", type = "file" }
  lrc.copy_require()
  eq(
    "copy_require: an init.lua's module string drops the trailing '.init'",
    vim.fn.getreg("+"),
    "require('myplug')"
  )

  vim.fn.setreg("+", "sentinel")
  cur_node = { path = lrc_root .. "/outside/orphan.lua", type = "file" }
  lrc.copy_require()
  eq(
    "copy_require: a node outside any lua/ dir copies nothing (no guessed module)",
    vim.fn.getreg("+"),
    "sentinel"
  )

  vim.fn.setreg("+", "")
  cur_node = { path = lrc_root .. "/plugin/lua/myplug", type = "directory" }
  lrc.copy_require()
  local dir_lines = vim.split(vim.fn.getreg("+"), "\n")
  table.sort(dir_lines)
  eq("copy_require: a directory gathers every .lua file recursively (3 modules)", #dir_lines, 3)
  check(
    "copy_require: directory gather includes the nested sub/bar.lua module",
    vim.tbl_contains(dir_lines, "require('myplug.sub.bar')")
  )

  -- copy_require_relative(): resolves against cwd/lua/ instead of the "/lua/"
  -- substring search -- exercised with the real cwd, whose OWN separator style
  -- on Windows (getcwd() answers with backslashes no matter how :cd was
  -- spelled) must not break the prefix strip.
  local prev_cwd = vim.fn.getcwd()
  vim.cmd("cd " .. vim.fn.fnameescape(lrc_root .. "/plugin"))
  vim.fn.setreg("+", "")
  cur_node = { path = lrc_root .. "/plugin/lua/myplug/foo.lua", type = "file" }
  lrc.copy_require_relative()
  eq(
    "copy_require_relative: resolves relative to cwd/lua/ regardless of cwd's own separator style",
    vim.fn.getreg("+"),
    "require('myplug.foo')"
  )
  vim.cmd("cd " .. vim.fn.fnameescape(prev_cwd))

  cur_node = nil
  vim.fn.setreg("+", "sentinel2")
  lrc.copy_require()
  eq(
    "copy_require: no current node is a warned no-op, clipboard untouched",
    vim.fn.getreg("+"),
    "sentinel2"
  )

  lrc.teardown()
end

-- ── search.filter ── native backend filter, falls back to extmark dimming ──
do
  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(tree_buf, 0, -1, false, { "foo.lua", "bar.lua", "readme.md" })
  local nodes = { { name = "foo.lua" }, { name = "bar.lua" }, { name = "readme.md" } }
  local stub = setmetatable({
    -- Neither "neotree" nor "nvimtree": try_native_filter must fall through
    -- cleanly to dimming with no real tree backend installed.
    name = "gaps27-filter-stub",
    get_bufnr = function()
      return tree_buf
    end,
    get_node_at_line = function(_, linenr)
      return nodes[linenr + 1]
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  })

  local filt = require("filetree.features.search.filter")
  filt.setup({ enabled = true }, stub)

  filt.apply("bar")
  local ns = vim.api.nvim_get_namespaces()["filetree_filter"]
  local dimmed = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(tree_buf, ns, 0, -1, {})) do
    dimmed[m[2]] = true
  end
  check("filter.apply(): the matching line ('bar.lua', line 1) is NOT dimmed", not dimmed[1])
  check("filter.apply(): a non-matching line ('foo.lua', line 0) IS dimmed", dimmed[0])
  check("filter.apply(): a non-matching line ('readme.md', line 2) IS dimmed", dimmed[2])

  filt.clear()
  eq(
    "filter.clear(): every dimming extmark removed",
    #vim.api.nvim_buf_get_extmarks(tree_buf, ns, 0, -1, {}),
    0
  )

  -- adapter.name == "neotree" tries the real backend module first; with
  -- neo-tree not on this suite's runtimepath, that pcall(require, ...)
  -- genuinely fails, and the code must fall back to dimming rather than
  -- silently doing nothing (the exact regression its own header documents).
  stub.name = "neotree"
  filt.apply("bar")
  check(
    "filter.apply(): adapter.name='neotree' without neo-tree installed still falls back to dimming",
    #vim.api.nvim_buf_get_extmarks(tree_buf, ns, 0, -1, {}) > 0
  )
  stub.name = "gaps27-filter-stub"
  filt.clear()

  -- enter(): the floating query input, stubbed the same way this campaign
  -- stubs ui.kit elsewhere (smart_rename's kit.input, etc.) rather than
  -- driving a real floating window.
  package.loaded["ui.kit"] = {
    live_input = function(opts)
      opts.on_change("foo")
      return {
        is_valid = function()
          return true
        end,
        focus = function() end,
        on_close = function() end,
        close = function() end,
      }
    end,
  }
  package.loaded["filetree.features.search.filter"] = nil
  filt = require("filetree.features.search.filter")
  filt.setup({ enabled = true }, stub)
  filt.enter()
  local dimmed2 = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(tree_buf, ns, 0, -1, {})) do
    dimmed2[m[2]] = true
  end
  check(
    "filter.enter(): on_change('foo') from the live input dims every non-matching line",
    dimmed2[1] and dimmed2[2]
  )
  check("filter.enter(): 'foo.lua' (the match) stays undimmed", not dimmed2[0])

  package.loaded["ui.kit"] = nil
  package.loaded["filetree.features.search.filter"] = nil
  filt.teardown()
  pcall(vim.api.nvim_buf_delete, tree_buf, { force = true })
end

-- ── search.live_search ── incremental highlight/dim overlay over visible nodes ─
do
  vim.cmd("silent! only")
  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(tree_buf, 0, -1, false, { "l1", "l2", "l3" })
  vim.api.nvim_win_set_buf(0, tree_buf)
  local tree_win = vim.api.nvim_get_current_win()

  local vis_nodes = {
    { path = "/proj/foo.lua", line_number = 1 },
    { path = "/proj/bar.lua", line_number = 2 },
    { path = "/proj/sub/bar.lua", line_number = 3 },
  }
  local stub = setmetatable({
    name = "gaps27-livesearch-stub",
    get_winid = function()
      return tree_win
    end,
    get_bufnr = function()
      return tree_buf
    end,
    get_visible_nodes = function()
      return vis_nodes
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  })

  ---@internal Reload live_search after (re-)stubbing ui.kit -- its `kit`
  ---local is captured at module-load time, same reason the smart_rename
  ---suite reloads its feature module after stubbing ui.kit.
  local function reload_live_search(kit_stub)
    package.loaded["ui.kit"] = kit_stub
    package.loaded["filetree.features.search.live_search"] = nil
    return require("filetree.features.search.live_search")
  end

  local ls = reload_live_search({
    live_input = function(opts)
      opts.on_change("bar")
      return nil
    end,
  })
  ls.setup({ enabled = true, match = "name" }, stub)
  ls.open()

  local ns = vim.api.nvim_get_namespaces()["filetree_live_search"]
  local function hl_of(line)
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(tree_buf, ns, 0, -1, { details = true })) do
      if m[2] == line then return m[4].line_hl_group end
    end
    return nil
  end
  eq("live_search: 'bar.lua' (line 2) highlighted as a match", hl_of(1), "Search")
  eq(
    "live_search: 'sub/bar.lua' (line 3) matches by filename too, not full path",
    hl_of(2),
    "Search"
  )
  eq("live_search: 'foo.lua' (line 1) dimmed as a non-match", hl_of(0), "Comment")

  ls.clear()
  eq(
    "live_search.clear(): overlay removed",
    #vim.api.nvim_buf_get_extmarks(tree_buf, ns, 0, -1, {}),
    0
  )

  -- match = "path": now the query must hit the full path, not just the tail.
  ls = reload_live_search({
    live_input = function(opts)
      opts.on_change("sub")
      return nil
    end,
  })
  ls.setup({ enabled = true, match = "path" }, stub)
  ls.open()
  eq(
    "live_search match='path': only the node whose full PATH contains the query matches",
    hl_of(2),
    "Search"
  )
  eq(
    "live_search match='path': a name-only hit elsewhere in the tree does not count for siblings",
    hl_of(0),
    "Comment"
  )

  -- commit_to_filter: <CR> pushes the pattern into the filter feature.
  package.loaded["filetree.features.search.filter"] = {
    apply = function(q)
      _G.__gaps27_committed_filter_query = q
    end,
  }
  ls = reload_live_search({
    live_input = function(opts)
      opts.on_submit("committed-query")
      return nil
    end,
  })
  ls.setup({ enabled = true, commit_to_filter = true }, stub)
  ls.open()
  eq(
    "live_search: <CR> commits the query to the filter feature via commit_to_filter",
    _G.__gaps27_committed_filter_query,
    "committed-query"
  )
  _G.__gaps27_committed_filter_query = nil
  package.loaded["filetree.features.search.filter"] = nil

  package.loaded["ui.kit"] = nil
  package.loaded["filetree.features.search.live_search"] = nil
  ls.teardown()
  pcall(vim.api.nvim_buf_delete, tree_buf, { force = true })
  vim.cmd("silent! only")
end

-- ── ui.window_style ── blank statusline + highlight isolation in tree wins ──
do
  local stub = setmetatable({
    name = "gaps27-windowstyle-stub",
    is_available = function()
      return true
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  })

  local tree_buf, tree_win = setup_tree_buffer(stub, {
    window_style = { enabled = true, statusline = true, highlights_isolate = true },
  })

  eq("window_style: the tree window's statusline is blanked", vim.wo[tree_win].statusline, " ")

  -- Fallback re-application: BufWinEnter/WinEnter re-assert it even after
  -- another plugin overwrote it.
  vim.wo[tree_win].statusline = "clobbered"
  vim.api.nvim_exec_autocmds("WinEnter", {})
  local ok_wait = vim.wait(500, function()
    return vim.wo[tree_win].statusline == " "
  end, 10)
  check(
    "window_style: WinEnter re-asserts the blanked statusline after it was overwritten",
    ok_wait
  )

  -- highlights_isolate: the default superset links NeoTreeNormal -> Normal.
  local hl = vim.api.nvim_get_hl(0, { name = "NeoTreeNormal" })
  eq("window_style: highlights_isolate links NeoTreeNormal -> Normal by default", hl.link, "Normal")

  -- A ColorScheme change re-isolates it.
  vim.api.nvim_set_hl(0, "NeoTreeNormal", { link = "ErrorMsg" })
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  local ok_wait2 = vim.wait(500, function()
    return vim.api.nvim_get_hl(0, { name = "NeoTreeNormal" }).link == "Normal"
  end, 10)
  check("window_style: a ColorScheme change re-isolates the highlight link", ok_wait2)

  -- An adapter-declared filetypes/hl_groups table replaces the DEFAULT superset.
  stub.filetypes = { "mytree" }
  stub.hl_groups = { MyTreeNormal = "Normal" }
  require("filetree").setup({
    adapter = "gaps27-windowstyle-stub",
    features = {
      window_style = { enabled = true, statusline = true, highlights_isolate = true },
      no_name_guard = { enabled = false },
    },
  })
  vim.wait(300, function()
    return false
  end)
  eq(
    "window_style: an adapter-declared hl_groups table is used instead of the default superset",
    vim.api.nvim_get_hl(0, { name = "MyTreeNormal" }).link,
    "Normal"
  )
  vim.bo[tree_buf].filetype = "mytree"
  vim.wait(300, function()
    return false
  end)
  eq(
    "window_style: an adapter-declared filetypes list is used for the statusline target too",
    vim.wo[tree_win].statusline,
    " "
  )

  require("filetree.features.ui.window_style").teardown()
  vim.cmd("silent! only")
end

-- ── ui.window_size_cycler ── cycle the tree window width through presets ───
do
  vim.cmd("silent! only")
  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(tree_buf)
  local tree_win = vim.api.nvim_get_current_win()
  -- A sole window fills the whole tabpage and CANNOT be resized (there is no
  -- sibling column to take space from/give it to) -- a real sibling split is
  -- required for nvim_win_set_width to have any visible effect at all.
  vim.cmd("botright vsplit")
  vim.api.nvim_set_current_win(tree_win)

  local stub = setmetatable({
    name = "gaps27-wsc-stub",
    is_available = function()
      return true
    end,
    get_winid = function()
      return tree_win
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({
    adapter = "gaps27-wsc-stub",
    features = {
      window_size_cycler = { enabled = true, sizes = { 30, 50, 15 }, keymap = "w" },
      no_name_guard = { enabled = false },
    },
  })
  vim.bo[tree_buf].filetype = "neo-tree"
  vim.wait(300, function()
    return false
  end)

  -- setup() started the cycle at the preset nearest the window's width at
  -- that moment (a brand-new scratch window, not necessarily one of the
  -- presets) -- the first press always advances one step from there, so pin
  -- the state with one throwaway press before asserting the transitions.
  vim.api.nvim_feedkeys(keys("w"), "x", false)
  local after_first = vim.api.nvim_win_get_width(tree_win)
  check(
    "window_size_cycler: 'w' sets the window to one of the configured presets",
    after_first == 30 or after_first == 50 or after_first == 15
  )

  vim.api.nvim_feedkeys(keys("w"), "x", false)
  local after_second = vim.api.nvim_win_get_width(tree_win)
  check(
    "window_size_cycler: a second 'w' advances to a DIFFERENT preset",
    after_second ~= after_first
  )

  -- An explicit count jumps directly to preset N (clamped), NOT N steps
  -- forward -- v:count vs v:count1, deliberately, per the module's own header.
  vim.api.nvim_feedkeys(keys("2w"), "x", false)
  eq(
    "window_size_cycler: '2w' jumps directly to preset #2 (50), regardless of the current step",
    vim.api.nvim_win_get_width(tree_win),
    50
  )

  vim.api.nvim_feedkeys(keys("99w"), "x", false)
  eq(
    "window_size_cycler: a count beyond the list clamps to the LAST preset",
    vim.api.nvim_win_get_width(tree_win),
    15
  )

  require("filetree.features.ui.window_size_cycler").teardown()
  vim.cmd("silent! only")
end

-- ── ui.cursor_hide ── hide the block cursor while focus is in the tree ─────
do
  local stub = setmetatable({
    name = "gaps27-cursorhide-stub",
    is_available = function()
      return true
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  })

  local _, tree_win = setup_tree_buffer(stub, {
    cursor_hide = { enabled = true },
  })
  vim.cmd("botright vsplit")
  local editor_win = vim.api.nvim_get_current_win()

  -- Entering the tree window hides the cursor there.
  vim.api.nvim_set_current_win(tree_win)
  local ok_hide = vim.wait(500, function()
    return (vim.wo[tree_win].winhighlight or ""):find("Cursor:FiletreeCursorHidden", 1, true) ~= nil
  end, 10)
  check("cursor_hide: entering the tree window sets Cursor:FiletreeCursorHidden", ok_hide)

  -- Leaving it strips the override again (merge-and-strip, not a wholesale
  -- overwrite -- see the module's own header on why that distinction matters).
  vim.api.nvim_set_current_win(editor_win)
  local ok_show = vim.wait(500, function()
    return not (vim.wo[tree_win].winhighlight or ""):find("Cursor:FiletreeCursorHidden", 1, true)
  end, 10)
  check("cursor_hide: leaving the tree window strips the Cursor override again", ok_show)

  require("filetree.features.ui.cursor_hide").teardown()
  vim.cmd("silent! only")
end

-- ── ui.tree_reset ── one key tears down every transient tree UI state ──────
do
  vim.cmd("silent! only")
  local tree_buf
  local stub = setmetatable({
    name = "gaps27-treereset-stub",
    is_available = function()
      return true
    end,
    get_current_node = function()
      return nil
    end,
    get_bufnr = function()
      return tree_buf
    end,
    get_node_at_line = function()
      return nil
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  })

  local ft = require("filetree")
  ft.register_adapter(stub)
  ft.setup({
    adapter = "gaps27-treereset-stub",
    features = {
      tree_reset = { enabled = true, keymap = "<Esc>" },
      preview = { enabled = true, mode = "float" },
      filter = { enabled = true },
      live_search = { enabled = true },
      watcher_quarantine = { enabled = true, patch_neotree_watch = false },
      no_name_guard = { enabled = false },
    },
  })

  tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(tree_buf)
  vim.bo[tree_buf].filetype = "neo-tree"
  vim.wait(300, function()
    return false
  end)

  require("filetree.features.search.filter").apply("something")
  require("filetree.features.infra.watcher_quarantine").enter()
  check(
    "tree_reset (pre-check): watcher_quarantine is actually active before the reset key",
    require("filetree.features.infra.watcher_quarantine").is_active()
  )

  local km = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(tree_buf, "n")) do
    km[m.lhs] = m
  end
  check(
    "tree_reset: '<Esc>' bound on the tree buffer",
    km["<Esc>"] ~= nil and km["<Esc>"].callback ~= nil
  )
  local ok_call = pcall(km["<Esc>"].callback)
  check("tree_reset: the reset key runs without erroring across every fanned-out feature", ok_call)

  check(
    "tree_reset: exits watcher_quarantine",
    not require("filetree.features.infra.watcher_quarantine").is_active()
  )
  local filt_ns = vim.api.nvim_get_namespaces()["filetree_filter"]
  local filt_marks = filt_ns and vim.api.nvim_buf_get_extmarks(tree_buf, filt_ns, 0, -1, {}) or {}
  eq("tree_reset: clears the filter's dimming extmarks", #filt_marks, 0)
  check(
    "tree_reset: the tree buffer itself is untouched (still valid)",
    vim.api.nvim_buf_is_valid(tree_buf)
  )

  require("filetree.features.ui.tree_reset").teardown()
  vim.cmd("silent! only")
end

-- ── ui.size_info ── file sizes (sync) + directory sizes (stubbed vim.system) ─
do
  local si = require("filetree.features.ui.size_info")
  local tmp = (TMP_ROOT .. "/gaps27-sizeinfo"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp .. "/sub", "p")
  local file_a = tmp .. "/a.txt"
  vim.fn.writefile({ string.rep("x", 100) }, file_a)

  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(tree_buf, 0, -1, false, { "a.txt", "sub" })
  local nodes = {
    [0] = { path = file_a, type = "file" },
    [1] = { path = tmp .. "/sub", type = "directory" },
  }
  local stub = {
    name = "gaps27-sizeinfo-stub",
    get_bufnr = function()
      return tree_buf
    end,
    get_node_at_line = function(_, linenr)
      return nodes[linenr]
    end,
  }

  local fmt = require("lib.lua.strings.format").format_bytes
  local function virt_of(line)
    local ns = vim.api.nvim_get_namespaces()["filetree_size_info"]
    local m = vim.api.nvim_buf_get_extmarks(
      tree_buf,
      ns,
      { line, 0 },
      { line, -1 },
      { details = true }
    )
    if #m == 0 then return nil end
    return m[1][4].virt_text[1][1]
  end

  si.setup({ enabled = true, show_files = true, show_dirs = true, dir_async = false }, stub)
  local real_size = (vim.uv or vim.loop).fs_stat(file_a).size
  eq(
    "size_info: a real file's size renders via lib's format_bytes",
    virt_of(0),
    " " .. fmt(real_size)
  )
  check(
    "size_info: dir_async=false renders nothing for a directory (no du/PowerShell run)",
    virt_of(1) == nil
  )

  -- Async dir size: stub vim.system exactly like this campaign's git_status
  -- suite does, so the real POSIX (`du -sk`) / Windows (PowerShell) branch and
  -- its output parsing run for real, without spawning a process.
  local orig_system = vim.system
  local captured_cmd
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, _opts, on_done)
    captured_cmd = cmd
    local out = (vim.fn.has("win32") == 1) and "4096\r\n" or "4\tsub\n" -- kibibytes, per `du -sk`
    vim.schedule(function()
      on_done({ code = 0, stdout = out, stderr = "" })
    end)
    return { wait = function() end }
  end

  si.setup({ enabled = true, show_files = true, show_dirs = true, dir_async = true }, stub)
  check(
    "size_info: dir_async=true first shows a pending placeholder while the size query is in flight",
    virt_of(1) == " …"
  )
  local ok_wait = vim.wait(1000, function()
    return virt_of(1) ~= nil and virt_of(1) ~= " …"
  end, 10)
  check("size_info: the async directory size eventually renders", ok_wait)
  eq(
    "size_info: 4096 bytes formats via the same lib.lua.strings.format helper",
    virt_of(1),
    " " .. fmt(4096)
  )

  if vim.fn.has("win32") == 1 then
    check(
      "size_info: on Windows the async dir-size command is PowerShell",
      captured_cmd[1] == "powershell"
    )
  else
    check(
      "size_info: on POSIX the async dir-size command is `du -sk`",
      captured_cmd[1] == "du" and captured_cmd[2] == "-sk"
    )
  end

  si.refresh()
  check(
    "size_info.refresh(): clears the cache -- the directory goes back to pending",
    virt_of(1) == " …"
  )

  vim.system = orig_system
  si.teardown()
  pcall(vim.api.nvim_buf_delete, tree_buf, { force = true })
end

-- ── ui.preview ── file/dir preview (float + buffer modes), image/pdf dispatch ─
do
  local preview = require("filetree.features.ui.preview")
  local tmp = (TMP_ROOT .. "/gaps27-preview"):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp .. "/sub", "p")
  local text_file = tmp .. "/note.lua"
  vim.fn.writefile({ "return 1" }, text_file)
  local image_file = tmp .. "/pic.png"
  vim.fn.writefile({ "fake-png-bytes" }, image_file)
  local binary_file = tmp .. "/blob.bin"
  vim.fn.writefile({ "fake-binary-bytes" }, binary_file)

  local cur_node
  local stub = setmetatable({
    name = "gaps27-preview-stub",
    get_current_node = function()
      return cur_node
    end,
  }, {
    __index = function()
      return function()
        return false
      end
    end,
  })

  local function open_float_win()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then return w end
    end
    return nil
  end

  -- ── float mode: a real floating window, no backend needed ────────────────
  preview.setup({
    enabled = true,
    mode = "float",
    max_lines = 10,
    image = { backend = false },
    pdf = { backend = false },
  }, stub)

  cur_node = { path = text_file, type = "file" }
  preview.toggle()
  local float_win = open_float_win()
  check("preview.toggle() [float]: opens a real floating window for a text file", float_win ~= nil)
  eq(
    "preview.toggle() [float]: the float shows the file's real content",
    float_win and vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float_win), 0, -1, false)[1],
    "return 1"
  )

  preview.toggle()
  check("preview.toggle() [float]: a second toggle closes it again", open_float_win() == nil)

  -- Binary content: hex-dumped rather than shown as raw bytes.
  cur_node = { path = binary_file, type = "file" }
  preview.toggle()
  float_win = open_float_win()
  local first_line = float_win
      and vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float_win), 0, 1, false)[1]
    or ""
  check(
    "preview.toggle() [float]: a binary file is hex-dumped, not shown as raw bytes",
    first_line:match("^%x%x") ~= nil
  )
  preview.close()

  -- Directory listing.
  cur_node = { path = tmp, type = "directory" }
  preview.toggle()
  float_win = open_float_win()
  local dir_lines = float_win
      and vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float_win), 0, -1, false)
    or {}
  check(
    "preview.toggle() [float]: a directory node lists its entries",
    vim.tbl_contains(dir_lines, "  /sub")
  )
  preview.close()

  -- image.backend=false: <Tab> falls through to the ordinary preview instead
  -- of dispatching to an image viewer.
  cur_node = { path = image_file, type = "file" }
  preview.toggle_or_open()
  check(
    "preview.toggle_or_open(): image.backend=false falls through to the text/hex preview instead of dispatching",
    open_float_win() ~= nil
  )
  preview.close()

  -- <CR> dispatch: image.backend=false means open_or_fallback calls the
  -- adapter's own fallback instead of trying to open the image.
  local fallback_called = false
  preview.open_or_fallback(function()
    fallback_called = true
  end)
  check(
    "preview.open_or_fallback(): image.backend=false calls the fallback for an image node",
    fallback_called
  )

  preview.teardown()
  vim.cmd("silent! only")

  -- ── buffer mode: shows the file in the ADJACENT editor window ────────────
  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(tree_buf)
  local tree_win = vim.api.nvim_get_current_win()
  vim.cmd("botright vsplit")
  local editor_win = vim.api.nvim_get_current_win()
  vim.fn.writefile({ "original" }, tmp .. "/original.txt")
  vim.cmd("edit " .. vim.fn.fnameescape(tmp .. "/original.txt"))
  vim.api.nvim_set_current_win(tree_win)

  stub.get_winid = function()
    return tree_win
  end
  preview.setup({ enabled = true, mode = "buffer" }, stub)

  cur_node = { path = text_file, type = "file" }
  preview.toggle()
  eq(
    "preview.toggle() [buffer]: the adjacent editor window now shows the previewed file",
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor_win)), ":t"),
    "note.lua"
  )
  eq(
    "preview.toggle() [buffer]: focus stayed in the tree window",
    vim.api.nvim_get_current_win(),
    tree_win
  )

  preview.toggle()
  eq(
    "preview.toggle() [buffer]: toggling off restores the editor window's original buffer",
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor_win)), ":t"),
    "original.txt"
  )

  preview.teardown()
  vim.cmd("silent! only")
end

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\nfiletree.nvim gaps: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
