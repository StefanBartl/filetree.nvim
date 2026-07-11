---@module 'filetree.integrations.menu'
---@brief Context-menu entries for nvzone/menu (soft, opt-in integration).
---@description
--- filetree.nvim does not depend on a menu plugin. It *provides* a curated list
--- of entries in the shape nvzone/menu expects (`{ name, cmd, rtxt }` plus
--- `{ name = "separator" }`), wired to the filetree feature actions. A host —
--- typically the user's tree/RightMouse dispatcher — composes them for the tree
--- window, e.g.:
--- >
---   local items = require("filetree.integrations.menu").items()
---   require("menu").open(items, { mouse = true })
--- <
--- Entries are self-gating: an action whose feature is disabled (so
--- `require("filetree").feature(name)` is nil) is omitted, and whole groups can
--- be turned off via `config.menu` (see filetree.config.DEFAULTS). nvzone closes
--- the menu before running `cmd`, so the tree window/node is the active context —
--- exactly as if the corresponding keymap had been pressed.

local M = {}

--- Resolve a loaded feature module (nil when the feature is disabled/absent).
---@param name string
---@return table|nil
local function feature(name)
  local ok, main = pcall(require, "filetree")
  if not ok then return nil end
  return main.feature(name)
end

--- Build one menu entry, or nil when the feature/function is unavailable.
---@param name string   feature name
---@param fn string     function on the feature module
---@param label string  menu label
---@param rtxt? string  right-aligned hint (usually the default keymap)
---@return table|nil
local function entry(name, fn, label, rtxt)
  local f = feature(name)
  if not (f and type(f[fn]) == "function") then return nil end
  return {
    name = label,
    rtxt = rtxt,
    cmd = function()
      local ff = feature(name)
      if ff and type(ff[fn]) == "function" then ff[fn]() end
    end,
  }
end

--- Append every non-nil entry of `group` to `out`, preceded by a separator when
--- both `out` and `group` are non-empty. Returns whether anything was added.
---@param out table
---@param group table[]
---@return boolean added
local function add_group(out, group)
  local compact = {}
  for _, e in ipairs(group) do
    if e ~= nil then compact[#compact + 1] = e end
  end
  if #compact == 0 then return false end
  if #out > 0 then out[#out + 1] = { name = "separator" } end
  for _, e in ipairs(compact) do out[#out + 1] = e end
  return true
end

--- Build the filetree context-menu entries for the current tree node.
--- Returns an empty list when the integration (or every group) is disabled, so a
--- host can `vim.list_extend` it unconditionally.
---@return table[]
function M.items()
  local ok, main = pcall(require, "filetree")
  local mcfg = (ok and main.config() and main.config().menu) or {}
  if mcfg.enable == false then return {} end

  local out = {}
  local on = function(group) return mcfg[group] ~= false end

  if on("fileops") then
    add_group(out, {
      entry("smart_create", "create", "  Create file / dir", "a"),
      entry("smart_rename", "rename_current", "  Rename (LSP refs)", "r"),
      entry("rename_batch", "open", "  Batch rename", "<leader>rb"),
      entry("create_from_template", "open_current", "  New from template", "t"),
    })
  end

  if on("clipboard") then
    add_group(out, {
      entry("copy_move", "stage_copy", "  Copy", "c"),
      entry("copy_move", "stage_cut", "  Cut", "x"),
      entry("copy_move", "paste", "  Paste", "p"),
    })
  end

  if on("delete") then
    add_group(out, {
      entry("trash", "delete_current", "  Trash", "d"),
    })
  end

  if on("open") then
    add_group(out, {
      entry("open_variants", "open_vsplit", "  Open in vsplit", "sg"),
      entry("open_variants", "open_split", "  Open in split", "sv"),
      entry("open_variants", "open_tabnew", "  Open in tab", "st"),
      entry("open_with", "open_system", "  Open with system app", "<leader>sm"),
      entry("open_in_fm", "open", "  Reveal in file manager", "<leader>fm"),
    })
  end

  if on("paths") then
    add_group(out, {
      entry("path_copy", "pick", "  Copy path…", "[a"),
      entry("markdown_links", "link_current", "  Markdown link", "ML"),
    })
  end

  if on("search") then
    add_group(out, {
      entry("find_files", "find", "  Find files", "f"),
      entry("grep_in_dir", "grep", "  Grep in dir", "gr"),
    })
  end

  if on("info") then
    add_group(out, {
      entry("node_info", "show_current", "  Node info", "I"),
    })
  end

  return out
end

--- Convenience: the entries wrapped as a single nested submenu entry, for hosts
--- that prefer a "Filetree ▸" fly-out. Returns nil when there is nothing to show.
---@param label? string
---@return table|nil
function M.submenu(label)
  local items = M.items()
  if #items == 0 then return nil end
  return { name = label or "  Filetree", items = items }
end

return M
