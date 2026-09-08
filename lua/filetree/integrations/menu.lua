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

---@internal
--- Resolve a loaded feature module (nil when the feature is disabled/absent).
---@param name string
---@return table|nil
local function feature(name)
  local ok, main = pcall(require, "filetree")
  if not ok then return nil end
  return main.feature(name)
end

---@internal
--- Resolve the active tree adapter (nil when filetree isn't set up / no
--- adapter resolved yet). Unlike `feature()`, this isn't gated by a feature
--- name — open/close is core plugin identity, not something to disable.
---@return FiletreeAdapter|nil
local function get_adapter()
  local ok, main = pcall(require, "filetree")
  if not ok then return nil end
  local ok2, adapter = pcall(main.adapter)
  return (ok2 and adapter) or nil
end

---@internal
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

---@internal
--- Append every non-nil entry to `out`, preceded by a separator when both
--- `out` and the incoming entries are non-empty. Returns whether anything
--- was added.
---
--- Takes varargs, not a table: a table CONSTRUCTOR with a nil in a
--- non-trailing slot (e.g. `{ entry(a), entry(b), entry(c) }` where `b` is
--- disabled) creates a "hole", and `ipairs` stops at the first one --
--- silently dropping every entry after it, even enabled ones. Varargs don't
--- have this problem: `select()` finds every argument at its true position
--- regardless of which others are nil.
---@param out table
---@vararg table|nil
---@return boolean added
local function add_group(out, ...)
  local n = select("#", ...)
  local compact = {}
  for i = 1, n do
    local e = select(i, ...)
    if e ~= nil then compact[#compact + 1] = e end
  end
  if #compact == 0 then return false end
  if #out > 0 then out[#out + 1] = { name = "separator" } end
  for _, e in ipairs(compact) do
    out[#out + 1] = e
  end
  return true
end

---Single entry to open or close the tree, depending on whether it is
---currently open. Deliberately NOT part of `items()`'s node-action groups
---(rename/trash/copy/… only make sense against a node under the cursor,
---which a normal editor buffer does not have) -- exposed standalone so a
---host's normal-buffer context menu can offer "open the tree" without also
---dragging in the 18 tree-only actions. `items()` still includes the SAME
---entry under its own "window" group, since "close" is meaningful there too.
---@param bufnr? integer  Buffer to reveal when opening (defaults to the current buffer).
---@return table|nil
function M.window_entry(bufnr)
  local ok, main = pcall(require, "filetree")
  local mcfg = (ok and main.config() and main.config().menu) or {}
  if mcfg.enable == false or mcfg.window == false then return nil end

  local adapter = get_adapter()
  if not adapter then return nil end

  local is_open = type(adapter.is_open) == "function" and adapter.is_open()
  if is_open then
    if type(adapter.close) ~= "function" then return nil end
    return {
      name = "  Close filetree",
      cmd = function()
        adapter.close()
      end,
    }
  end

  if type(adapter.open_reveal) ~= "function" or type(adapter.open_cwd) ~= "function" then
    return nil
  end
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
  return {
    name = "  Open filetree",
    cmd = function()
      if path ~= "" and vim.fn.filereadable(path) == 1 then
        adapter.open_reveal(path)
      else
        adapter.open_cwd()
      end
    end,
  }
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
  local on = function(group)
    return mcfg[group] ~= false
  end

  if on("fileops") then
    add_group(
      out,
      entry("smart_create", "create", "  Create file / dir", "a"),
      entry("smart_rename", "rename_current", "  Rename (LSP refs)", "r"),
      entry("rename_batch", "open", "  Batch rename", "<leader>rb"),
      entry("move", "move", "  Move to…", "M"),
      entry("create_from_template", "open_current", "  New from template", "A")
    )
  end

  if on("clipboard") then
    add_group(
      out,
      entry("copy_move", "stage_copy", "  Copy", "c"),
      entry("copy_move", "stage_cut", "  Cut", "x"),
      entry("copy_move", "paste", "  Paste", "p")
    )
  end

  if on("delete") then add_group(out, entry("trash", "delete_current", "  Trash", "d")) end

  if on("open") then
    add_group(
      out,
      entry("open_variants", "open_vsplit", "  Open in vsplit", "sg"),
      entry("open_variants", "open_split", "  Open in split", "sv"),
      entry("open_variants", "open_tabnew", "  Open in tab", "st"),
      entry("open_with", "open_system", "  Open with system app", "<leader>sm"),
      entry("open_in_fm", "open", "  Reveal in file manager", "<leader>fm")
    )
  end

  if on("paths") then
    add_group(
      out,
      entry("path_copy", "pick", "  Copy path…", "[a"),
      entry("markdown_links", "link_current", "  Markdown link", "ML")
    )
  end

  if on("search") then
    add_group(
      out,
      entry("find_files", "find", "  Find files", "f"),
      entry("grep_in_dir", "grep", "  Grep in dir", "gr")
    )
  end

  if on("info") then add_group(out, entry("node_info", "show_current", "  Node info", "I")) end

  if on("marks") then
    add_group(
      out,
      entry("marks", "toggle_current", "  Toggle mark", "m"),
      entry("marks", "mark_all_visible", "  Mark all visible", "]m"),
      entry("marks", "unmark_all_visible", "  Unmark all visible", "[m"),
      entry("marks", "clear_all", "  Clear marks", "<leader>mc"),
      entry("marks", "show", "  Show marked nodes", "<leader>ms")
    )
  end

  if on("window") then add_group(out, M.window_entry()) end

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
