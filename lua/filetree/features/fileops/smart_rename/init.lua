---@module 'filetree.features.smart_rename'
---@brief LSP-aware single-node rename with will/did rename notifications.
---@description
--- Renames the current node and notifies all attached LSP servers via the
--- workspace/willRenameFiles → (file move) → workspace/didRenameFiles
--- protocol sequence so that servers can update cross-file references.
---
--- Falls back gracefully when no LSP servers support file renames.
--- Also updates open Neovim buffers pointing to the old path.
--- Integrates with the safety feature for pre-rename backups.
---
--- Config:
---   enabled      boolean
---   keymap       string?   Key inside tree (default "<F2>").
---   use_safety   boolean   Create safety backup before rename (default true).
---   dry_run      boolean   Log without executing (default false).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree smartrename

local notify = require("filetree.util.notify").create("[filetree.smart_rename]")

local M = {}

---@type FiletreeSmartRenameConfig
local _cfg = {
  enabled    = false,
  keymap     = "<F2>",
  use_safety = true,
  dry_run    = false,
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── LSP helpers ───────────────────────────────────────────────────────────────

local function make_rename_files_params(old_uri, new_uri)
  return { files = { { oldUri = old_uri, newUri = new_uri } } }
end

local function uri(path)
  return vim.uri_from_fname(path)
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

-- ── Buffer update ─────────────────────────────────────────────────────────────

local function update_buffers(old_path, new_path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == old_path then
      -- Rename the buffer to the new path
      vim.api.nvim_buf_set_name(bufnr, new_path)
      -- Clear the "file has changed on disk" state
      pcall(vim.api.nvim_buf_call, bufnr, function()
        vim.cmd("edit!")
      end)
    elseif name:sub(1, #old_path + 1) == old_path .. "/" then
      -- Buffer inside renamed directory
      local new_name = new_path .. name:sub(#old_path + 1)
      vim.api.nvim_buf_set_name(bufnr, new_name)
    end
  end
end

-- ── Core rename ───────────────────────────────────────────────────────────────

local function do_rename(old_path, new_path)
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

    -- Perform the filesystem rename
    local uv  = vim.uv or vim.loop
    uv.fs_rename(old_path, new_path, function(err)
      vim.schedule(function()
        if err then
          notify.error("Rename failed: " .. err)
          return
        end

        -- Notify LSP servers
        lsp_did_rename(old_path, new_path)

        -- Update open buffers
        update_buffers(old_path, new_path)

        -- Refresh tree
        if _adapter and _adapter.refresh then _adapter.refresh() end

        notify.info(string.format("%s → %s",
          vim.fn.fnamemodify(old_path, ":t"),
          vim.fn.fnamemodify(new_path, ":t")))
      end)
    end)
  end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.rename_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end

  local old_path = node.path
  local old_name = vim.fn.fnamemodify(old_path, ":t")
  local dir      = vim.fn.fnamemodify(old_path, ":h")

  vim.ui.input({ prompt = "Rename to: ", default = old_name }, function(new_name)
    if not new_name or new_name == "" or new_name == old_name then return end
    local new_path = dir .. "/" .. new_name
    if vim.fn.filereadable(new_path) == 1 or vim.fn.isdirectory(new_path) == 1 then
      vim.ui.select({ "Overwrite", "Cancel" }, { prompt = "'" .. new_name .. "' exists. " }, function(choice)
        if choice == "Overwrite" then do_rename(old_path, new_path) end
      end)
    else
      do_rename(old_path, new_path)
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

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_smart_rename", { clear = true })

  if _cfg.keymap then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.keymap.set("n", _cfg.keymap, M.rename_current, {
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
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
