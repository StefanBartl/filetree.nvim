---@module 'filetree'
---@brief filetree.nvim — adapter-agnostic filetree features for Neovim.
---@description
--- Entry point. Call require("filetree").setup({}) with your configuration.
--- See :help filetree or README.md for full option reference.

local config_mod  = require("filetree.config")
local adapter_mod = require("filetree.adapter")
local commands    = require("filetree.commands")
local registry    = require("filetree.features")
local notify      = require("filetree.util.notify").create("[filetree]")

local M = {}

---@type boolean
local _initialized = false

-- ── Feature registry ─────────────────────────────────────────────────────────
-- The name → module-path mapping lives in `filetree.features` (a single source of
-- truth) so features can be organized into category subfolders without any
-- consumer hard-coding those paths.
local FEATURES = registry.FEATURES

-- ── Default-disabled features ─────────────────────────────────────────────────
--
-- filetree.nvim is opt-out: every feature in FEATURES is ON by default. The user
-- disables what they don't want with `{ enabled = false }`. The short list below
-- is the exception — features that stay OFF until explicitly enabled, each for a
-- concrete reason:
--
--   cwd_sync              Changes the global cwd automatically on buffer switch;
--                         aggressive and overlaps auto_reveal / tree_traverse.
--   current_hl            Purely cosmetic; ships hardcoded colours that only fit
--                         some colorschemes — better tuned by the user.
--   safety                A backup API with no keymaps; enabling it has no visible
--                         effect unless other code calls into it.
--   auto_resize           Automatic width management fights the manual
--                         window_size_cycler (kept on by default).
--   git_actions           Default `gs` collides with live_search, and it mutates
--                         the git index (stage/unstage) from the tree.
--   path_utils            Redundant with path_copy (kept on by default); enabling
--                         both ships two overlapping path-copy keymap families.
--   harpoon_integration   Hard-requires the external harpoon plugin.
--   telescope_integration Hard-requires telescope; redundant with the
--                         builtin-fallback find_or_grep_menu / find_files.
--   tree_open_keymaps     Binds global (not tree-local) normal-mode keys — too
--                         opinionated to enable without explicit opt-in.
--
---@type table<string, boolean>
local DEFAULT_DISABLED = {
  cwd_sync              = true,
  current_hl            = true,
  safety                = true,
  auto_resize           = true,
  git_actions           = true,
  path_utils            = true,
  harpoon_integration   = true,
  telescope_integration = true,
  tree_open_keymaps     = true,
}

---@type table<string, table>  name → loaded feature module
local _active_features = {}

---@type integer?
local _adapter_keymaps_augroup = nil

-- ── Setup ─────────────────────────────────────────────────────────────────────

---Initialize filetree.nvim.
---@param user_config FiletreeConfig?
function M.setup(user_config)
  config_mod.setup(user_config)

  local ok, err = config_mod.validate()
  if not ok then
    notify.error("Invalid config: " .. (err or "?"))
    return
  end

  local cfg = config_mod.get()

  -- Resolve adapter
  local adapter = adapter_mod.resolve(cfg.adapter)
  if not adapter then
    notify.error("Could not resolve adapter '" .. cfg.adapter .. "'. Aborting setup.")
    return
  end

  -- Tear down previous features (re-setup is idempotent)
  for _, feat in pairs(_active_features) do
    if type(feat.teardown) == "function" then
      pcall(feat.teardown)
    end
  end
  _active_features = {}

  -- Set up each enabled feature.
  -- Opt-out model: a feature runs unless the user set `enabled = false`, or it is
  -- in DEFAULT_DISABLED and the user did not explicitly set `enabled = true`.
  local feat_cfg = cfg.features or {}
  for name, info in pairs(FEATURES) do
    local fcfg = feat_cfg[name]
    local enabled
    if type(fcfg) == "table" and fcfg.enabled ~= nil then
      enabled = fcfg.enabled                 -- explicit user choice always wins
    else
      enabled = not DEFAULT_DISABLED[name]   -- default: on, except the opt-in few
    end
    if enabled then
      fcfg = fcfg or {}
      fcfg.enabled = true
      feat_cfg[name] = fcfg                   -- keep M.config() in sync
      local ok2, feat_mod = pcall(require, info.mod)
      if ok2 and type(feat_mod.setup) == "function" then
        local ok3, setup_err = pcall(feat_mod.setup, fcfg, adapter)
        if ok3 then
          _active_features[name] = feat_mod
        else
          notify.warn("Feature '" .. name .. "' setup failed: " .. tostring(setup_err))
        end
      else
        notify.warn("Feature module '" .. info.mod .. "' not found or has no setup()")
      end
    end
  end

  commands.setup(cfg.command)

  -- After registering all FileType autocmds, re-fire them for any tree buffer
  -- that is already open.  Handles two cases:
  --   (a) filetree loads after the tree was opened (e.g. event="VeryLazy" in real config)
  --   (b) filetree.setup() is called a second time while the tree is already visible
  vim.schedule(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
        if ft == "neo-tree" or ft == "NvimTree" then
          -- Fire FileType with the tree buffer current so the feature autocmd
          -- callbacks see the correct ev.buf.  (pattern and buf are mutually
          -- exclusive in nvim_exec_autocmds, hence nvim_buf_call.)
          vim.api.nvim_buf_call(buf, function()
            vim.api.nvim_exec_autocmds("FileType", { pattern = ft, modeline = false })
          end)
        end
      end
    end
  end)

  -- Apply adapter_keymaps: override / noop the adapter's own native keymaps.
  -- false → <Nop>, string → remap target.
  -- Runs in vim.schedule inside a FileType autocmd to fire AFTER the adapter
  -- has set its own buffer-local keymaps.
  if type(cfg.adapter_keymaps) == "table" then
    if _adapter_keymaps_augroup then
      pcall(vim.api.nvim_del_augroup_by_id, _adapter_keymaps_augroup)
    end
    _adapter_keymaps_augroup = vim.api.nvim_create_augroup(
      "filetree_adapter_keymaps", { clear = true })

    local overrides = cfg.adapter_keymaps
    vim.api.nvim_create_autocmd("FileType", {
      group   = _adapter_keymaps_augroup,
      pattern = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          for key, target in pairs(overrides) do
            if target == false then
              vim.keymap.set("n", key, "<Nop>", {
                buffer = buf, silent = true,
                desc   = "Filetree: adapter keymap disabled",
              })
            elseif type(target) == "string" then
              -- remap: forward to the target key
              vim.keymap.set("n", key, target, {
                buffer = buf, silent = true,
                desc   = "Filetree: adapter keymap remapped",
              })
            end
          end
        end)
      end,
    })
  end

  -- Auto-inject filetree keymaps into neo-tree's window.mappings so they appear in
  -- the `?` cheatsheet — no user wiring needed beyond setup().  neo-tree's merged
  -- config only exists after its own setup() has run, which (with lazy=false) may
  -- be before or after ours; run once when Neovim has finished starting (all
  -- lazy=false plugin configs done), and immediately if we loaded post-startup.
  if adapter.name == "neotree" then
    local function do_inject()
      require("filetree.attach").inject(config_mod.get(), adapter)
    end
    if vim.v.vim_did_enter == 1 then
      vim.schedule(function() vim.defer_fn(do_inject, 50) end)
    else
      vim.api.nvim_create_autocmd("VimEnter", {
        once     = true,
        callback = function() vim.defer_fn(do_inject, 50) end,
      })
    end
  end

  _initialized = true
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Return the active adapter, or nil if setup was not called.
---@return FiletreeAdapter?
function M.adapter()
  return adapter_mod.get()
end

---Return the active configuration.
---@return FiletreeConfig
function M.config()
  return config_mod.get()
end

---Return a loaded feature module by name, or nil.
---@param name string
---@return table?
function M.feature(name)
  return _active_features[name]
end

---Return whether `name` is enabled under the current config and the opt-out
---rules: on by default unless the user set `enabled = false`, or it is in the
---default-disabled set and the user did not explicitly set `enabled = true`.
---@param name string
---@return boolean
function M.is_feature_enabled(name)
  local features = config_mod.get().features
  local fcfg = features and features[name]
  if type(fcfg) == "table" and fcfg.enabled ~= nil then
    return fcfg.enabled == true
  end
  return not DEFAULT_DISABLED[name]
end

---Register a custom adapter.
---Must be called before setup().
---@param adapter FiletreeAdapter
function M.register_adapter(adapter)
  adapter_mod.register(adapter)
end

---Inject filetree feature keymaps into neo-tree's `window.mappings` so they show
---up in neo-tree's `?` cheatsheet.  Call BEFORE `require("neo-tree").setup(opts)`,
---passing the neo-tree opts table and the same config you give to `setup()`.
---No-op for non-neotree adapters (their help systems differ).
---@param opts table    neo-tree opts table (mutated in place).
---@param config FiletreeConfig  Same config table passed to setup().
---@return table opts
function M.attach(opts, config)
  return require("filetree.attach").neotree(opts, config)
end

---Return true when setup() has completed successfully.
---@return boolean
function M.is_initialized()
  return _initialized
end

return M
