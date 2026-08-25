---@module 'filetree.features.fileops.smart_rename'
--- LSP-aware single-node rename with will/did rename notifications.
---
--- Renames the current node and notifies all attached LSP servers via the
--- workspace/willRenameFiles → (file move) → workspace/didRenameFiles
--- protocol sequence so that servers can update cross-file references.
---
--- Falls back gracefully when no LSP servers support file renames. Everything
--- an LSP client did *not* rewrite — markdown links always, plus require()/
--- import statements whenever no workspace edit was applied (which, for Lua,
--- is always: lua_ls never advertises the capability) — is handled by the
--- reference engine, `filetree.refs`, which also owns the chooser and the
--- undoable rewrite. Open Neovim buffers pointing at the old path are
--- repointed, and the safety feature gets its pre-rename backup.
---
--- Config:
---   enabled     boolean
---   keymap      string?   Key inside tree (default "r").
---   use_safety  boolean   Create safety backup before rename (default true).
---   dry_run     boolean   Log without executing (default false).
---
--- Reference handling is configured centrally under `refs` (see
--- `filetree.refs.DEFAULTS`), not per feature.
---
--- Commands (via :Filetree dispatcher):
---   :Filetree smartrename

local notify = require("filetree.util.notify").create("[filetree.smart_rename]")

local map = require("filetree.util.map")
local tree_attach = require("filetree.util.tree_attach")
local confirm_choice = require("filetree.util.confirm_choice")
local path        = require("filetree.util.path")
local buffer      = require("filetree.util.buffer")
-- Cross-file references (markdown links, require()/import statements) are the
-- reference engine's job, not this feature's: it owns the scan, the chooser
-- and the undoable rewrite for every provider at once.
local refs        = require("filetree.refs")

-- The one way this plugin moves a path: retries the transient Windows sharing
-- errors (EPERM/EACCES/EBUSY) that a raw uv.fs_rename surfaces as a hard
-- failure, releasing neo-tree's watcher on the source between attempts, and
-- falls back to a copy+delete across drive letters. See filetree.util.mutate.
local mutate = require("filetree.util.mutate")

local M = {}

---@type FiletreeSmartRenameConfig
local _cfg = {
  enabled    = false,
  keymap     = "r",
  use_safety = true,
  dry_run    = false,
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── LSP helpers ───────────────────────────────────────────────────────────────

---@internal
local function make_rename_files_params(old_uri, new_uri)
  return { files = { { oldUri = old_uri, newUri = new_uri } } }
end

---@internal
local function uri(fname)
  return vim.uri_from_fname(fname)
end

---@internal
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
    client:request("workspace/willRenameFiles", params, function(err, result)
      pending = pending - 1
      if not err and result then
        merged = vim.tbl_deep_extend("force", merged, result)
      end
      if pending == 0 then cb(#vim.tbl_keys(merged) > 0 and merged or nil) end
    end)
  end
end

---@internal
local function lsp_did_rename(old_path, new_path)
  local params = make_rename_files_params(uri(old_path), uri(new_path))
  for _, client in pairs(vim.lsp.get_clients()) do
    local cap = vim.tbl_get(client, "server_capabilities", "workspace",
                             "fileOperations", "didRename")
    if cap then
      client:notify("workspace/didRenameFiles", params)
    end
  end
end

-- Buffer update: filetree.util.buffer.relocate() (shared with copy_move and
-- rename_batch, which have the exact same "file moved on disk, repoint any
-- open buffer" need) handles both the single-file and nested-directory cases,
-- and normalizes path-separator style before comparing, and preserves
-- unsaved changes on a modified buffer instead of force-reloading them away.

-- ── Core rename ───────────────────────────────────────────────────────────────

---@internal
---@param old_path string
---@param new_path string
---@param scan_result FiletreeRefScanResult|nil  References captured BEFORE the
---  rename (via `refs.prefetch`), so every link style resolved against the old
---  location.
local function do_rename(old_path, new_path, scan_result)
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

    -- Synchronous rather than an async uv.fs_rename callback: we are already on
    -- the main loop here (the un-scheduled apply_workspace_edit above depends
    -- on that), which is exactly what the retry backoff's vim.wait needs — so
    -- the post-rename work runs inline instead of hopping through vim.schedule.
    local ok, err = mutate.move(old_path, new_path)
    if not ok then
      notify.error("Rename failed: " .. tostring(err))
      return
    end

    -- Notify LSP servers
    lsp_did_rename(old_path, new_path)

    -- Update open buffers
    buffer.relocate(old_path, new_path)

    -- Everything that pointed at the old path: markdown links, require()s,
    -- imports. `lsp_handled` lets the engine skip the code providers whose
    -- language server already rewrote them (`refs.prefer_lsp`), while markdown
    -- and Lua — which never get an LSP edit here — still run.
    if scan_result then
      refs.handle_result(scan_result, { [old_path] = new_path }, {
        op = "rename",
        lsp_handled = workspace_edit ~= nil,
      })
    end

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

  -- Start the reference scan NOW, while old_path still exists on disk, so it
  -- overlaps with the (potentially long) time the user spends typing a new
  -- name. The rename only happens inside `await`, i.e. strictly after this
  -- scan finished, so old_path is always still present while it runs — see
  -- refs.prefetch. (Returns an immediately-resolving handle when references
  -- are switched off, so the flow below stays the same either way.)
  local refs_handle = refs.prefetch({ old_path }, { op = "rename" })

  require("lib.nvim.ui.kit").input({
    title = "Rename to: ",
    default = old_name,
    on_submit = function(new_name)
      if not new_name or new_name == "" or new_name == old_name then return end
      new_name = path.slashify(new_name)  -- accept "/" or "\" if renaming into a subdir
      local new_path = dir .. "/" .. new_name

      local function proceed()
        refs_handle.await(function(result) do_rename(old_path, new_path, result) end)
      end

      if vim.fn.filereadable(new_path) == 1 or vim.fn.isdirectory(new_path) == 1 then
        confirm_choice("'" .. new_name .. "' exists.", { "Overwrite", "Cancel" }, function(choice)
          if choice == "Overwrite" then proceed() end
        end)
      else
        proceed()
      end
    end,
  })
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeSmartRenameConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _cfg.keymap then
    tree_attach.on_attach(function(buf)
      map("n", _cfg.keymap, M.rename_current, {
        buffer = buf, silent = true, desc = "Filetree: LSP-aware rename",
      })
    end)
  end
end

function M.teardown()
  _adapter = nil
end

return M
