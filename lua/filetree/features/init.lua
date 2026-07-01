---@module 'filetree.features'
---@brief Feature registry — the single source of truth mapping feature names to
---their module paths and categories.
---@description
--- Every site that loads a feature *by name* — the setup loop, the neo-tree
--- cheatsheet injector, quick_open, telescope_integration, and cross-feature
--- lookups — resolves through this module. Feature files therefore live in
--- category subfolders (`features/<category>/<name>/`) without any consumer
--- hard-coding those paths: moving a feature between categories means editing
--- exactly one line here.

local M = {}

---@class FiletreeFeatureInfo
---@field mod      string  Lua module path of the feature.
---@field category string  Grouping category (also the on-disk subfolder).

---@type table<string, FiletreeFeatureInfo>
M.FEATURES = {
  -- ── nav: navigation, reveal, window lifecycle ──────────────────────────────
  picker            = { mod = "filetree.features.nav.picker",            category = "nav" },
  tree_traverse     = { mod = "filetree.features.nav.tree_traverse",     category = "nav" },
  jump_list         = { mod = "filetree.features.nav.jump_list",         category = "nav" },
  quick_open        = { mod = "filetree.features.nav.quick_open",        category = "nav" },
  reveal_alt        = { mod = "filetree.features.nav.reveal_alt",        category = "nav" },
  auto_reveal       = { mod = "filetree.features.nav.auto_reveal",       category = "nav" },
  auto_resize       = { mod = "filetree.features.nav.auto_resize",       category = "nav" },
  cwd_sync          = { mod = "filetree.features.nav.cwd_sync",          category = "nav" },
  layout_guard      = { mod = "filetree.features.nav.layout_guard",      category = "nav" },
  tree_open_keymaps = { mod = "filetree.features.nav.tree_open_keymaps", category = "nav" },

  -- ── ui: cosmetic / display ─────────────────────────────────────────────────
  window_style       = { mod = "filetree.features.ui.window_style",       category = "ui" },
  window_size_cycler = { mod = "filetree.features.ui.window_size_cycler", category = "ui" },
  current_hl         = { mod = "filetree.features.ui.current_hl",         category = "ui" },
  cursor_hide        = { mod = "filetree.features.ui.cursor_hide",        category = "ui" },
  tree_reset         = { mod = "filetree.features.ui.tree_reset",         category = "ui" },
  preview            = { mod = "filetree.features.ui.preview",            category = "ui" },
  node_info          = { mod = "filetree.features.ui.node_info",          category = "ui" },
  breadcrumbs        = { mod = "filetree.features.ui.breadcrumbs",        category = "ui" },
  size_info          = { mod = "filetree.features.ui.size_info",          category = "ui" },
  color_labels       = { mod = "filetree.features.ui.color_labels",       category = "ui" },
  ignore_patterns    = { mod = "filetree.features.ui.ignore_patterns",    category = "ui" },

  -- ── fileops: create / edit / move ──────────────────────────────────────────
  smart_create         = { mod = "filetree.features.fileops.smart_create",         category = "fileops" },
  copy_move            = { mod = "filetree.features.fileops.copy_move",            category = "fileops" },
  duplicate_node       = { mod = "filetree.features.fileops.duplicate_node",       category = "fileops" },
  rename_batch         = { mod = "filetree.features.fileops.rename_batch",         category = "fileops" },
  smart_rename         = { mod = "filetree.features.fileops.smart_rename",         category = "fileops" },
  symlink              = { mod = "filetree.features.fileops.symlink",              category = "fileops" },
  create_from_template = { mod = "filetree.features.fileops.create_from_template", category = "fileops" },
  archive              = { mod = "filetree.features.fileops.archive",             category = "fileops" },
  trash                = { mod = "filetree.features.fileops.trash",               category = "fileops" },
  open_replace         = { mod = "filetree.features.fileops.open_replace",         category = "fileops" },
  buffer_save          = { mod = "filetree.features.fileops.buffer_save",          category = "fileops" },
  file_permissions     = { mod = "filetree.features.fileops.file_permissions",     category = "fileops" },

  -- ── search: filter / find / grep ───────────────────────────────────────────
  filter            = { mod = "filetree.features.search.filter",            category = "search" },
  live_search       = { mod = "filetree.features.search.live_search",       category = "search" },
  find_files        = { mod = "filetree.features.search.find_files",        category = "search" },
  find_or_grep_menu = { mod = "filetree.features.search.find_or_grep_menu", category = "search" },
  grep_in_dir       = { mod = "filetree.features.search.grep_in_dir",       category = "search" },
  recent_files      = { mod = "filetree.features.search.recent_files",      category = "search" },

  -- ── paths: clipboard / path tools ──────────────────────────────────────────
  path_copy        = { mod = "filetree.features.paths.path_copy",        category = "paths" },
  path_utils       = { mod = "filetree.features.paths.path_utils",       category = "paths" },
  lua_require_copy = { mod = "filetree.features.paths.lua_require_copy", category = "paths" },
  copy_file_list   = { mod = "filetree.features.paths.copy_file_list",   category = "paths" },

  -- ── git ────────────────────────────────────────────────────────────────────
  git_status = { mod = "filetree.features.git.git_status", category = "git" },
  git_blame  = { mod = "filetree.features.git.git_blame",  category = "git" },
  git_actions = { mod = "filetree.features.git.git_actions", category = "git" },

  -- ── org: marks / organization ──────────────────────────────────────────────
  marks     = { mod = "filetree.features.org.marks",     category = "org" },
  bookmarks = { mod = "filetree.features.org.bookmarks", category = "org" },
  pin_node  = { mod = "filetree.features.org.pin_node",  category = "org" },
  tag_system = { mod = "filetree.features.org.tag_system", category = "org" },
  notes     = { mod = "filetree.features.org.notes",     category = "org" },
  workspace = { mod = "filetree.features.org.workspace", category = "org" },
  session   = { mod = "filetree.features.org.session",   category = "org" },

  -- ── system: external programs ──────────────────────────────────────────────
  open_in_fm    = { mod = "filetree.features.system.open_in_fm",    category = "system" },
  open_with     = { mod = "filetree.features.system.open_with",     category = "system" },
  open_terminal = { mod = "filetree.features.system.open_terminal", category = "system" },
  shell_run     = { mod = "filetree.features.system.shell_run",     category = "system" },

  -- ── lsp: diagnostics / symbols ─────────────────────────────────────────────
  lsp_diagnostics    = { mod = "filetree.features.lsp.lsp_diagnostics",    category = "lsp" },
  outline            = { mod = "filetree.features.lsp.outline",            category = "lsp" },
  diagnostics_filter = { mod = "filetree.features.lsp.diagnostics_filter", category = "lsp" },

  -- ── compare: diff / directory comparison ───────────────────────────────────
  diff         = { mod = "filetree.features.compare.diff",         category = "compare" },
  compare_dirs = { mod = "filetree.features.compare.compare_dirs", category = "compare" },

  -- ── integration: external plugins ──────────────────────────────────────────
  harpoon_integration   = { mod = "filetree.features.integration.harpoon_integration",   category = "integration" },
  telescope_integration = { mod = "filetree.features.integration.telescope_integration", category = "integration" },

  -- ── infra: plumbing shared by other features ───────────────────────────────
  ignore_list        = { mod = "filetree.features.infra.ignore_list",        category = "infra" },
  project_root       = { mod = "filetree.features.infra.project_root",       category = "infra" },
  file_watcher       = { mod = "filetree.features.infra.file_watcher",       category = "infra" },
  watcher_quarantine = { mod = "filetree.features.infra.watcher_quarantine", category = "infra" },
  hooks_api          = { mod = "filetree.features.infra.hooks_api",          category = "infra" },
  safety             = { mod = "filetree.features.infra.safety",             category = "infra" },
}

---Display order of categories (for docs / health grouping).
---@type string[]
M.CATEGORY_ORDER = {
  "nav", "ui", "fileops", "search", "paths",
  "git", "org", "system", "lsp", "compare", "integration", "infra",
}

---Return the module path for a feature, or nil when the name is unknown.
---@param name string
---@return string?
function M.mod_path(name)
  local info = M.FEATURES[name]
  return info and info.mod or nil
end

---Load a feature module by name. Returns nil when the name is unknown or the
---module fails to load.
---@param name string
---@return table?
function M.require(name)
  local ok, mod = M.load(name)
  return ok and mod or nil
end

---Load a feature module by name, preserving `pcall`'s `(ok, module)` return so
---it is a drop-in for the old `pcall(require, "filetree.features.<name>")` call
---sites. Returns `(false, nil)` for an unknown name.
---@param name string
---@return boolean ok, table|nil mod
function M.load(name)
  local info = M.FEATURES[name]
  if not info then return false, nil end
  return pcall(require, info.mod)
end

---Return feature names grouped by category (each list sorted).
---@return table<string, string[]>
function M.by_category()
  local out = {}
  for name, info in pairs(M.FEATURES) do
    out[info.category] = out[info.category] or {}
    table.insert(out[info.category], name)
  end
  for _, list in pairs(out) do
    table.sort(list)
  end
  return out
end

return M
