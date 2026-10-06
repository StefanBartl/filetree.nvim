---@module 'filetree.refs.report'
--- On-demand reports over the reference engine, the read-only counterpart of
--- the rewrite-on-mutation pipeline:
---
---   :Filetree references [path]      who points at this file -- a popup (or a
---                                    picker) of every site, <CR> jumps there
---
--- Counting itself lives in `filetree.refs.usage`; this module resolves the
--- target, picks the view and does the jump.

local usage = require("filetree.refs.usage")
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
  if vim.fn.isdirectory(target) == 1 then
    notify.warn("a directory has no single reference count -- use `:Filetree refs unused <dir>`")
    return
  end
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

return M
