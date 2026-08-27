---@module 'filetree.features.fileops.link_create'
--- Create a symlink or hardlink inside the current tree directory, pointing
--- at a path entered via prompt.
---
--- `:Filetree link` (no default keymap — usercmd-first, like path_copy's
--- format picker) asks for a target path, then creates the link named after
--- the target's basename inside the node under the cursor (its own directory
--- if it's a directory, else its parent — same resolution as smart_create).
--- A directory target only ever gets a symlink (neither Windows nor POSIX
--- allows an unprivileged hard link to a directory); a file target is offered
--- a Symlink/Hardlink choice via kit.confirm.

local confirm_choice = require("filetree.util.confirm_choice")
local path = require("filetree.util.path")
local platform = require("filetree.util.platform")
local mutate = require("lib.nvim.cross.fs.mutate")

local M = {}

---@type FiletreeLinkCreateConfig
local _cfg = {
  enabled = true,
  keymap = nil, -- off by default; set e.g. keymap = "gl" to bind one
}
---@type FiletreeAdapter?
local _adapter = nil

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
  if kind == "Hardlink" then
    ok, err = mutate.hardlink(target, link_path)
  else
    ok, err = mutate.symlink(target, link_path, is_dir)
  end

  if not ok then
    notify.error("Failed to create " .. kind:lower() .. ": " .. friendly_error(err))
    return
  end

  notify.info(kind .. " created: " .. path.relative(link_path) .. " -> " .. path.relative(target))
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

  require("lib.nvim.ui.kit").input({
    title = "Link target (path to link to), created in " .. display .. ": ",
    on_submit = function(input)
      if not input or input == "" then return end

      -- fnamemodify(":p") (inside to_absolute) appends a trailing OS-native
      -- separator for a path that is currently an existing directory, and
      -- does not itself normalize separators — slashify again afterwards,
      -- then strip it, or path.basename() below returns "" and the link
      -- would be misnamed (e.g. its own parent directory).
      local target = path.slashify(path.to_absolute(path.slashify(input)))
      if #target > 1 and target:sub(-1) == "/" then target = target:sub(1, -2) end
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
  })
end

function M.teardown()
  _adapter = nil
end

return M
