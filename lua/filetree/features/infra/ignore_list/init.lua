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

---Merge `names` into a filtered_items hide_by_name value, in place, returning
---a dict (`{name = true, …}`).
---
---neo-tree's own `filesystem.setup()` converts `hide_by_name` from the
---user-facing `string[]` shape into this dict shape (`utils.list_to_dict`) so
---that its render-time filter (`file-items.lua`: `f.hide_by_name[name]`) is an
---O(1) lookup — and it does this conversion exactly once, during its own
---setup(), which normally runs *before* filetree's (event="VeryLazy"). Adding
---entries as if `hide_by_name` were still an array (`ipairs` + `#+1` append, the
---previous implementation here) silently does nothing: neo-tree's filter never
---iterates the table, it only ever indexes it by name, so array-shaped entries
---are invisible to it. This must always end up dict-shaped, regardless of
---whether neo-tree already converted it (dict), the user pre-set it in their
---own neo-tree opts (array, not yet converted), or it was never set (nil).
---@param existing table?  Current filtered_items.hide_by_name value (any shape, or nil).
---@param names    string[]
---@return table<string, true>
local function merge_hide_by_name(existing, names)
  local dict = {}
  if type(existing) == "table" then
    for k, v in pairs(existing) do
      if type(k) == "string" then
        dict[k] = v            -- already dict-shaped (converted by neo-tree)
      elseif type(v) == "string" then
        dict[v] = true         -- still array-shaped (not yet converted)
      end
    end
  end
  for _, name in ipairs(names) do
    dict[name] = true
  end
  return dict
end

---Inject names into neo-tree's filtered_items.hide_by_name (both the merged
---config, for future states, and any already-open state) and refresh.
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

  -- 1. Future states: neo-tree deepcopies from this config template.
  ncfg.filesystem.filtered_items = ncfg.filesystem.filtered_items or {}
  local fi = ncfg.filesystem.filtered_items
  fi.hide_by_name = merge_hide_by_name(fi.hide_by_name, names)
  if fi.visible == nil then fi.visible = false end

  -- 2. Already-open state(s): patch live filtered_items directly, in case
  -- neo-tree already built its filesystem-source state from the config
  -- before we got here (shares the config's nested tables in some neo-tree
  -- versions, but not reliably across all of them — patch explicitly either way).
  local ok_mgr, mgr = pcall(require, "neo-tree.sources.manager")
  if ok_mgr and type(mgr._get_all_states) == "function" then
    for _, state in ipairs(mgr._get_all_states()) do
      if state.filtered_items then
        state.filtered_items.hide_by_name = merge_hide_by_name(state.filtered_items.hide_by_name, names)
        if state.filtered_items.visible == nil then state.filtered_items.visible = false end
      end
    end
  end

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
