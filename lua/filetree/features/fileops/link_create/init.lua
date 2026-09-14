---@module 'filetree.features.fileops.link_create'
--- Create a symlink or hardlink inside the current tree directory, pointing
--- at a path entered via prompt, or via a two-step mark/paste usercmd pair.
---
--- `:Filetree link` (no default keymap — usercmd-first, like path_copy's
--- format picker) asks for a target path, then creates the link named after
--- the target's basename inside the node under the cursor (its own directory
--- if it's a directory, else its parent — same resolution as smart_create).
--- A directory target only ever gets a symlink (neither Windows nor POSIX
--- allows an unprivileged hard link to a directory); a file target is offered
--- a Symlink/Hardlink choice via kit.confirm.
---
--- `:Filetree link mark [path]` / `:Filetree link paste` are the fast-path
--- pair: mark a source once (the node under the cursor, the focused editor
--- buffer's file, or an explicit path), then paste it as a link into any
--- number of nodes without retyping the source or being asked to choose a
--- link kind each time — that choice is picked automatically instead (see
--- `M.paste`). Marking again replaces the previous source; pasting does not
--- clear it, so the same source can be linked into several places in a row
--- (mirrors copy_move's copy-stays-staged behaviour).

local confirm_choice = require("filetree.util.confirm_choice")
local path = require("filetree.util.path")
local platform = require("filetree.util.platform")
local buffer = require("filetree.util.buffer")
local mutate = require("lib.nvim.cross.fs.mutate")

local M = {}

---@type FiletreeLinkCreateConfig
local _cfg = {
  enabled = true,
  keymap = nil, -- off by default; set e.g. keymap = "gl" to bind one
  keymap_mark = nil,
  keymap_paste = nil,
}
---@type FiletreeAdapter?
local _adapter = nil

---@class FiletreeLinkMarkedSource
---@field path   string   Absolute path.
---@field name   string   Basename, used both to notify and to name the link.
---@field is_dir boolean

---@type FiletreeLinkMarkedSource?
local _marked = nil

local notify = require("filetree.util.notify").create("[filetree.link_create]")
local bind = require("filetree.util.bind")

---@internal
---Get the directory to create the link in (current node's dir or cwd) —
---identical resolution to smart_create's resolve_parent_dir.
---@return string
local function resolve_parent_dir()
  if not _adapter then return path.slashify(vim.fn.getcwd()) end
  local node = _adapter.get_current_node()
  if not node then return path.slashify(vim.fn.getcwd()) end
  if node.type == "directory" then return path.slashify(node.path) end
  return path.parent(node.path)
end

---@internal
---Absolute-ize a raw, possibly relative, possibly trailing-slashed path.
---`to_absolute`'s `fnamemodify(":p")` appends a trailing OS-native separator
---for a path that is currently an existing directory; strip it again, or
---`path.basename()` below returns "" and the link would be misnamed (e.g.
---its own parent directory).
---@param raw string
---@return string
local function to_target(raw)
  local target = path.slashify(path.to_absolute(path.slashify(raw)))
  if #target > 1 and target:sub(-1) == "/" then target = target:sub(1, -2) end
  return target
end

---@internal
---@param err string|nil
---@return string
local function friendly_error(err)
  if
    platform.is_windows()
    and type(err) == "string"
    and (err:find("EPERM", 1, true) or err:find("privilege", 1, true))
  then
    return tostring(err)
      .. " (creating a symlink on Windows needs Developer Mode, "
      .. "or an elevated Neovim; a hardlink to a file doesn't need either)"
  end
  return tostring(err)
end

---@internal
---@param target string    Absolute path the link points to.
---@param link_path string Absolute path of the link to create.
---@param kind "Symlink"|"Hardlink"
---@param is_dir boolean
local function do_create(target, link_path, kind, is_dir)
  local ok, err
  local fell_back = false
  if kind == "Hardlink" then
    ok, err = mutate.hardlink(target, link_path)
    if not ok and type(err) == "string" and err:match("^EXDEV") then
      -- A hard link cannot cross filesystems or drive letters, on any OS --
      -- unlike a move (see filetree.util.mutate), there is no copy-based
      -- fallback that would still BE a hard link, so a symlink is the only
      -- link that still works here. Same trigger (EXDEV, not transient, so
      -- not retried), different fallback: this can be reached both from
      -- `M.paste`'s own Hardlink pick (files, on Windows) and from `M.create`'s
      -- user-chosen one, on any platform.
      kind = "Symlink"
      fell_back = true
      ok, err = mutate.symlink(target, link_path, is_dir)
    end
  else
    ok, err = mutate.symlink(target, link_path, is_dir)
  end

  if not ok then
    notify.error("Failed to create " .. kind:lower() .. ": " .. friendly_error(err))
    return
  end

  local msg = kind .. " created: " .. path.relative(link_path) .. " -> " .. path.relative(target)
  if fell_back then
    msg = msg .. " (hardlink not possible across drives/filesystems, used a symlink instead)"
  end
  notify.info(msg)
  if _adapter and _adapter.refresh then pcall(_adapter.refresh) end
end

---Prompt for a target path and create a link to it inside the current tree
---directory (the node under the cursor, or its parent if it's a file).
function M.create()
  local parent = resolve_parent_dir()

  local display = path.relative(parent)
  if display == "" or display == "." then
    display = "./"
  else
    display = display .. "/"
  end

  require("ui.kit").input({
    title = "Link target (path to link to), created in " .. display .. ": ",
    on_submit = function(input)
      if not input or input == "" then return end

      local target = to_target(input)
      local stat = vim.uv.fs_stat(target)
      if not stat then
        notify.error("Target does not exist: " .. path.relative(target))
        return
      end

      local is_dir = stat.type == "directory"
      local name = path.basename(target)
      local link_path = parent .. "/" .. name

      if vim.uv.fs_stat(link_path) then
        notify.error("Already exists, not overwriting: " .. path.relative(link_path))
        return
      end

      if is_dir then
        -- Hard links can't target a directory on any supported platform —
        -- no meaningful choice to offer, just create the symlink.
        do_create(target, link_path, "Symlink", true)
      else
        confirm_choice('Link "' .. name .. '" as:', { "Symlink", "Hardlink" }, function(choice)
          if not choice then return end
          do_create(target, link_path, choice, false)
        end)
      end
    end,
  })
end

-- ── Mark / paste ──────────────────────────────────────────────────────────────

---@internal
---Resolve what "the current source" means with no explicit path given: the
---node under the cursor when the tree is the focused buffer, else the
---focused editor buffer's file. Returns nil when neither applies (e.g. the
---focused buffer is a terminal or an unnamed scratch buffer).
---@return string?
local function resolve_implicit_source()
  if buffer.is_tree_buffer() and _adapter then
    local node = _adapter.get_current_node()
    if node then return path.slashify(node.path) end
  end

  local ctx = buffer.context()
  return ctx and path.slashify(ctx.file) or nil
end

---Mark a link source: an explicit path, else the node under the cursor (run
---from the tree), else the focused editor buffer's file. Replaces whatever
---was marked before; use `M.paste()` to insert it as a link.
---@param raw_path string?
function M.mark(raw_path)
  local target = (raw_path and raw_path ~= "") and to_target(raw_path) or resolve_implicit_source()

  if not target then
    notify.warn("Nothing to mark: not on a tree node, no file buffer focused, and no path given")
    return
  end

  local stat = vim.uv.fs_stat(target)
  if not stat then
    notify.error("Path does not exist: " .. path.relative(target))
    return
  end

  _marked = { path = target, name = path.basename(target), is_dir = stat.type == "directory" }
  notify.info("Marked link source: " .. path.relative(target))
end

---Paste the marked source as a link into the node under the cursor (its own
---directory if it's a directory, else its parent — same resolution as
---`M.create`). The link kind is picked automatically rather than prompted,
---since this pair is the fast path; `:Filetree link` still offers the
---Symlink/Hardlink choice for anyone who wants to override it.
---
---Directories only ever get a symlink (neither OS allows an unprivileged hard
---link to one). Files get a hardlink on Windows — needs no elevation or
---Developer Mode, unlike a Windows symlink — and a symlink elsewhere, the
---POSIX idiom. If the source and destination turn out to be on different
---drives/filesystems, a hardlink can't be created at all (EXDEV, on any OS);
---`do_create` falls back to a symlink automatically in that case.
function M.paste()
  if not _marked then
    notify.warn("No link source marked — use `:Filetree link mark` first")
    return
  end
  if not vim.uv.fs_stat(_marked.path) then
    notify.error("Marked source no longer exists: " .. path.relative(_marked.path))
    _marked = nil
    return
  end

  local parent = resolve_parent_dir()
  local link_path = parent .. "/" .. _marked.name

  if vim.uv.fs_stat(link_path) then
    notify.error("Already exists, not overwriting: " .. path.relative(link_path))
    return
  end

  local kind = _marked.is_dir and "Symlink" or (platform.is_windows() and "Hardlink" or "Symlink")
  do_create(_marked.path, link_path, kind, _marked.is_dir)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param cfg FiletreeLinkCreateConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg = vim.tbl_deep_extend("force", _cfg, cfg or {})
  _adapter = adapter

  bind.bind("link_create", _cfg, {
    {
      name = "create",
      field = "keymap",
      rhs = function()
        M.create()
      end,
      desc = "create link",
    },
    {
      name = "mark",
      field = "keymap_mark",
      rhs = function()
        M.mark()
      end,
      desc = "mark link source",
    },
    {
      name = "paste",
      field = "keymap_paste",
      rhs = function()
        M.paste()
      end,
      desc = "paste marked source as link",
    },
  })
end

function M.teardown()
  _adapter = nil
  _marked = nil
end

return M
