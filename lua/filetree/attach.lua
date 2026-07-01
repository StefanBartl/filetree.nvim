---@module 'filetree.attach'
---@brief Inject filetree feature keymaps into neo-tree's `window.mappings`.
---@description
--- filetree normally binds its keymaps via a FileType autocmd + `vim.keymap.set`
--- AFTER the adapter has set up its own buffer-local keymaps.  Those keymaps work,
--- but they are invisible to neo-tree's `?` cheatsheet, because that help screen is
--- generated purely from `state.resolved_mappings` — which neo-tree builds from the
--- `window.mappings` table passed to `require("neo-tree").setup(opts)`.
---
--- `attach(opts, config)` bridges that gap: called BEFORE `neo-tree.setup(opts)`, it
--- writes an entry `{ handler, desc = "…" }` into `opts.window.mappings` for every
--- enabled feature keymap.  neo-tree then:
---   * binds the key to `handler` (which calls the filetree feature action), and
---   * lists it in the `?` cheatsheet using `desc`.
---
--- The FileType autocmds still run and re-bind the same keys to the same functions,
--- so behaviour is identical whether or not `attach` is used — `attach` only adds
--- cheatsheet visibility (and native neo-tree multi-key `?` sub-menu grouping).
---
--- Usage (in your neo-tree `config` function, before `neo-tree.setup`):
---   local ft_opts = require("config.my_filetree_opts")  -- same table you pass to setup
---   require("filetree").attach(opts, ft_opts)
---   require("neo-tree").setup(opts)
---   ...
---   require("filetree").setup(ft_opts)

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
    { field = "keymap_abs",  method = "copy_absolute", desc = "filetree: copy absolute path", default = "[a" },
    { field = "keymap_rel",  method = "copy_relative", desc = "filetree: copy relative path", default = "]a" },
    { field = "keymap_name", method = "copy_name",     desc = "filetree: copy filename",      default = "<leader>yn" },
    { field = "keymap_pick", method = "pick",          desc = "filetree: copy path (pick)",   default = "<leader>yp" },
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
  find_or_grep_menu = {
    { field = "keymap", method = "open", desc = "filetree: find/grep menu", default = "<M-p>" },
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
  buffer_save = {
    { field = "keymap_adjacent", method = "save_adjacent", desc = "filetree: save adjacent buffer", default = "<C-s>" },
    { field = "keymap_node",     method = "save_node",     desc = "filetree: save node buffer",     default = "<M-s>" },
  },
  open_replace = {
    { field = "keymap", method = "open_replace", desc = "filetree: open (replace buffer)", default = "O" },
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
    local ok, mod = pcall(require, "filetree.features." .. feature)
    if not ok then return end
    local fn = mod[method]
    if type(fn) == "function" then
      pcall(fn)
    end
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Inject enabled filetree feature keymaps into neo-tree's window.mappings so they
---appear in the `?` cheatsheet.  Call BEFORE `require("neo-tree").setup(opts)`.
---@param opts table       The neo-tree opts table you will pass to setup().
---@param config table     The filetree config table (same one passed to setup()).
---@return table opts      The mutated opts (for chaining).
function M.neotree(opts, config)
  opts = opts or {}
  opts.window = opts.window or {}
  opts.window.mappings = opts.window.mappings or {}
  local mappings = opts.window.mappings

  local feat_cfg = (config and config.features) or {}

  for feature, entries in pairs(SPEC) do
    local fc = feat_cfg[feature]
    if type(fc) == "table" and fc.enabled ~= false then
      for _, entry in ipairs(entries) do
        local key = resolve_key(fc, entry)
        if key then
          mappings[key] = {
            make_handler(feature, entry.method),
            desc = entry.desc,
          }
        end
      end
    end
  end

  return opts
end

return M
