---@module 'filetree.features.system.file_clipboard'
---@brief Copy the FILES themselves to the OS clipboard, ready for Ctrl+V elsewhere.
---@description
--- Mark three screenshots with `m`, press `gy`, and paste them with Ctrl+V into
--- a chat, a mail or a file manager -- no detour through the OS file manager.
--- What lands on the clipboard is a file list, exactly what Ctrl+C in Explorer
--- or Finder puts there; it is NOT the text of their paths (that is
--- `path_copy` / `copy_file_list`), and it is NOT filetree's own copy/cut
--- staging (`copy_move`, which only `p` inside the tree can paste).
---
--- Targets follow the usual idiom: every marked node when any is marked, else
--- the node under the cursor. Reading the marks does not clear them, so the
--- same selection can go on to `path_copy` or `markdown_links` afterwards.
--- Directories are copied as directories (the receiving app decides what to do
--- with them); entries that no longer exist are skipped and reported.
---
--- The platform tool and what it needs are described in `backend.lua`.
---
--- Config:
---   enabled        boolean
---   keymap         string?   In the tree (default `gy`).
---   preview_limit  integer?  Names listed in the notification (default 5).
---
--- Commands: `:Filetree clipfiles`.

local notify = require("filetree.util.notify").create("[filetree.file_clipboard]")
local bind = require("filetree.util.bind")
local backend = require("filetree.features.system.file_clipboard.backend")

local M = {}

---@type FiletreeFileClipboardConfig
local DEFAULTS = {
  keymap = "gy",
  preview_limit = 5,
}

---Option schema (see `filetree.config.schema`): exactly what
---`features.file_clipboard` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {
  keymap = "keymap",
  preview_limit = { "number", min = 0 },
}

---@type FiletreeFileClipboardConfig
local _cfg = vim.deepcopy(DEFAULTS)
---@type FiletreeAdapter?
local _adapter = nil

---@internal
---Every marked node when any is marked, else the one under the cursor.
---@return string[]
local function get_targets()
  local ok, marks = require("filetree.features").load("marks")
  if ok and marks and marks.count() > 0 then return marks.get_marked() end
  if not _adapter then return {} end
  local node = _adapter.get_current_node()
  return node and node.path and { node.path } or {}
end

---Split `paths` into those that exist and those that do not (a stale mark, a
---file deleted behind the tree's back).
---@param paths string[]
---@return string[] existing
---@return string[] missing
function M.split_existing(paths)
  local uv = vim.uv or vim.loop
  local existing, missing = {}, {}
  for _, p in ipairs(paths) do
    if uv.fs_stat(p) then
      existing[#existing + 1] = p
    else
      missing[#missing + 1] = p
    end
  end
  return existing, missing
end

---The notification body: how many, and the first few names.
---@param paths string[]
---@param limit integer
---@return string
local function summary(paths, limit)
  local shown = {}
  for i = 1, math.min(limit, #paths) do
    shown[i] = "  " .. vim.fn.fnamemodify(paths[i], ":t")
  end
  if #paths > limit then shown[#shown + 1] = ("  … (%d more)"):format(#paths - limit) end
  return table.concat(shown, "\n")
end

---Put `paths` on the OS clipboard as a file list. Public so a host (or a test)
---can feed it a list of its own; the keymap and the command call it with the
---tree's selection.
---@param paths string[]
function M.copy_paths(paths)
  local existing, missing = M.split_existing(paths)
  if #missing > 0 then
    notify.warn(("%d path(s) no longer exist and are skipped"):format(#missing))
  end
  if #existing == 0 then
    notify.warn("No existing file to copy")
    return
  end

  backend.copy(existing, function(ok, err, count)
    if not ok then
      notify.error("Could not copy to the system clipboard: " .. (err or "unknown error"))
      return
    end
    notify.info(
      ("Copied %d file(s) to the system clipboard (Ctrl+V pastes them):\n%s"):format(
        count,
        summary(existing, _cfg.preview_limit or DEFAULTS.preview_limit)
      )
    )
  end)
end

---Copy the marked nodes -- else the node under the cursor -- to the clipboard.
function M.copy()
  local targets = get_targets()
  if #targets == 0 then
    notify.warn("No current node")
    return
  end
  M.copy_paths(targets)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param cfg FiletreeFileClipboardConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), cfg or {})
  _adapter = adapter

  bind.bind("file_clipboard", _cfg, {
    {
      name = "copy",
      field = "keymap",
      rhs = M.copy,
      desc = "copy file(s) to the system clipboard",
    },
  })
end

function M.teardown()
  _adapter = nil
end

return M
