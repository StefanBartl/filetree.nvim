---@module 'filetree.features.telescope_integration'
---@brief Telescope / fzf-lua pickers for filetree collections.
---@description
--- Provides fuzzy-search pickers (with live preview) for all major filetree
--- collections: bookmarks, marks, recent files, notes, pins, workspace roots,
--- and tagged files.
---
--- Backend priority:
---   1. telescope.nvim (if installed and enabled)
---   2. fzf-lua       (if installed and enabled)
---   3. builtin       (falls back to each feature's own floating picker)
---
--- Config:
---   enabled   boolean
---   backend   "auto"|"telescope"|"fzf-lua"|"builtin"  (default "auto")
---   keymap_prefix  string?   Leader for all pickers (e.g. "<leader>f").
---                            Individual sub-keys: b/m/r/n/p/w/t
---                            Set to nil to skip global keymaps (default nil).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree telescope bookmarks
---   :Filetree telescope marks
---   :Filetree telescope recent
---   :Filetree telescope notes
---   :Filetree telescope pins
---   :Filetree telescope workspace
---   :Filetree telescope tags

local notify = require("filetree.util.notify").create("[filetree.telescope_integration]")

local M = {}

---@type FiletreeTelescopeConfig
local _cfg = {
  enabled        = false,
  backend        = "auto",
  keymap_prefix  = nil,
}

-- ── Backend detection ─────────────────────────────────────────────────────────

local function resolve_backend()
  if _cfg.backend ~= "auto" then return _cfg.backend end
  if pcall(require, "telescope")  then return "telescope" end
  if pcall(require, "fzf-lua")    then return "fzf-lua"   end
  return "builtin"
end

-- ── Feature helpers (lazy-loaded) ─────────────────────────────────────────────

local function feat(name)
  return require("filetree.features").require(name)
end

-- ── Telescope backend ─────────────────────────────────────────────────────────

local function telescope_picker(title, items, on_select, entry_to_str, preview_fn)
  local ok_t, telescope = pcall(require, "telescope")
  if not ok_t then notify.warn("telescope not available"); return end

  local pickers    = require("telescope.pickers")
  local finders    = require("telescope.finders")
  local conf       = require("telescope.config").values
  local actions    = require("telescope.actions")
  local action_st  = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local previewer = preview_fn and previewers.new_buffer_previewer({
    define_preview = function(self, entry)
      local lines = preview_fn(entry.value) or { "(no preview)" }
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
    end,
  }) or conf.file_previewer({})

  pickers.new({}, {
    prompt_title  = title,
    finder        = finders.new_table {
      results      = items,
      entry_maker  = function(item)
        return { value = item, display = entry_to_str(item), ordinal = entry_to_str(item) }
      end,
    },
    sorter        = conf.generic_sorter({}),
    previewer     = previewer,
    attach_mappings = function(buf, map)
      actions.select_default:replace(function()
        actions.close(buf)
        local sel = action_st.get_selected_entry()
        if sel then on_select(sel.value) end
      end)
      return true
    end,
  }):find()
end

-- ── fzf-lua backend ───────────────────────────────────────────────────────────

local function fzflua_picker(title, items, on_select, entry_to_str)
  local ok_f, fzf = pcall(require, "fzf-lua")
  if not ok_f then notify.warn("fzf-lua not available"); return end

  local str_to_item = {}
  local strs = {}
  for _, item in ipairs(items) do
    local s = entry_to_str(item)
    strs[#strs + 1] = s
    str_to_item[s]  = item
  end

  fzf.fzf_exec(strs, {
    prompt  = title .. "> ",
    actions = {
      default = function(selected)
        if selected and selected[1] then
          local item = str_to_item[selected[1]]
          if item then on_select(item) end
        end
      end,
    },
  })
end

-- ── Builtin fallback (calls each feature's own picker) ────────────────────────

local function builtin_fallback(feature_name, method)
  local f = feat(feature_name)
  if f and f[method] then f[method]()
  else notify.warn("Feature not available: " .. feature_name) end
end

-- ── Open-file helper ──────────────────────────────────────────────────────────

local function open_file(path)
  if vim.fn.filereadable(path) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  else
    notify.warn("Not readable: " .. path)
  end
end

-- ── Generic picker dispatcher ─────────────────────────────────────────────────

---@class FiletreePickerSpec
---@field title        string
---@field items        fun(): any[]
---@field to_str       fun(item: any): string
---@field on_select    fun(item: any)
---@field preview_fn   (fun(item: any): string[])?
---@field fallback_feat string?
---@field fallback_meth string?

local function open_picker(spec)
  local backend = resolve_backend()

  if backend == "builtin" and spec.fallback_feat then
    builtin_fallback(spec.fallback_feat, spec.fallback_meth or "show")
    return
  end

  local items = spec.items()
  if #items == 0 then notify.info("No items"); return end

  if backend == "telescope" then
    telescope_picker(spec.title, items, spec.on_select, spec.to_str, spec.preview_fn)
  elseif backend == "fzf-lua" then
    fzflua_picker(spec.title, items, spec.on_select, spec.to_str)
  else
    builtin_fallback(spec.fallback_feat or "", spec.fallback_meth or "show")
  end
end

-- ── Public pickers ────────────────────────────────────────────────────────────

function M.bookmarks()
  open_picker({
    title        = "Filetree Bookmarks",
    fallback_feat = "bookmarks",
    fallback_meth = "show",
    items        = function()
      local f = feat("bookmarks"); return f and f.get_all() or {}
    end,
    to_str       = function(item) return item.label or item.path end,
    on_select    = open_file,
    preview_fn   = function(item)
      if vim.fn.isdirectory(item.path) == 1 then
        return vim.fn.readdir(item.path)
      elseif vim.fn.filereadable(item.path) == 1 then
        local lines = vim.fn.readfile(item.path, "", 40)
        return lines
      end
      return {}
    end,
  })
end

function M.marks()
  open_picker({
    title        = "Filetree Marks",
    fallback_feat = "marks",
    fallback_meth = "show",
    items        = function()
      local f = feat("marks"); return f and f.get_all() or {}
    end,
    to_str       = function(item) return type(item) == "string" and item or item.path end,
    on_select    = function(item)
      open_file(type(item) == "string" and item or item.path)
    end,
  })
end

function M.recent_files()
  open_picker({
    title        = "Filetree Recent Files",
    fallback_feat = "recent_files",
    fallback_meth = "show",
    items        = function()
      local f = feat("recent_files"); return f and f.get_all() or {}
    end,
    to_str       = function(path) return vim.fn.fnamemodify(path, ":~:.") end,
    on_select    = open_file,
    preview_fn   = function(path)
      if vim.fn.filereadable(path) == 1 then return vim.fn.readfile(path, "", 40) end
      return {}
    end,
  })
end

function M.notes()
  open_picker({
    title        = "Filetree Notes",
    fallback_feat = "notes",
    fallback_meth = "show",
    items        = function()
      local f = feat("notes")
      if not f then return {} end
      local all = f.get_all and f.get_all() or {}
      local result = {}
      for _, entry in ipairs(all) do result[#result + 1] = entry end
      return result
    end,
    to_str       = function(item)
      return string.format("%-40s %s",
        vim.fn.fnamemodify(item.path or "", ":~:."), item.note or "")
    end,
    on_select    = function(item) open_file(item.path or "") end,
  })
end

function M.pins()
  open_picker({
    title        = "Filetree Pins",
    fallback_feat = "pin_node",
    fallback_meth = "show",
    items        = function()
      local f = feat("pin_node"); return f and f.get_all() or {}
    end,
    to_str       = function(path) return vim.fn.fnamemodify(path, ":~:.") end,
    on_select    = function(path)
      local adapter_mod = require("filetree.adapter")
      local adapter     = adapter_mod.get()
      if adapter and adapter.reveal then adapter.reveal(path)
      else open_file(path) end
    end,
  })
end

function M.workspace()
  open_picker({
    title        = "Filetree Workspaces",
    fallback_feat = "workspace",
    fallback_meth = "switch",
    items        = function()
      local f = feat("workspace"); return f and f.list() or {}
    end,
    to_str       = function(path) return vim.fn.fnamemodify(path, ":~:.") end,
    on_select    = function(path)
      local f = feat("workspace")
      if f then f.switch_to(path) end
    end,
  })
end

function M.tags()
  open_picker({
    title        = "Filetree Tags",
    fallback_feat = "tag_system",
    fallback_meth = "list",
    items        = function()
      local f = feat("tag_system"); if not f then return {} end
      local all = {}
      for path, tags in pairs(f._store or {}) do
        all[#all + 1] = { path = path, tags = tags }
      end
      return all
    end,
    to_str       = function(item)
      return string.format("%-40s %s",
        vim.fn.fnamemodify(item.path, ":~:."),
        table.concat(vim.tbl_map(function(t) return "#" .. t end, item.tags), " "))
    end,
    on_select    = function(item) open_file(item.path) end,
  })
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeTelescopeConfig
---@param _adapter FiletreeAdapter
function M.setup(config, _adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)

  if _cfg.keymap_prefix then
    local p = _cfg.keymap_prefix
    local map = function(k, fn, desc)
      vim.keymap.set("n", p .. k, fn, { silent = true, desc = "Filetree: " .. desc })
    end
    map("b", M.bookmarks,    "telescope bookmarks")
    map("m", M.marks,        "telescope marks")
    map("r", M.recent_files, "telescope recent files")
    map("n", M.notes,        "telescope notes")
    map("p", M.pins,         "telescope pins")
    map("w", M.workspace,    "telescope workspace")
    map("t", M.tags,         "telescope tags")
  end
end

function M.teardown() end

return M
