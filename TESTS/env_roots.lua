---@diagnostic disable: need-check-nil, missing-fields, duplicate-set-field
-- env_roots.lua — headless tests for the named-root layer
-- (`filetree.util.env_roots`, the top-level `env_roots` option) and where it is
-- applied: the util itself (fold / expand / remap), the copied absolute path
-- formats, the file lists, the inserted Markdown link, a created symlink
-- (relative inside one root, absolute across two) and a repair's re-anchoring.
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/env_roots.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)

for _, env in ipairs({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" and vim.fn.isdirectory(v .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(v)
    break
  end
end
for _, c in ipairs({
  vim.fn.fnamemodify(root_dir, ":h") .. "/lib.nvim",
  vim.fn.stdpath("data") .. "/lazy/lib.nvim",
}) do
  if vim.fn.isdirectory(c .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(c)
    break
  end
end
for _, env in ipairs({ "FILETREE_UI_NVIM", "UI_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" and vim.fn.isdirectory(v .. "/lua/ui") == 1 then
    vim.opt.rtp:prepend(v)
    break
  end
end
for _, c in ipairs({
  vim.fn.fnamemodify(root_dir, ":h") .. "/ui.nvim",
  vim.fn.stdpath("data") .. "/lazy/ui.nvim",
}) do
  if vim.fn.isdirectory(c .. "/lua/ui") == 1 then
    vim.opt.rtp:prepend(c)
    break
  end
end

local uv = vim.uv or vim.loop
local TMP_ROOT = vim.env.TEMP or vim.env.TMPDIR or vim.env.TMP or "/tmp"
TMP_ROOT = (uv.fs_realpath(TMP_ROOT) or TMP_ROOT):gsub("\\", "/")

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

local ER = require("filetree.util.env_roots")

---A fresh scratch tree: <tmp>/repos (the `$REPOS_DIR`), <tmp>/notes (a
---user-defined root) and <tmp>/outside (under no root).
---@param name string
---@return string tmp, string repos, string notes, string outside
local function scratch(name)
  local tmp = (TMP_ROOT .. "/envroots-" .. name):gsub("\\", "/")
  vim.fn.delete(tmp, "rf")
  vim.fn.mkdir(tmp .. "/repos/proj/sub", "p")
  vim.fn.mkdir(tmp .. "/repos/other", "p")
  vim.fn.mkdir(tmp .. "/notes/a", "p")
  vim.fn.mkdir(tmp .. "/outside", "p")
  vim.fn.writefile({ "x" }, tmp .. "/repos/proj/sub/file.md")
  vim.fn.writefile({ "x" }, tmp .. "/notes/a/n.md")
  return tmp, tmp .. "/repos", tmp .. "/notes", tmp .. "/outside"
end

local saved_repos = vim.env.REPOS_DIR

-- ── util: fold ────────────────────────────────────────────────────────────────
do
  local tmp, repos, notes, outside = scratch("fold")
  vim.env.REPOS_DIR = repos
  ER.setup({ extra = { NOTES = notes } })

  eq("fold: a path under $REPOS_DIR", (ER.fold(repos .. "/proj/x.lua")), "$REPOS_DIR/proj/x.lua")
  eq("fold: the root itself", (ER.fold(repos)), "$REPOS_DIR")
  eq("fold: a user-defined root", (ER.fold(notes .. "/a/n.md")), "$NOTES/a/n.md")
  eq(
    "fold: $NVIM_CONFIG_DIR needs no environment variable",
    (ER.fold(vim.fn.stdpath("config"):gsub("\\", "/") .. "/lua/x.lua")),
    "$NVIM_CONFIG_DIR/lua/x.lua"
  )
  eq("fold: a path under no root is returned as given", (ER.fold(outside .. "/f")), outside .. "/f")
  eq(
    "fold: a backslash path folds too",
    (ER.fold(((repos .. "/proj/x.lua"):gsub("/", "\\")))),
    "$REPOS_DIR/proj/x.lua"
  )
  eq("fold: the sibling 'repos2' is not under 'repos'", (ER.fold(repos .. "2/x")), repos .. "2/x")
  local _, name = ER.fold(repos .. "/proj")
  eq("fold: second value is the root's name", name, "REPOS_DIR")
  eq("root_of", ER.root_of(notes .. "/a"), "NOTES")

  ER.setup({ nvim_config = false })
  local cfgdir = vim.fn.stdpath("config"):gsub("\\", "/") .. "/lua/x.lua"
  eq("fold: nvim_config = false", (ER.fold(cfgdir)), cfgdir)

  ER.setup({ vars = { "FT_TEST_OTHER" } })
  vim.env.FT_TEST_OTHER = outside
  eq("fold: vars replaces the default list", (ER.fold(outside .. "/f")), "$FT_TEST_OTHER/f")
  eq("fold: ...so $REPOS_DIR is no longer a root", (ER.fold(repos .. "/proj")), repos .. "/proj")
  vim.env.FT_TEST_OTHER = nil
  eq("fold: an unset variable is skipped", (ER.fold(outside .. "/f")), outside .. "/f")

  -- Longest match wins: a root nested in another.
  ER.setup({ extra = { INNER = repos .. "/proj" } })
  eq("fold: the longest root wins", (ER.fold(repos .. "/proj/sub/file.md")), "$INNER/sub/file.md")

  -- extra overrides a variable of the same name.
  ER.setup({ extra = { REPOS_DIR = notes } })
  eq("fold: extra overrides a same-named variable", (ER.fold(notes .. "/a")), "$REPOS_DIR/a")

  -- A function resolver is called fresh each time.
  local calls = 0
  ER.setup({
    extra = {
      FN = function()
        calls = calls + 1
        return outside
      end,
    },
  })
  eq("fold: a function root", (ER.fold(outside .. "/f")), "$FN/f")
  check("fold: the function was called", calls > 0)

  ER.setup({ enable = false })
  eq("enable = false: nothing is folded", (ER.fold(repos .. "/proj")), repos .. "/proj")
  eq(
    "enable = false: ...unless forced",
    (ER.fold(repos .. "/proj", { force = true })),
    "$REPOS_DIR/proj"
  )
  eq("enable = false: enabled()", ER.enabled(), false)
  eq("enable = false: root_of is nil", ER.root_of(repos .. "/proj"), nil)

  ER.setup(nil)
  eq("setup(nil) restores the defaults", (ER.fold(repos .. "/proj")), "$REPOS_DIR/proj")

  vim.fn.delete(tmp, "rf")
end

-- ── util: expand ──────────────────────────────────────────────────────────────
do
  local tmp, repos, notes = scratch("expand")
  vim.env.REPOS_DIR = repos
  ER.setup({ extra = { NOTES = notes } })

  eq("expand: $REPOS_DIR/x", ER.expand("$REPOS_DIR/proj/x"), repos .. "/proj/x")
  eq("expand: ${REPOS_DIR}\\x", ER.expand("${REPOS_DIR}\\proj"), repos .. "\\proj")
  eq("expand: the bare variable", ER.expand("$REPOS_DIR"), repos)
  eq("expand: a user-defined root", ER.expand("$NOTES/a"), notes .. "/a")
  eq(
    "expand: $NVIM_CONFIG_DIR without an environment variable",
    ER.expand("$NVIM_CONFIG_DIR/lua"),
    vim.fn.stdpath("config"):gsub("\\", "/") .. "/lua"
  )
  eq("expand: an unknown variable is left alone", ER.expand("$NOPE_NOT_SET/x"), "$NOPE_NOT_SET/x")
  eq("expand: '$REPOS_DIRX' is another name", ER.expand("$REPOS_DIRX/x"), "$REPOS_DIRX/x")
  eq("expand: a plain path", ER.expand("/a/b"), "/a/b")
  ER.setup({ enable = false })
  eq(
    "expand: works with enable = false (it acts on typed text)",
    ER.expand("$REPOS_DIR/x"),
    repos .. "/x"
  )

  vim.fn.delete(tmp, "rf")
end

-- ── util: remap ───────────────────────────────────────────────────────────────
do
  local tmp, repos, notes = scratch("remap")
  vim.env.REPOS_DIR = repos
  ER.setup({ extra = { NOTES = notes } })

  -- tmp/repos is called "repos": the part after a `repos` segment is looked up under it.
  local hits = ER.remap("Z:/elsewhere/repos/proj/sub/file.md")
  eq("remap: another drive, same root name", hits[1], repos .. "/proj/sub/file.md")
  eq("remap: exactly one candidate", #hits, 1)
  eq(
    "remap: a POSIX-style recorded path",
    ER.remap("/home/me/repos/proj/sub/file.md")[1],
    repos .. "/proj/sub/file.md"
  )
  eq(
    "remap: a backslash recorded path",
    ER.remap([[D:\code\repos\proj\sub\file.md]])[1],
    repos .. "/proj/sub/file.md"
  )
  eq(
    "remap: case-insensitive anchor only on Windows",
    #ER.remap("/h/REPOS/proj/sub/file.md") > 0,
    vim.fn.has("win32") == 1
  )
  eq(
    "remap: a user-defined root's folder name",
    ER.remap("/srv/notes/a/n.md")[1],
    notes .. "/a/n.md"
  )
  eq("remap: nothing that exists", #ER.remap("/h/repos/proj/missing.md"), 0)
  eq("remap: a relative recorded path", #ER.remap("repos/proj/sub/file.md"), 0)
  eq("remap: the path itself is not a candidate", #ER.remap(repos .. "/proj/sub/file.md"), 0)
  ER.setup({ enable = false })
  eq("remap: nothing with enable = false", #ER.remap("/h/repos/proj/sub/file.md"), 0)

  vim.fn.delete(tmp, "rf")
end

-- ── config: the env_roots option ──────────────────────────────────────────────
do
  local config = require("filetree.config")
  config.setup({ env_roots = { enable = false, typo = 1, vars = "not-a-table", nvim_config = 3 } })
  local issues = table.concat(config.issues(), "\n")
  check(
    "config: unknown env_roots key is reported",
    issues:find("env_roots.typo", 1, true) ~= nil,
    issues
  )
  check(
    "config: wrong-typed vars is reported",
    issues:find("env_roots.vars", 1, true) ~= nil,
    issues
  )
  check(
    "config: wrong-typed nvim_config is reported",
    issues:find("env_roots.nvim_config", 1, true) ~= nil,
    issues
  )
  eq("config: the valid sibling is kept", config.get().env_roots.enable, false)
  eq("config: a wrong value falls back to the default", config.get().env_roots.nvim_config, true)

  config.setup({ env_roots = "off" })
  check(
    "config: a non-table env_roots is reported",
    table.concat(config.issues(), "\n"):find("option 'env_roots' must be a table", 1, true) ~= nil
  )
  config.setup({})
  eq("config: defaults", config.get().env_roots.enable, true)
  eq("config: defaults leave vars to the module", config.get().env_roots.vars, nil)
end

-- ── a stub adapter for the feature-level checks ──────────────────────────────
local cur_node
local stub = setmetatable({
  name = "envroots-stub",
  is_available = function()
    return true
  end,
  get_current_node = function()
    return cur_node
  end,
  get_winid = function()
    return nil
  end,
  refresh = function()
    return true
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

local function setup(env_roots, features)
  ft.setup({
    adapter = "envroots-stub",
    env_roots = env_roots,
    features = vim.tbl_extend("force", {
      path_copy = { enabled = true },
      copy_file_list = { enabled = true },
      markdown_links = { enabled = true, insert_path = "absolute" },
      link_create = { enabled = true },
    }, features or {}),
  })
end

-- ── path_copy: absolute formats ──────────────────────────────────────────────
do
  local tmp, repos, notes, outside = scratch("pathcopy")
  vim.env.REPOS_DIR = repos
  setup({ extra = { NOTES = notes } })
  local pc = ft.feature("path_copy")

  local function copied(fn, node_path)
    cur_node = { path = node_path, type = "file" }
    vim.fn.setreg('"', "")
    fn()
    return vim.fn.getreg('"')
  end

  eq(
    "path_copy absolute: folded under $REPOS_DIR",
    copied(pc.copy_absolute, repos .. "/proj/sub/file.md"),
    "$REPOS_DIR/proj/sub/file.md"
  )
  eq(
    "path_copy absolute: folded under a user-defined root",
    copied(pc.copy_absolute, notes .. "/a/n.md"),
    "$NOTES/a/n.md"
  )
  eq(
    "path_copy absolute: untouched under no root",
    copied(pc.copy_absolute, outside .. "/f.md"),
    outside .. "/f.md"
  )
  eq(
    "path_copy absolute_raw: never folded",
    copied(pc.copy_absolute_raw, repos .. "/proj/sub/file.md"),
    repos .. "/proj/sub/file.md"
  )
  eq(
    "path_copy dirname: folded",
    copied(pc.copy_dirname, repos .. "/proj/sub/file.md"),
    "$REPOS_DIR/proj/sub"
  )
  check(
    "path_copy uri: still the real path",
    copied(pc.copy_uri, repos .. "/proj/x.md"):find(repos:gsub("^%a:", ""), 1, true) ~= nil
  )
  check(
    "path_copy relative: relative formats are not folded",
    not copied(pc.copy_relative, repos .. "/proj/x.md"):find("$", 1, true)
  )
  eq(
    "path_copy env_rooted: still folds",
    copied(pc.copy_env_rooted, repos .. "/proj/x.md"),
    "$REPOS_DIR/proj/x.md"
  )

  setup({ enable = false })
  eq(
    "path_copy absolute, env_roots off: the plain absolute path",
    copied(ft.feature("path_copy").copy_absolute, repos .. "/proj/x.md"),
    repos .. "/proj/x.md"
  )
  eq(
    "path_copy env_rooted, env_roots off: asked for by name, still folds",
    copied(ft.feature("path_copy").copy_env_rooted, repos .. "/proj/x.md"),
    "$REPOS_DIR/proj/x.md"
  )

  vim.fn.delete(tmp, "rf")
end

-- ── copy_file_list: absolute lists ───────────────────────────────────────────
do
  local tmp, repos = scratch("filelist")
  vim.env.REPOS_DIR = repos
  setup({})
  local cfl = ft.feature("copy_file_list")

  cur_node = { path = repos .. "/proj", type = "directory" }
  vim.fn.setreg('"', "")
  cfl.copy_files_abs()
  eq("copy_file_list files_abs: folded", vim.fn.getreg('"'), "$REPOS_DIR/proj/sub/file.md")

  vim.fn.setreg('"', "")
  cfl.copy_files_rel()
  check(
    "copy_file_list files_rel: not folded",
    not vim.fn.getreg('"'):find("$", 1, true),
    vim.fn.getreg('"')
  )

  setup({ enable = false })
  vim.fn.setreg('"', "")
  ft.feature("copy_file_list").copy_files_abs()
  eq(
    "copy_file_list files_abs, env_roots off: plain",
    vim.fn.getreg('"'),
    repos .. "/proj/sub/file.md"
  )

  vim.fn.delete(tmp, "rf")
end

-- ── markdown_links: insert_path = "absolute" ─────────────────────────────────
do
  local tmp, repos = scratch("mdlinks")
  vim.env.REPOS_DIR = repos
  setup({})
  local ml = ft.feature("markdown_links")
  local buf = vim.api.nvim_create_buf(false, true)

  local links = ml.build_insert_links({ repos .. "/proj/sub/file.md" }, buf)
  eq(
    "markdown_links insert_path=absolute: folded",
    links[1],
    "[file.md]($REPOS_DIR/proj/sub/file.md)"
  )

  setup({ enable = false })
  links = ft.feature("markdown_links").build_insert_links({ repos .. "/proj/sub/file.md" }, buf)
  eq(
    "markdown_links insert_path=absolute, env_roots off: plain",
    links[1],
    "[file.md](" .. repos .. "/proj/sub/file.md)"
  )

  vim.fn.delete(tmp, "rf")
end

-- ── link_create: symlink target text, and repair's re-anchoring ──────────────
do
  local tmp, repos, notes = scratch("linkcreate")
  vim.env.REPOS_DIR = repos
  vim.fn.mkdir(repos .. "/proj/dir_a", "p")
  vim.fn.mkdir(repos .. "/other/links", "p")
  vim.fn.mkdir(notes .. "/n_dir", "p")

  local notes_seen = {}
  local orig_notify = vim.notify
  vim.notify = function(m)
    notes_seen[#notes_seen + 1] = m
  end

  local function readlink(p)
    local ok, r = pcall(uv.fs_readlink, p)
    return ok and r or nil
  end

  setup({ extra = { NOTES = notes } })
  local lc = ft.feature("link_create")

  -- Same root -> relative.
  lc.mark(repos .. "/proj/dir_a")
  cur_node = { path = repos .. "/other/links", type = "directory" }
  lc.paste()
  local made = readlink(repos .. "/other/links/dir_a")
  if not made then
    print(
      "  note link_create: directory symlink not created in this environment (needs elevation on Windows)"
    )
  else
    eq(
      "link_create: link and target under one root -> relative target",
      made:gsub("\\", "/"),
      "../../proj/dir_a"
    )
    check("link_create: ...and it resolves", uv.fs_stat(repos .. "/other/links/dir_a") ~= nil)
    check(
      "link_create: the message names the env form and the relative text",
      table.concat(notes_seen, "\n"):find("$REPOS_DIR/proj/dir_a", 1, true) ~= nil
        and table.concat(notes_seen, "\n"):find("stored relative", 1, true) ~= nil,
      table.concat(notes_seen, "\n")
    )

    -- Different roots -> absolute.
    lc.mark("$NOTES/n_dir")
    cur_node = { path = repos .. "/other/links", type = "directory" }
    lc.paste()
    local cross = readlink(repos .. "/other/links/n_dir")
    check(
      "link_create: a `$NOTES/..` target is expanded, and across two roots stays absolute",
      cross ~= nil and cross:gsub("\\", "/") == notes .. "/n_dir",
      tostring(cross)
    )

    -- relative = "never" / "always".
    vim.fn.delete(repos .. "/other/links/dir_a")
    setup({}, { link_create = { enabled = true, relative = "never" } })
    lc = ft.feature("link_create")
    lc.mark(repos .. "/proj/dir_a")
    cur_node = { path = repos .. "/other/links", type = "directory" }
    lc.paste()
    local abs = readlink(repos .. "/other/links/dir_a")
    check(
      "link_create relative=never: absolute",
      abs ~= nil and abs:gsub("\\", "/") == repos .. "/proj/dir_a",
      tostring(abs)
    )

    vim.fn.delete(repos .. "/other/links/dir_a")
    setup({}, { link_create = { enabled = true, relative = "always" } })
    lc = ft.feature("link_create")
    lc.mark(notes .. "/n_dir")
    cur_node = { path = repos .. "/other/links", type = "directory" }
    vim.fn.delete(repos .. "/other/links/n_dir")
    lc.paste()
    local always = readlink(repos .. "/other/links/n_dir")
    check(
      "link_create relative=always: relative even across roots (same drive)",
      always ~= nil and always:gsub("\\", "/"):find("^%.%./") ~= nil,
      tostring(always)
    )

    -- env_roots off: auto never goes relative.
    vim.fn.delete(repos .. "/other/links/dir_a")
    setup({ enable = false }, { link_create = { enabled = true, relative = "auto" } })
    lc = ft.feature("link_create")
    lc.mark(repos .. "/proj/dir_a")
    cur_node = { path = repos .. "/other/links", type = "directory" }
    lc.paste()
    local plain = readlink(repos .. "/other/links/dir_a")
    check(
      "link_create auto, env_roots off: absolute",
      plain ~= nil and plain:gsub("\\", "/") == repos .. "/proj/dir_a",
      tostring(plain)
    )
  end

  vim.notify = orig_notify
  vim.fn.delete(tmp, "rf")
end

-- ── review fixes ─────────────────────────────────────────────────────────────
do
  local tmp, repos, notes, outside = scratch("review")
  vim.env.REPOS_DIR = repos

  -- A root value must be absolute; junk in `vars` must not throw.
  ER.setup({ vars = { "FT_REL_ROOT", 42, "REPOS_DIR" }, extra = { REL = "relative/dir", NUM = 7 } })
  vim.env.FT_REL_ROOT = "relative/dir"
  local ok, roots = pcall(ER.roots)
  check("roots: a non-string entry in vars does not throw", ok, tostring(roots))
  local names = {}
  for _, r in ipairs(ok and roots or {}) do
    names[r.name] = true
  end
  check(
    "roots: a relative value is no root",
    not names.FT_REL_ROOT and not names.REL and not names.NUM
  )
  check("roots: the valid sibling survives", names.REPOS_DIR == true)
  vim.env.FT_REL_ROOT = nil

  -- folder(): same answers as fold(), roots resolved once.
  ER.setup({ extra = { INNER = repos .. "/proj", NOTES = notes } })
  local fold = ER.folder()
  for _, p in ipairs({
    repos .. "/proj/sub/file.md",
    repos .. "/other",
    notes .. "/a/n.md",
    outside .. "/f",
    (repos .. "/proj/x"):gsub("/", "\\"),
    repos .. "/proj/",
    "relative/x",
  }) do
    eq("folder == fold: " .. p, (fold(p)), (ER.fold(p)))
  end
  eq("folder: longest root wins", (fold(repos .. "/proj/sub/file.md")), "$INNER/sub/file.md")
  eq("folder: a trailing slash is dropped", (fold(repos .. "/other/")), "$REPOS_DIR/other")
  eq("folder: a relative path is returned as is", (fold("proj/x")), "proj/x")
  ER.setup({ enable = false })
  eq("folder: enable = false is the identity", (ER.folder()(repos .. "/proj")), repos .. "/proj")
  eq("folder: ...unless forced", (ER.folder({ force = true })(repos .. "/proj")), "$REPOS_DIR/proj")

  -- A relative symlink is checked against where the OS really resolves it: a
  -- link inside a symlinked directory falls back to the absolute path.
  ER.setup(nil)
  setup({})
  vim.fn.mkdir(repos .. "/proj/dir_a", "p")
  vim.fn.mkdir(repos .. "/phys/deep/links", "p")
  local via = repos .. "/via"
  local ok_via = uv.fs_symlink(repos .. "/phys/deep/links", via, { dir = true })
  if not ok_via then
    print(
      "  note link_create: directory symlink not created in this environment (needs elevation on Windows)"
    )
  else
    local seen = {}
    local orig_notify = vim.notify
    vim.notify = function(m)
      seen[#seen + 1] = m
    end
    local lc = ft.feature("link_create")
    lc.mark(repos .. "/proj/dir_a")
    cur_node = { path = via, type = "directory" }
    lc.paste()
    vim.notify = orig_notify
    local made = uv.fs_readlink(repos .. "/phys/deep/links/dir_a")
    check("link_create: the link exists", made ~= nil)
    check(
      "link_create: a link under a symlinked ancestor still resolves to its target",
      uv.fs_stat(via .. "/dir_a") ~= nil
        and uv.fs_realpath(via .. "/dir_a"):gsub("\\", "/"):lower()
          == uv.fs_realpath(repos .. "/proj/dir_a"):gsub("\\", "/"):lower(),
      tostring(made)
    )
    check(
      "link_create: ...by falling back to an absolute target",
      made ~= nil and made:gsub("\\", "/") == repos .. "/proj/dir_a",
      tostring(made)
    )
  end

  vim.fn.delete(tmp, "rf")
end

vim.env.REPOS_DIR = saved_repos
ER.setup(nil)

print(("\nfiletree.nvim env_roots: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
