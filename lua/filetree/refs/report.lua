---@module 'filetree.refs.report'
--- On-demand reports over the reference engine, the read-only counterpart of
--- the rewrite-on-mutation pipeline:
---
---   :Filetree references [path]      who points at this file -- a popup (or a
---                                    picker) of every site, <CR> jumps there
---   :Filetree refs unused [dir]      which files under a folder nobody points
---                                    at, with a pick-and-trash step
---
--- Counting itself lives in `filetree.refs.usage`; this module resolves the
--- target, picks the view and does the jump.

local usage = require("filetree.refs.usage")
local assets = require("filetree.refs.assets")
local scan = require("filetree.refs.scan")
local ftfs = require("filetree.util.fs")
local ftpath = require("filetree.util.path")
local buffer = require("filetree.util.buffer")
local window = require("filetree.util.window")
local ui_select = require("filetree.util.select")
local refs_picker = require("filetree.util.refs_picker")
local notify = require("filetree.util.notify").create("[filetree.refs]")

local M = {}

-- Longest source line shown in the popup before it is cut (the full line is
-- one jump away; the popup only has to identify the site).
local MAX_TEXT = 90

---@internal
---@return FiletreeAdapter?
local function adapter()
  local ok, main = pcall(require, "filetree")
  if not ok then return nil end
  return main.adapter()
end

---The path a report should be about: an explicit argument, else the node
---under the cursor (when run from the tree), else the focused editor buffer.
---@param arg string?
---@return string? path  Absolute, forward slashes.
function M.resolve_target(arg)
  if arg and arg ~= "" then return ftpath.slashify(ftpath.to_absolute(vim.fn.expand(arg))) end
  local ad = adapter()
  if ad and buffer.is_tree_buffer() then
    local node = ad.get_current_node()
    if node and node.path then return ftpath.slashify(node.path) end
  end
  local ctx = buffer.context()
  return ctx and ftpath.slashify(ctx.file) or nil
end

---@internal
---"3 References" / "1 Reference".
---@param n integer
---@return string
local function noun(n)
  return string.format("%d Reference%s", n, n == 1 and "" or "s")
end

---Open the file of `ref` at its line, in an editor window (never in the tree
---window).
---@param ref FiletreeRef
function M.jump(ref)
  local ad = adapter()
  local win = buffer.find_editor_win(ad and ad.get_winid and ad.get_winid() or nil)
  if not win then win = window.open_editor_window(ad) end
  if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
  local ok, err = pcall(vim.cmd.edit, ftpath.fnameescape(ref.file))
  if not ok then
    notify.warn("could not open " .. ref.file .. ": " .. tostring(err))
    return
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { ref.line, math.max((ref.col or 1) - 1, 0) })
  pcall(vim.cmd, "normal! zz")
end

---@internal
---@param ref FiletreeRef
---@param root string
---@return string
local function popup_line(ref, root)
  local text = vim.trim(ref.text or "")
  if vim.fn.strchars(text) > MAX_TEXT then
    text = vim.fn.strcharpart(text, 0, MAX_TEXT - 1) .. "…"
  end
  return string.format("%s:%d  %s", ftpath.relative(ref.file, root), ref.line, text)
end

---Show the sites of `u` for `target` in the configured view.
---@param target string
---@param u FiletreeRefUsage
---@param opts? { view?: "popup"|"picker" }
function M.present(target, u, opts)
  local cfg = require("filetree.refs").config()
  local view = (opts and opts.view) or (cfg.report and cfg.report.view) or "popup"
  local title = string.format("%s: %s", noun(u.count), ftpath.basename(target))

  if view == "picker" then
    refs_picker.browse(u.refs, { prefer = cfg.picker, title = title })
    return
  end

  local root = require("filetree.refs").resolve_root(target)
  ui_select(u.refs, {
    prompt = title,
    relative = "editor",
    format_item = function(ref)
      return popup_line(ref, root)
    end,
  }, function(ref)
    if ref then M.jump(ref) end
  end)
end

---`:Filetree references [path]` -- count the references to one file and show
---where they are.
---@param arg string?
---@param opts? { view?: "popup"|"picker" }
function M.references(arg, opts)
  local target = M.resolve_target(arg)
  if not target then
    notify.warn("Nothing to check: not on a tree node, no file buffer focused, and no path given")
    return
  end
  if vim.fn.isdirectory(target) == 1 then return M.unused(target) end
  if vim.uv.fs_stat(target) == nil then
    notify.warn("no such file: " .. ftpath.relative(target))
    return
  end

  usage.count({ target }, nil, function(by_path, meta)
    local u = by_path[target]
    if not u or u.count == 0 then
      notify.info(
        string.format(
          "0 references to %s (%s)",
          ftpath.relative(target),
          #meta.providers > 0 and table.concat(meta.providers, ", ") .. " scanned"
            or "no provider is enabled"
        )
      )
      return
    end
    M.present(target, u, opts)
  end)
end

-- ── Unused files ──────────────────────────────────────────────────────────────

-- Files one `refs unused` sweep will count at most; past it the list is cut
-- (and says so) rather than the editor churning through a whole monorepo.
local DEFAULT_MAX_FILES = 5000

---@internal
---@param bytes integer
---@return string
local function human_size(bytes)
  if bytes < 1024 then return string.format("%d B", bytes) end
  if bytes < 1024 * 1024 then return string.format("%.0f KB", bytes / 1024) end
  return string.format("%.1f MB", bytes / 1024 / 1024)
end

---@internal
---The directories a sweep covers: the argument, else the node under the
---cursor (its own directory, or a file's parent), else the configured asset
---roots under the project root.
---@param arg string?
---@return string[]
local function resolve_dirs(arg)
  if arg and arg ~= "" then
    local target = M.resolve_target(arg)
    return target and { target } or {}
  end

  local ad = adapter()
  if ad and buffer.is_tree_buffer() then
    local node = ad.get_current_node()
    if node and node.path then
      local node_path = ftpath.slashify(node.path)
      return { vim.fn.isdirectory(node_path) == 1 and node_path or ftpath.parent(node_path) }
    end
  end

  local refs = require("filetree.refs")
  local cfg = refs.config()
  local roots = (cfg.outgoing_assets and cfg.outgoing_assets.roots) or assets.DEFAULT_ROOTS
  local base = (refs.resolve_root(vim.fn.getcwd()):gsub("/+$", ""))
  local dirs = {}
  for _, r in ipairs(roots) do
    local dir = ftpath.slashify(base .. "/" .. r)
    if vim.fn.isdirectory(dir) == 1 then dirs[#dirs + 1] = dir end
  end
  return dirs
end

---@internal
---Every file under `dirs` that passes the extension filter, capped.
---@param dirs string[]
---@param extensions string[]?  nil = every file
---@param max_files integer
---@return string[] files, boolean truncated, integer total
local function collect_files(dirs, extensions, max_files)
  local wanted
  if extensions then
    wanted = {}
    for _, e in ipairs(extensions) do
      wanted[e:lower()] = true
    end
  end

  local files, seen = {}, {}
  for _, dir in ipairs(dirs) do
    local found = ftfs.collect_recursive(dir, "files", function(name)
      return scan.PRUNE_DIRS[name] == true
    end)
    for _, f in ipairs(found) do
      local file = ftpath.slashify(f)
      local ext = file:match("%.([%w_]+)$")
      if not seen[file] and (not wanted or (ext and wanted[ext:lower()])) then
        seen[file] = true
        files[#files + 1] = file
      end
    end
  end
  table.sort(files)

  local total = #files
  if total > max_files then
    for i = total, max_files + 1, -1 do
      files[i] = nil
    end
  end
  return files, total > max_files, total
end

---Move `paths` to the trash through the trash feature (its confirmation,
---undo history and buffer cleanup apply). Replaceable so a caller or test can
---intercept it.
---@param paths string[]
function M.delete_paths(paths)
  local ok, main = pcall(require, "filetree")
  local trash = ok and main.feature and main.feature("trash") or nil
  if not trash or type(trash.delete_current) ~= "function" then
    notify.warn("the trash feature is not enabled -- nothing was deleted")
    return
  end
  trash.delete_current({ paths = paths })
end

---`:Filetree refs unused [dir] [--all] [--picker|--popup]` -- list the files
---under a folder that no scanned file references, and offer to trash a
---selection of them.
---
---By default only asset-like files are considered (`refs.report.extensions`,
---else the asset allowlist of `filetree.refs.assets`); `--all` lifts that.
---A file referenced only from a kind of file no enabled provider can read
---shows up as unused -- the summary names the providers that did run.
---@param arg string?  Directory; default the node under the cursor, else the asset roots.
---@param opts? { all?: boolean }
function M.unused(arg, opts)
  opts = opts or {}
  local refs = require("filetree.refs")
  local cfg = refs.config()
  local report_cfg = cfg.report or {}

  local dirs = resolve_dirs(arg)
  for i = #dirs, 1, -1 do
    if vim.fn.isdirectory(dirs[i]) ~= 1 then
      notify.warn(
        "not a directory: " .. ftpath.relative(dirs[i]) .. " -- see `:Filetree references`"
      )
      table.remove(dirs, i)
    end
  end
  if #dirs == 0 then
    notify.warn("No directory to check: give one, or put the cursor on a tree node")
    return
  end

  local extensions
  if not opts.all then
    extensions = report_cfg.extensions
      or (cfg.outgoing_assets and cfg.outgoing_assets.extensions)
      or assets.DEFAULT_EXTENSIONS
  end
  local files, truncated, total =
    collect_files(dirs, extensions, report_cfg.max_files or DEFAULT_MAX_FILES)
  local where = ftpath.relative(dirs[1]) .. (#dirs > 1 and string.format(" (+%d)", #dirs - 1) or "")
  if #files == 0 then
    notify.info("No candidate files in " .. where)
    return
  end
  if truncated then
    notify.warn(
      string.format(
        "%d files in %s -- only the first %d are checked (refs.report.max_files)",
        total,
        where,
        #files
      )
    )
  end

  local root = refs.resolve_root(dirs[1])
  usage.count(files, { root = root }, function(by_path, meta)
    -- A partial or blind sweep would call referenced files unused -- never
    -- offer those for deletion.
    if meta.cancelled then
      notify.warn("Cancelled -- no result, nothing is offered for deletion")
      return
    end
    if #meta.providers == 0 then
      notify.warn("No reference provider is enabled (refs.providers) -- cannot tell what is unused")
      return
    end

    local entries = {}
    for _, f in ipairs(files) do
      if by_path[f] and by_path[f].count == 0 then
        local stat = vim.uv.fs_stat(f)
        local rel = ftpath.relative(f, root)
        entries[#entries + 1] = {
          file = f,
          line = 1,
          col = 1,
          display = rel,
          label = string.format("%s  (%s)", rel, human_size(stat and stat.size or 0)),
        }
      end
    end

    notify.info(
      string.format(
        "%d of %d file(s) unused in %s  [scanned: %s]",
        #entries,
        #files,
        where,
        table.concat(meta.providers, ", ")
      )
    )
    if #entries == 0 then return end

    refs_picker.pick(entries, {
      prefer = cfg.picker,
      title = string.format("%d unused: %s", #entries, where),
      qf_hint = "Unused files in the quickfix list. Delete lines (e.g. `dd`) for files you "
        .. "want to KEEP, then run `:Filetree mdrefs confirm` to move the rest to the trash.",
    }, function(selected)
      local paths = {}
      for _, entry in ipairs(selected) do
        paths[#paths + 1] = entry.file
      end
      if #paths > 0 then M.delete_paths(paths) end
    end, function() end)
  end)
end

return M
