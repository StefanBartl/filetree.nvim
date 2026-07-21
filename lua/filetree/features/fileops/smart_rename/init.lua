---@module 'filetree.features.smart_rename'
---@brief LSP-aware single-node rename with will/did rename notifications.
---@description
--- Renames the current node and notifies all attached LSP servers via the
--- workspace/willRenameFiles → (file move) → workspace/didRenameFiles
--- protocol sequence so that servers can update cross-file references.
---
--- Falls back gracefully when no LSP servers support file renames. When no
--- client applied a workspace edit (or the file is Lua, where lua_ls never
--- advertises this capability), a project-wide textual fallback rewrites
--- require()/import references instead — see update_references below.
--- Also updates open Neovim buffers pointing to the old path.
--- Integrates with the safety feature for pre-rename backups.
---
--- Config:
---   enabled            boolean
---   keymap             string?   Key inside tree (default "r").
---   use_safety         boolean   Create safety backup before rename (default true).
---   dry_run            boolean   Log without executing (default false).
---   update_references  boolean   Fallback require()/import rewrite across the
---                                project when LSP didn't handle it (default true).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree smartrename

local notify = require("filetree.util.notify").create("[filetree.smart_rename]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local ui_select   = require("filetree.util.select")
local path        = require("filetree.util.path")
local buffer      = require("filetree.util.buffer")
local refs_util   = require("filetree.util.markdown_refs")
local refs_picker = require("filetree.util.refs_picker")

-- Central FS-mutation chokepoint (libuv-based, no shell). Retries transient
-- Windows sharing errors (EPERM/EACCES/EBUSY) that a raw uv.fs_rename would
-- surface as a hard failure — see the handle_guard plan.
local fsops = require("lib.nvim.cross.fs.mutate")

local M = {}

---@type FiletreeSmartRenameConfig
local _cfg = {
  enabled             = false,
  keymap              = "r",
  use_safety          = true,
  dry_run             = false,
  update_references   = true,
  check_markdown_refs = true,
  refs_picker_prefer  = "auto",
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── LSP helpers ───────────────────────────────────────────────────────────────

local function make_rename_files_params(old_uri, new_uri)
  return { files = { { oldUri = old_uri, newUri = new_uri } } }
end

local function uri(fname)
  return vim.uri_from_fname(fname)
end

---Send willRenameFiles to all supporting clients. Returns edit to apply (or nil).
---@param old_path string
---@param new_path string
---@param cb fun(workspace_edit: table?)
local function lsp_will_rename(old_path, new_path, cb)
  local params   = make_rename_files_params(uri(old_path), uri(new_path))
  local clients  = {}
  for _, client in pairs(vim.lsp.get_clients()) do
    local cap = vim.tbl_get(client, "server_capabilities", "workspace",
                             "fileOperations", "willRename")
    if cap then clients[#clients + 1] = client end
  end

  if #clients == 0 then cb(nil); return end

  local pending = #clients
  local merged  = {}
  for _, client in ipairs(clients) do
    client.request("workspace/willRenameFiles", params, function(err, result)
      pending = pending - 1
      if not err and result then
        merged = vim.tbl_deep_extend("force", merged, result)
      end
      if pending == 0 then cb(#vim.tbl_keys(merged) > 0 and merged or nil) end
    end)
  end
end

local function lsp_did_rename(old_path, new_path)
  local params = make_rename_files_params(uri(old_path), uri(new_path))
  for _, client in pairs(vim.lsp.get_clients()) do
    local cap = vim.tbl_get(client, "server_capabilities", "workspace",
                             "fileOperations", "didRename")
    if cap then
      client.notify("workspace/didRenameFiles", params)
    end
  end
end

-- Buffer update: filetree.util.buffer.relocate() (shared with copy_move and
-- rename_batch, which have the exact same "file moved on disk, repoint any
-- open buffer" need) handles both the single-file and nested-directory cases,
-- and normalizes path-separator style before comparing, and preserves
-- unsaved changes on a modified buffer instead of force-reloading them away.

-- ── Reference update (fallback) ────────────────────────────────────────────────
-- LSP willRenameFiles/didRenameFiles (above) is the primary mechanism for
-- updating cross-file references on rename/move, but it only fires when an
-- attached client advertises workspace.fileOperations.willRename — lua_ls does
-- not, so Lua projects would otherwise silently lose every require() reference
-- on every move. This fallback does a project-wide textual find/replace of
-- require()/import statements, restricted to the renamed file's own language
-- family, and only runs when the LSP path didn't already handle it (or the
-- file is Lua, which never gets an LSP edit here regardless).

local function escape_lua_pattern(s)
  return (s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
end

local function escape_gsub_repl(s)
  return (s:gsub("%%", "%%%%"))
end

---Absolute .lua path → dotted require() module name, e.g.
---".../lua/foo/bar.lua" → "foo.bar". Mirrors path_utils'/lua_require_copy's
---path_to_module convention: a trailing "/init" collapses into its parent.
---@param abs_path string
---@return string?
local function file_to_lua_module(abs_path)
  -- The leading ".*" is greedy, so this anchors on the *last* "/lua/" segment
  -- (the nearest ancestor lua/ dir) rather than the first — an outer ancestor
  -- directory named "lua" (e.g. a workspace folder "~/projects/lua/") must
  -- not be mistaken for the require-root. ".lua" is stripped if present but
  -- not required, so this also resolves directory paths (a renamed dir has
  -- no extension at all) for submodule-cascade purposes.
  local rel = path.to_unix(abs_path):match(".*/lua/(.+)$")
  if not rel then return nil end
  -- path.to_unix() -> fnamemodify(p, ":p") appends a trailing "/" when `p`
  -- currently exists as a directory on disk (Vim's own :p behavior) — which,
  -- for a rename's *new* path, it does by the time this runs. Strip it so
  -- old_m/new_m are computed the same way regardless of which side of the
  -- rename already exists on disk at call time.
  rel = rel:gsub("/$", ""):gsub("%.lua$", ""):gsub("/init$", "")
  return (rel:gsub("/", "."))
end

---Absolute .py path → dotted import module name, relative to the nearest
---detected project root (falls back to the file's own directory).
---@param abs_path string
---@return string?
local function file_to_python_module(abs_path)
  if not abs_path:match("%.py$") then return nil end

  local ok_pr, pr = require("filetree.features").load("project_root")
  local root = (ok_pr and pr and pr.find) and pr.find(abs_path) or path.parent(abs_path)
  local root_norm = path.to_unix(root):gsub("/$", "")

  local rel = path.to_unix(abs_path)
  if rel:sub(1, #root_norm) == root_norm then
    rel = rel:sub(#root_norm + 2) -- +2 skips root and its separating "/"
  end
  rel = rel:gsub("%.py$", ""):gsub("/__init__$", "")

  return rel ~= "" and (rel:gsub("/", ".")) or nil
end

---Relative path from `from_dir` to `target_path`, POSIX-style, with ".."
---segments where needed (filetree.util.path.relative only handles descendants).
---@param from_dir string
---@param target_path string
---@return string
local function relpath(from_dir, target_path)
  local t, f = {}, {}
  for part in path.to_unix(target_path):gmatch("[^/]+") do t[#t + 1] = part end
  for part in path.to_unix(from_dir):gmatch("[^/]+") do f[#f + 1] = part end

  local i = 1
  while t[i] and f[i] and t[i] == f[i] do i = i + 1 end

  local parts = {}
  for _ = i, #f do parts[#parts + 1] = ".." end
  for j = i, #t do parts[#parts + 1] = t[j] end

  return #parts > 0 and table.concat(parts, "/") or "."
end

---Relative path from `from_dir` to `target_path` as a JS/TS module specifier
---(extensionless, "/index" collapsed, "./"-prefixed unless it already climbs up).
---@param from_dir string
---@param target_path string
---@return string
local function to_module_specifier(from_dir, target_path)
  local rel = relpath(from_dir, target_path)
    :gsub("%.tsx?$", ""):gsub("%.jsx?$", ""):gsub("/index$", "")
  if rel:sub(1, 2) ~= ".." then rel = "./" .. rel end
  return rel
end

---Build a line-replacer for `filetype`, or nil when this filetype has no
---supported reference pattern (old/new module couldn't be resolved, e.g. the
---file isn't under a lua/ root). `ref_file` matters only for TS/JS, where the
---import specifier is relative to the file being patched, not to old_path.
---@param filetype string
---@param old_path string
---@param new_path string
---@param ref_file string
---@return (fun(line: string): string)?
local function build_line_replacer(filetype, old_path, new_path, ref_file)
  if filetype == "lua" then
    local old_m, new_m = file_to_lua_module(old_path), file_to_lua_module(new_path)
    if not old_m or not new_m then return nil end
    local old_esc, new_esc = escape_lua_pattern(old_m), escape_gsub_repl(new_m)
    return function(line)
      local out = (line:gsub("(require%s*%(%s*[\"'])" .. old_esc .. "([\"']%s*%))", "%1" .. new_esc .. "%2"))
      out = (out:gsub("(require%s+[\"'])" .. old_esc .. "([\"'])", "%1" .. new_esc .. "%2"))
      -- Submodule cascade: renaming a directory ("testfs.rem" -> "testfs.remolus")
      -- must also update require()s of anything nested under it
      -- ("testfs.rem.da" -> "testfs.remolus.da"). The suffix must start with a
      -- literal "." so a same-prefix-different-module ("testfs.rem_other")
      -- never matches.
      -- function-form replacements are inserted verbatim (no %-escaping
      -- needed/wanted here, unlike the string-form repl above), so these use
      -- new_m directly rather than the %%-doubled new_esc.
      out = (out:gsub(
        "(require%s*%(%s*[\"'])" .. old_esc .. "(%.[%w_%.]*)([\"']%s*%))",
        function(pre, suffix, post) return pre .. new_m .. suffix .. post end
      ))
      return (out:gsub(
        "(require%s+[\"'])" .. old_esc .. "(%.[%w_%.]*)([\"'])",
        function(pre, suffix, post) return pre .. new_m .. suffix .. post end
      ))
    end

  elseif filetype == "python" then
    local old_m, new_m = file_to_python_module(old_path), file_to_python_module(new_path)
    if not old_m or not new_m then return nil end
    local old_esc, new_esc = escape_lua_pattern(old_m), escape_gsub_repl(new_m)
    return function(line)
      local out = (line:gsub("(from%s+)" .. old_esc .. "(%s+import)", "%1" .. new_esc .. "%2"))
      return (out:gsub("(import%s+)" .. old_esc .. "([%s,]?)", "%1" .. new_esc .. "%2"))
    end

  elseif filetype:match("^typescript") or filetype:match("^javascript") then
    local ref_dir = path.parent(ref_file)
    local old_r, new_r = to_module_specifier(ref_dir, old_path), to_module_specifier(ref_dir, new_path)
    local old_esc, new_esc = escape_lua_pattern(old_r), escape_gsub_repl(new_r)
    return function(line)
      local out = (line:gsub("(from%s+[\"'])" .. old_esc .. "([\"'])", "%1" .. new_esc .. "%2"))
      out = (out:gsub("(import%s+[\"'])" .. old_esc .. "([\"'])", "%1" .. new_esc .. "%2"))
      return (out:gsub("(import%(%s*[\"'])" .. old_esc .. "([\"'])", "%1" .. new_esc .. "%2"))
    end
  end

  return nil
end

---Pick the search needle + extension whitelist for a rename, based on the
---renamed file's own filetype — references only ever come from the same
---language family (lua ← lua, .py ← .py, ts/js ← any of ts/tsx/js/jsx).
---Also returns the *resolved* filetype, since a directory rename comes in
---with an empty `filetype` (no extension to detect one from) but must still
---be dispatched as "lua" downstream, in build_line_replacer.
---@param old_path string
---@param filetype string
---@return string? needle, string[]? extensions, string? resolved_filetype
local function reference_scan_spec(old_path, filetype)
  if filetype == "lua" then
    local m = file_to_lua_module(old_path)
    return m, m and { "lua" } or nil, "lua"
  elseif filetype == "python" then
    local m = file_to_python_module(old_path)
    return m, m and { "py" } or nil, "python"
  elseif filetype:match("^typescript") or filetype:match("^javascript") then
    return (path.basename(old_path):gsub("%.[tj]sx?$", "")), { "ts", "tsx", "js", "jsx" }, filetype
  elseif filetype == "" then
    -- Likely a directory rename (no extension to detect a language from).
    -- file_to_lua_module() already returns nil for anything not under a
    -- lua/ tree, so this only fires for genuine Lua module directories
    -- (e.g. renaming a Python package directory correctly falls through to nil).
    local m = file_to_lua_module(old_path)
    return m, m and { "lua" } or nil, m and "lua" or nil
  end
  return nil, nil, nil
end

---Synchronous ripgrep scan for files containing `needle` as a fixed string,
---restricted to `exts`. Degrades to an empty result (no-op) when ripgrep
---isn't installed rather than hard-failing.
---@param root string
---@param needle string
---@param exts string[]
---@return string[]
local function find_candidate_files(root, needle, exts)
  if vim.fn.executable("rg") == 0 then return {} end

  -- vim.system with an argv list (not a shell string) on purpose: it execs rg
  -- directly with no shell in between, so there's nothing to quote/escape and
  -- no dependency on &shell being cmd.exe-compatible (e.g. Git Bash as &shell
  -- on Windows mishandles hand-built quoted command strings). Matches the
  -- vim.system(cmd):wait() idiom used throughout the rest of the plugin.
  local cmd = { "rg", "--files-with-matches", "--fixed-strings", "--color=never" }
  for _, ext in ipairs(exts) do
    cmd[#cmd + 1] = "-g"
    cmd[#cmd + 1] = "*." .. ext
  end
  cmd[#cmd + 1] = "-g"; cmd[#cmd + 1] = "!.git/*"
  cmd[#cmd + 1] = "-g"; cmd[#cmd + 1] = "!node_modules/*"
  cmd[#cmd + 1] = "--"
  cmd[#cmd + 1] = needle
  cmd[#cmd + 1] = root

  local result = vim.system(cmd, { text = true }):wait()
  if result.code > 1 then return {} end -- rg: 0 = matches, 1 = no matches, >1 = error

  local files = {}
  for line in (result.stdout or ""):gmatch("[^\r\n]+") do
    files[#files + 1] = path.to_absolute(line)
  end
  return files
end

---Patch one file's require()/import references, whether it's open in a
---buffer (patched live) or only on disk (read/written directly).
---@param file string
---@param old_path string
---@param new_path string
---@param filetype string
---@return boolean changed
local function patch_file_references(file, old_path, new_path, filetype)
  local replace = build_line_replacer(filetype, old_path, new_path, file)
  if not replace then return false end

  local bufnr = vim.fn.bufnr(file)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local changed = false
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
      local new_line = replace(line)
      if new_line ~= line then
        vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { new_line })
        changed = true
      end
    end
    return changed
  end

  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok or not lines then return false end

  local changed = false
  for i, line in ipairs(lines) do
    local new_line = replace(line)
    if new_line ~= line then
      lines[i] = new_line
      changed = true
    end
  end
  if changed then pcall(vim.fn.writefile, lines, file) end
  return changed
end

---Project-wide fallback: rewrite require()/import references to `old_path`
---after a rename/move, when the LSP path above didn't already cover it.
---@param old_path string
---@param new_path string
---@param had_workspace_edit boolean  Whether an LSP client applied an edit.
local function update_references_fallback(old_path, new_path, had_workspace_edit)
  if not _cfg.update_references then return end

  local filetype = vim.filetype.match({ filename = old_path }) or ""
  if had_workspace_edit and filetype ~= "lua" then return end

  local needle, exts, resolved_filetype = reference_scan_spec(old_path, filetype)
  if not needle then return end

  local ok_pr, pr = require("filetree.features").load("project_root")
  local root = (ok_pr and pr and pr.find) and pr.find(old_path) or vim.fn.getcwd()

  local files_changed = 0
  for _, file in ipairs(find_candidate_files(root, needle, exts)) do
    if path.to_absolute(file) ~= path.to_absolute(new_path)
        and patch_file_references(file, old_path, new_path, resolved_filetype) then
      files_changed = files_changed + 1
    end
  end

  if files_changed > 0 then
    notify.info(string.format(
      "Updated references in %d file(s) for %s",
      files_changed, vim.fn.fnamemodify(old_path, ":t")
    ))
  end
end

-- ── Markdown reference update (post-rename) ─────────────────────────────────────
-- Separate from update_references_fallback above: that one rewrites
-- require()/import statements (code); this rewrites markdown `[text](path)`
-- links via the same markdown.nvim soft-dep + chooser UX as trash's delete
-- flow. Runs after the rename already succeeded (unlike trash, where the
-- check gates a still-pending delete) -- a rename is trivially reversible, so
-- there's no "cancel" option here, just "fix the links up" or "leave them".

---@param old_path string
---@param new_path string
---@param refs table[]|nil  References captured BEFORE the rename (via prefetch).
local function handle_markdown_refs(old_path, new_path, refs)
  if not _cfg.check_markdown_refs or not refs or #refs == 0 then return end

  -- Compute each ref's new target NOW, style-preserving (a `./x` link stays
  -- `./x`, a cwd-relative one stays cwd-relative). update()/the picker then
  -- just apply the per-ref new_target.
  for _, r in ipairs(refs) do r.new_target = refs_util.retarget(r, new_path) end

  local files = refs_util.unique_files(refs)
  notify.info(string.format(
    "%d markdown reference(s) found in: %s", #refs, table.concat(files, ", ")
  ))

  ui_select(
    {
      "✓  Update all references to the new path",
      "◐  Inspect references first",
      "✗  Leave references as-is",
    },
    { prompt = string.format(" %d ref(s) to %s ", #refs, vim.fn.fnamemodify(old_path, ":t")) },
    function(_, idx)
      if idx == 1 then
        refs_util.update(refs)
      elseif idx == 2 then
        refs_picker.pick(
          refs,
          { prefer = _cfg.refs_picker_prefer, title = string.format("References to %s", vim.fn.fnamemodify(old_path, ":t")) },
          function(selected)
            if #selected > 0 then refs_util.update(selected) end
          end,
          function() end -- Esc: nothing further to do, the rename already happened
        )
      end
      -- idx == 3 (leave as-is) or nil (dismissed): no-op
    end
  )
end

-- ── Core rename ───────────────────────────────────────────────────────────────

---@param old_path string
---@param new_path string
---@param refs table[]|nil  Markdown refs captured before the rename (prefetch).
local function do_rename(old_path, new_path, refs)
  if _cfg.dry_run then
    notify.info(string.format("[dry-run] %s → %s",
      vim.fn.fnamemodify(old_path, ":t"),
      vim.fn.fnamemodify(new_path, ":t")))
    return
  end

  -- Safety backup
  if _cfg.use_safety then
    local ok_s, safety = require("filetree.features").load("safety")
    if ok_s and safety then pcall(safety.before_move, old_path, new_path) end
  end

  lsp_will_rename(old_path, new_path, function(workspace_edit)
    -- Apply workspace edit from LSP (reference updates) before the move
    if workspace_edit then
      pcall(vim.lsp.util.apply_workspace_edit, workspace_edit, "utf-8")
    end

    -- Perform the filesystem rename through the central mutation chokepoint so a
    -- transient Windows sharing error (EPERM/EACCES/EBUSY — an open directory
    -- watcher / indexer / AV still holding the handle) is retried instead of
    -- surfaced as a hard failure. Synchronous rather than the old async
    -- uv.fs_rename callback form: we are already on the main loop here (the
    -- un-scheduled apply_workspace_edit above depends on that), which is exactly
    -- what the retry backoff's vim.wait needs — so the post-rename work can run
    -- inline instead of hopping through vim.schedule (the old async callback ran
    -- off-loop, which was the only reason that hop existed).
    local ok, err = fsops.rename_file(old_path, new_path)
    if not ok then
      notify.error("Rename failed: " .. tostring(err))
      return
    end

    -- Notify LSP servers
    lsp_did_rename(old_path, new_path)

    -- Update open buffers
    buffer.relocate(old_path, new_path)

    -- Fallback: textual require()/import rewrite across the project when
    -- no LSP client applied a workspace edit (or the file is Lua).
    update_references_fallback(old_path, new_path, workspace_edit ~= nil)

    -- Markdown `[text](path)` links pointing at the old path (separate
    -- concern from the code-reference fallback above). `refs` were captured
    -- BEFORE the rename (while old_path still existed) so cwd-relative and
    -- every other link style resolve correctly.
    handle_markdown_refs(old_path, new_path, refs)

    -- Refresh tree
    if _adapter and _adapter.refresh then _adapter.refresh() end

    notify.info(string.format("%s → %s",
      vim.fn.fnamemodify(old_path, ":t"),
      vim.fn.fnamemodify(new_path, ":t")))
  end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.rename_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end

  local old_path = node.path
  local old_name = vim.fn.fnamemodify(old_path, ":t")
  local dir      = path.parent(old_path)

  -- Start the markdown-reference search NOW, while old_path still exists on
  -- disk, so it overlaps with the (potentially long) time the user spends
  -- typing a new name. The rename only happens inside `await`, i.e. strictly
  -- after this scan finishes, so old_path is always still present during the
  -- scan — see refs_util.prefetch. (No-op handle when the check is disabled.)
  local refs_handle = (_cfg.check_markdown_refs and refs_util.available())
    and refs_util.prefetch(old_path) or nil

  vim.ui.input({ prompt = "Rename to: ", default = old_name }, function(new_name)
    if not new_name or new_name == "" or new_name == old_name then return end
    new_name = path.slashify(new_name)  -- accept "/" or "\" if renaming into a subdir
    local new_path = dir .. "/" .. new_name

    local function proceed()
      if refs_handle then
        refs_handle.await(function(refs) do_rename(old_path, new_path, refs) end)
      else
        do_rename(old_path, new_path, nil)
      end
    end

    if vim.fn.filereadable(new_path) == 1 or vim.fn.isdirectory(new_path) == 1 then
      ui_select({ "Overwrite", "Cancel" }, { prompt = "'" .. new_name .. "' exists. " }, function(choice)
        if choice == "Overwrite" then proceed() end
      end)
    else
      proceed()
    end
  end)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeSmartRenameConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_smart_rename", true)

  if _cfg.keymap then
    au.acmd("FileType", {
      group   = _augroup,
      pattern = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap, M.rename_current, {
            buffer = buf, silent = true, desc = "Filetree: LSP-aware rename",
          })
        end)
      end,
    })
  end
end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
