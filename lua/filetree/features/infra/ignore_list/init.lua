---@module 'filetree.features.ignore_list'
---@brief Hide common filesystem clutter (.git, node_modules, …) from the tree by default.
---@description
--- Injects a list of basenames into the adapter's native hide mechanism so they
--- do not appear in the tree at all.  Toggle via the adapter's built-in
--- show-hidden key (e.g. `H` in neo-tree, which toggles filtered_items.visible).
---
--- Precedence for the name list (highest first):
---   1. User supplies `ignore_list = { ".git", … }` → uses that array verbatim.
---   2. lib.nvim is on the runtimepath → uses require("lib.nvim.fs.ignore.list").basenames.
---   3. Built-in fallback embedded below.
---
--- Config (driven from top-level `ignore_list` in FiletreeConfig, not from features):
---   enabled  boolean     true = hide; false = skip entirely.
---   names    string[]?   nil = resolve from lib.nvim / built-in.
---
--- Toggle at runtime: use the adapter's own "toggle hidden" mechanism.
---   neotree  → `H` (toggle_hidden) shows/hides everything in filtered_items.
---   nvimtree → `H` (toggle_dotfiles) shows/hides dot-files.
---   Others   → filetree falls back to extmark-dim (same as ignore_patterns).

local notify = require("filetree.util.notify").create("[filetree.ignore_list]")

local au  = require("filetree.util.autocmd")
local M = {}

-- ── Built-in name list (mirrored from lib.nvim's canonical ignore list) ───────

local _BUILTIN = {
  ".git", ".github", ".hg", ".svn", ".svc", ".stfolder", ".stversions",
  "node_modules", ".pnpm-store", ".yarn",
  ".venv", ".direnv",
  "__pycache__", ".mypy_cache", ".pytest_cache",
  ".cache", ".sass-cache",
  "build", "dist", "out", "target", "bin", "obj",
  "zig-cache", "zig-out",
  ".DS_Store", "thumbs.db",
  ".vscode", ".idea",
}

---Resolve the effective name list: user override → lib.nvim → built-in.
---@param user_names string[]? explicit list from config; nil = use defaults
---@return string[]
local function resolve_names(user_names)
  if user_names then return user_names end
  local ok, lib_list = pcall(require, "lib.nvim.fs.ignore.list")
  if ok and type(lib_list) == "table" and type(lib_list.basenames) == "table" then
    return lib_list.basenames
  end
  return _BUILTIN
end

-- ── Adapter-specific hide injection ──────────────────────────────────────────

---Inject names into neo-tree's filtered_items.hide_by_name and refresh.
---@param names string[]
---@param adapter FiletreeAdapter
local function apply_neotree(names, adapter)
  -- The merged neo-tree config lives on require("neo-tree").config after its
  -- setup() has run (require("neo-tree.config") does NOT exist in v3.x).
  local ok, nt = pcall(require, "neo-tree")
  local ncfg = ok and (nt.config or (type(nt.ensure_config) == "function" and nt.ensure_config())) or nil
  if not ncfg or not ncfg.filesystem then
    -- neo-tree.setup() hasn't run yet (e.g. lazy=false startup race).
    -- Retry once after VimEnter when all plugin configs have executed.
    au.acmd("VimEnter", {
      once     = true,
      callback = function()
        vim.defer_fn(function() apply_neotree(names, adapter) end, 50)
      end,
    })
    return
  end

  local fi = ncfg.filesystem.filtered_items
  if not fi then
    ncfg.filesystem.filtered_items = {}
    fi = ncfg.filesystem.filtered_items
  end

  fi.hide_by_name = fi.hide_by_name or {}
  local existing = {}
  for _, n in ipairs(fi.hide_by_name) do existing[n] = true end
  for _, name in ipairs(names) do
    if not existing[name] then
      fi.hide_by_name[#fi.hide_by_name + 1] = name
      existing[name] = true
    end
  end

  if fi.visible == nil then fi.visible = false end

  if type(adapter.refresh) == "function" then
    vim.defer_fn(function() pcall(adapter.refresh) end, 100)
  end
end

-- ── Dim fallback (for adapters without a native hide API) ─────────────────────

local _ns = vim.api.nvim_create_namespace("filetree_ignore_list")

---@param names string[]
local function apply_dim(names)
  local set = {}
  for _, n in ipairs(names) do set[n:lower()] = true end

  local function render(bufnr)
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, _ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
      local name = (line:match("([^/\\%s]+)%s*$") or ""):lower()
      if name ~= "" and set[name] then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, i - 1, 0, {
          line_hl_group = "Comment",
          priority      = 89,
        })
      end
    end
  end

  local aug = au.group("filetree_ignore_list_dim", true)
  au.acmd({ "BufEnter", "TextChanged" }, {
    group   = aug,
    pattern = { "neo-tree://*", "NvimTree_*" },
    callback = function(ev) render(ev.buf) end,
  })
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeIgnoreListConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end

  local names = resolve_names(config.names)
  if #names == 0 then return end

  if adapter.name == "neotree" then
    apply_neotree(names, adapter)
  else
    apply_dim(names)
  end
end

function M.teardown()
  pcall(vim.api.nvim_del_augroup_by_name, "filetree_ignore_list_dim")
end

return M
