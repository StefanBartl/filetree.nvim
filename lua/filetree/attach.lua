---@module 'filetree.attach'
---@brief Inject filetree feature keymaps into neo-tree's `window.mappings`.
---@description
--- filetree normally binds its keymaps via a FileType autocmd + `vim.keymap.set`
--- AFTER the adapter has set up its own buffer-local keymaps.  Those keymaps work,
--- but they are invisible to neo-tree's `?` cheatsheet, because that help screen is
--- generated purely from `state.resolved_mappings` — which neo-tree builds from the
--- `window.mappings` table (per source config and per live state).
---
--- Two ways to get filetree keymaps into that cheatsheet:
---
---   1. AUTOMATIC (default) — `filetree.setup()` calls `M.inject(config)` after
---      neo-tree is configured.  It writes `{ handler, desc }` entries into
---      `require("neo-tree").config[source].window.mappings` (so future tree states
---      pick them up) and into any already-open state's `window.mappings` (then
---      refreshes).  No user wiring required — just `require("filetree").setup{…}`.
---
---   2. EXPLICIT — `M.neotree(opts, config)` (exposed as `require("filetree").attach`)
---      writes the same entries into the `opts` table BEFORE you call
---      `require("neo-tree").setup(opts)`.  Use this if you prefer not to rely on
---      post-setup config mutation.
---
--- Either way neo-tree binds the key to `handler` (which calls the filetree feature
--- action) and lists it in `?` using `desc`.  The FileType autocmds still run and
--- re-bind the same keys to the same functions, so behaviour is identical with or
--- without this module — it only adds cheatsheet visibility.

local M = {}

-- ── Keymap spec ───────────────────────────────────────────────────────────────
-- feature → list of { field, method, desc, default }
--   field   config key holding the lhs (in cfg.features[feature][field])
--   method  name of the no-arg function on the feature module to call
--   desc    label shown in neo-tree's `?` cheatsheet
--   default lhs used when the user did not set `field`

---@class FiletreeAttachEntry
---@field field   string
---@field method  string
---@field desc    string
---@field default string?

---@type table<string, FiletreeAttachEntry[]>
local SPEC = {
  tree_traverse = {
    { field = "keymap_up",   method = "up",   desc = "filetree: parent dir (up)",       default = "-" },
    { field = "keymap_down", method = "down", desc = "filetree: set dir as root (down)", default = "+" },
  },
  marks = {
    { field = "keymap",            method = "toggle_current",     desc = "filetree: toggle mark",       default = "m" },
    { field = "keymap_all",        method = "mark_all_visible",   desc = "filetree: mark all visible",  default = "]m" },
    { field = "keymap_unmark_all", method = "unmark_all_visible", desc = "filetree: unmark all visible", default = "[m" },
    { field = "keymap_clear",      method = "clear_all",          desc = "filetree: clear all marks",   default = "<C-m>" },
    { field = "keymap_show",       method = "show",               desc = "filetree: show marked nodes", default = "<leader>ms" },
  },
  path_copy = {
    { field = "keymap_abs",          method = "copy_absolute",         desc = "filetree: copy absolute path",            default = "[a" },
    { field = "keymap_dirname",      method = "copy_dirname",          desc = "filetree: copy absolute parent directory", default = "]a" },
    { field = "keymap_project_root", method = "copy_project_root",     desc = "filetree: copy absolute project root",    default = "[R" },
    { field = "keymap_project_rel",  method = "copy_project_relative", desc = "filetree: copy path relative to project root", default = "]R" },
  },
  trash = {
    { field = "keymap",         method = "delete_current", desc = "filetree: trash current node",  default = "d" },
    { field = "keymap_undo",    method = "undo_last",       desc = "filetree: undo last trash",     default = "U" },
    { field = "keymap_history", method = "show_history",    desc = "filetree: show trash history",  default = "<leader>th" },
  },
  node_info = {
    { field = "keymap", method = "show_current", desc = "filetree: node info", default = "I" },
  },
  preview = {
    { field = "keymap", method = "toggle_or_open", desc = "filetree: toggle preview", default = "<Tab>" },
  },
  filter = {
    { field = "keymap", method = "enter", desc = "filetree: filter tree", default = "/" },
  },
  live_search = {
    { field = "keymap", method = "open", desc = "filetree: live search", default = "gs" },
  },
  window_size_cycler = {
    { field = "keymap", method = "cycle", desc = "filetree: cycle window size", default = "w" },
  },
  copy_file_list = {
    { field = "keymap_files_abs", method = "copy_files_abs", desc = "filetree: copy file list (abs)", default = "[f" },
    { field = "keymap_files_rel", method = "copy_files_rel", desc = "filetree: copy file list (rel)", default = "]f" },
    { field = "keymap_dirs_abs",  method = "copy_dirs_abs",  desc = "filetree: copy dir list (abs)",  default = "[F" },
    { field = "keymap_dirs_rel",  method = "copy_dirs_rel",  desc = "filetree: copy dir list (rel)",  default = "]F" },
  },
  markdown_links = {
    { field = "keymap",             method = "link_current",    desc = "filetree: markdown link for current node", default = "ML" },
    { field = "keymap_recursive",   method = "link_recursive",  desc = "filetree: markdown links recursively",     default = "MR" },
    { field = "keymap_from_marked", method = "link_from_marked", desc = "filetree: markdown links from marked",    default = "MM" },
  },
  buffer_save = {
    { field = "keymap_adjacent", method = "save_adjacent", desc = "filetree: save adjacent buffer", default = "<C-s>" },
    { field = "keymap_node",     method = "save_node",     desc = "filetree: save node buffer",     default = "<M-s>" },
  },
  open_replace = {
    { field = "keymap", method = "open_replace", desc = "filetree: open (replace buffer)", default = "O" },
  },
  open_variants = {
    { field = "keymap_vsplit",   method = "open_vsplit", desc = "filetree: open in vertical split",   default = "sg" },
    { field = "keymap_split",    method = "open_split",  desc = "filetree: open in horizontal split", default = "sv" },
    { field = "keymap_tabnew",   method = "open_tabnew", desc = "filetree: open in new tab",          default = "st" },
    { field = "keymap_badd",     method = "open_badd",   desc = "filetree: add to buffer list (no focus switch)", default = "gb" },
    { field = "keymap_badd_alt", method = "open_badd",   desc = "filetree: add to buffer list (no focus switch)", default = "<S-CR>" },
  },
  open_in_fm = {
    { field = "keymap", method = "open", desc = "filetree: open in file manager", default = "<leader>fm" },
  },
  shell_run = {
    { field = "keymap", method = "run", desc = "filetree: run shell command", default = "i" },
  },
  lua_require_copy = {
    { field = "keymap", method = "copy_require", desc = "filetree: copy as require()", default = "rq" },
  },
  pdf_open = {
    { field = "keymap_open",     method = "open_default",  desc = "filetree: open PDF (pdfport)",      default = "gp" },
    { field = "keymap_text",     method = "open_text",     desc = "filetree: open PDF as text",        default = nil  },
    { field = "keymap_system",   method = "open_system",   desc = "filetree: open PDF in system viewer", default = nil  },
    { field = "keymap_terminal", method = "open_terminal", desc = "filetree: open PDF in terminal",    default = nil  },
  },
}

-- ── Helpers ─────────────────────────────────────────────────────────────────────

---Resolve the lhs for an entry from the feature config; nil = skip.
---@param feat_cfg table
---@param entry FiletreeAttachEntry
---@return string?
local function resolve_key(feat_cfg, entry)
  local v = feat_cfg[entry.field]
  if v == false then return nil end        -- explicitly disabled
  if type(v) == "string" and v ~= "" then return v end
  if v == nil then return entry.default end
  return nil
end

---Build a handler that lazily calls feature.<method>().  neo-tree invokes the
---handler with `state`; the feature actions take no args, so it is ignored.
---@param feature string
---@param method string
---@return function
local function make_handler(feature, method)
  return function()
    local ok, mod = require("filetree.features").load(feature)
    if not ok then return end
    local fn = mod[method]
    if type(fn) == "function" then
      pcall(fn)
    end
  end
end

---Normalize a neo-tree map key (e.g. "<C-M>" → "<c-m>") so injected entries merge
---and display consistently with neo-tree's own normalized mappings.
---@param key string
---@return string
local function normalize_key(key)
  local ok, helper = pcall(require, "neo-tree.setup.mapping-helper")
  if ok and type(helper.normalize_map_key) == "function" then
    local nk = helper.normalize_map_key(key)
    if type(nk) == "string" then return nk end
  end
  return key
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Build the filetree keymap table for neo-tree from a filetree config.
---@param config table            Filetree config (as passed to setup()).
---@return table<string, table>   { [lhs] = { handler, desc = "…" } }
function M.build_mappings(config)
  local mappings = {}
  local feat_cfg = (config and config.features) or {}
  -- Opt-out model: every feature in SPEC is on by default (none are in the
  -- default-disabled set), so a missing config table still means "enabled".
  -- Only an explicit `enabled = false` removes it from the cheatsheet.
  for feature, entries in pairs(SPEC) do
    local fc = feat_cfg[feature] or {}
    if fc.enabled ~= false then
      for _, entry in ipairs(entries) do
        local key = resolve_key(fc, entry)
        if key then
          mappings[normalize_key(key)] = {
            make_handler(feature, entry.method),
            desc = entry.desc,
          }
        end
      end
    end
  end
  return mappings
end

---Inject enabled filetree feature keymaps into a neo-tree `opts` table's
---window.mappings.  Call BEFORE `require("neo-tree").setup(opts)`.
---@param opts table       The neo-tree opts table you will pass to setup().
---@param config table     The filetree config table (same one passed to setup()).
---@return table opts      The mutated opts (for chaining).
function M.neotree(opts, config)
  opts = opts or {}
  opts.window = opts.window or {}
  opts.window.mappings = opts.window.mappings or {}
  local mappings = M.build_mappings(config)
  for k, v in pairs(mappings) do
    opts.window.mappings[k] = v
  end
  return opts
end

---Merge `mappings` into every window.mappings table in `windows`.
---@param windows table[]  list of neo-tree `window` config tables
---@param mappings table
local function merge_into_windows(windows, mappings)
  for _, w in ipairs(windows) do
    if type(w) == "table" then
      w.mappings = w.mappings or {}
      for k, v in pairs(mappings) do
        w.mappings[k] = v
      end
    end
  end
end

---Automatically inject filetree keymaps into the LIVE neo-tree config + any open
---states, so they show up in `?` without the user wiring up `M.neotree`.
---Safe to call repeatedly (idempotent merge).  Returns false if neo-tree's config
---is not ready yet (caller should retry, e.g. at VimEnter).
---@param config table               Filetree config (as passed to setup()).
---@param adapter FiletreeAdapter?    Active adapter (used for refresh).
---@return boolean ok
function M.inject(config, adapter)
  local ok_nt, nt = pcall(require, "neo-tree")
  if not ok_nt then return false end
  local ncfg = nt.config or (type(nt.ensure_config) == "function" and nt.ensure_config())
  if type(ncfg) ~= "table" then return false end

  local mappings = M.build_mappings(config)
  if vim.tbl_isempty(mappings) then return true end

  -- 1. Future states: neo-tree deepcopies each state from these config tables.
  local windows = {}
  if type(ncfg.window) == "table" then windows[#windows + 1] = ncfg.window end
  for _, src in ipairs({ "filesystem", "buffers", "git_status", "document_symbols" }) do
    local s = ncfg[src]
    if type(s) == "table" and type(s.window) == "table" then
      windows[#windows + 1] = s.window
    end
  end
  merge_into_windows(windows, mappings)

  -- 2. Already-open states: patch live window.mappings and force a rebuild of
  --    resolved_mappings (which neo-tree regenerates from window.mappings on render).
  local patched_live = false
  local ok_mgr, mgr = pcall(require, "neo-tree.sources.manager")
  if ok_mgr and type(mgr._get_all_states) == "function" then
    for _, state in ipairs(mgr._get_all_states()) do
      if type(state.window) == "table" then
        state.window.mappings = state.window.mappings or {}
        for k, v in pairs(mappings) do state.window.mappings[k] = v end
        state.resolved_mappings = nil
        patched_live = true
      end
    end
  end

  -- 3. Refresh so the open tree re-renders and rebinds/re-resolves mappings.
  if patched_live and adapter and type(adapter.refresh) == "function" then
    vim.defer_fn(function() pcall(adapter.refresh) end, 50)
  end

  return true
end

---@type integer?
local _popup_augroup = nil

---Restore native `/` search in neo-tree's help (`?`) popup.
---
---neo-tree's help screen maps *every* tree key inside the popup to run that
---command (so you can press a key to execute it). That means `/` runs the tree
---filter instead of searching the help text. This registers a `neo-tree-popup`
---FileType autocmd that removes the popup's buffer-local `/` (and `?`) maps, so
---they fall back to Neovim's built-in `/` search and native paging. `n`/`N` are
---not mapped by neo-tree, so they already page through matches natively.
---Idempotent — safe to call once at setup.
---@param keys string[]?  Keys to hand back to native behaviour (default { "/" }).
function M.native_search_in_help(keys)
  keys = keys or { "/" }
  if _popup_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _popup_augroup)
  end
  _popup_augroup = vim.api.nvim_create_augroup("filetree_neotree_popup_search", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group   = _popup_augroup,
    pattern = "neo-tree-popup",
    callback = function(ev)
      local buf = ev.buf
      -- Defer past neo-tree's own popup:map() calls so our removal wins.
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        for _, key in ipairs(keys) do
          pcall(vim.keymap.del, "n", key, { buffer = buf })
        end
      end)
    end,
  })
end

return M
