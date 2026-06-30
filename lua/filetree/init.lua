---@module 'filetree'
---@brief filetree.nvim — adapter-agnostic filetree features for Neovim.
---@description
--- Entry point. Call require("filetree").setup({}) with your configuration.
--- See :help filetree or README.md for full option reference.

local config_mod  = require("filetree.config")
local adapter_mod = require("filetree.adapter")
local notify      = require("filetree.util.notify").create("[filetree]")

local M = {}

---@type boolean
local _initialized = false

-- ── Feature registry ─────────────────────────────────────────────────────────

---@type table<string, { mod: string, key: string }>
local FEATURES = {
  picker              = { mod = "filetree.features.picker",              key = "picker"              },
  layout_guard        = { mod = "filetree.features.layout_guard",        key = "layout_guard"        },
  cwd_sync            = { mod = "filetree.features.cwd_sync",            key = "cwd_sync"            },
  current_hl          = { mod = "filetree.features.current_hl",          key = "current_hl"          },
  safety              = { mod = "filetree.features.safety",              key = "safety"              },
  trash               = { mod = "filetree.features.trash",               key = "trash"               },
  watcher_quarantine  = { mod = "filetree.features.watcher_quarantine",  key = "watcher_quarantine"  },
  marks               = { mod = "filetree.features.marks",               key = "marks"               },
  diff                = { mod = "filetree.features.diff",                key = "diff"                },
  project_root        = { mod = "filetree.features.project_root",        key = "project_root"        },
  path_utils          = { mod = "filetree.features.path_utils",          key = "path_utils"          },
  git_status          = { mod = "filetree.features.git_status",          key = "git_status"          },
  bookmarks           = { mod = "filetree.features.bookmarks",           key = "bookmarks"           },
  preview             = { mod = "filetree.features.preview",             key = "preview"             },
}

---@type table<string, table>  name → loaded feature module
local _active_features = {}

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

  -- Set up each enabled feature
  local feat_cfg = cfg.features or {}
  for name, info in pairs(FEATURES) do
    local fcfg = feat_cfg[name]
    if fcfg and fcfg.enabled ~= false then
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

---Register a custom adapter.
---Must be called before setup().
---@param adapter FiletreeAdapter
function M.register_adapter(adapter)
  adapter_mod.register(adapter)
end

---Return true when setup() has completed successfully.
---@return boolean
function M.is_initialized()
  return _initialized
end

return M
