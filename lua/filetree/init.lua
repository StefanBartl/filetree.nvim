---@module 'filetree'
---@brief filetree.nvim — adapter-agnostic filetree features for Neovim.
---@description
--- Entry point. Call require("filetree").setup({}) with your configuration.
--- See :help filetree or README.md for full option reference.

local config_mod  = require("filetree.config")
local adapter_mod = require("filetree.adapter")
local commands    = require("filetree.commands")
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
  rename_batch        = { mod = "filetree.features.rename_batch",        key = "rename_batch"        },
  session             = { mod = "filetree.features.session",             key = "session"             },
  open_terminal       = { mod = "filetree.features.open_terminal",       key = "open_terminal"       },
  copy_move           = { mod = "filetree.features.copy_move",           key = "copy_move"           },
  find_files          = { mod = "filetree.features.find_files",          key = "find_files"          },
  filter              = { mod = "filetree.features.filter",              key = "filter"              },
  grep_in_dir         = { mod = "filetree.features.grep_in_dir",         key = "grep_in_dir"         },
  recent_files        = { mod = "filetree.features.recent_files",        key = "recent_files"        },
  breadcrumbs         = { mod = "filetree.features.breadcrumbs",         key = "breadcrumbs"         },
  lsp_diagnostics     = { mod = "filetree.features.lsp_diagnostics",     key = "lsp_diagnostics"     },
  size_info           = { mod = "filetree.features.size_info",           key = "size_info"           },
  notes               = { mod = "filetree.features.notes",               key = "notes"               },
  create_from_template = { mod = "filetree.features.create_from_template", key = "create_from_template" },
  symlink             = { mod = "filetree.features.symlink",             key = "symlink"             },
  auto_reveal         = { mod = "filetree.features.auto_reveal",         key = "auto_reveal"         },
  archive             = { mod = "filetree.features.archive",             key = "archive"             },
  git_actions         = { mod = "filetree.features.git_actions",         key = "git_actions"         },
  auto_resize         = { mod = "filetree.features.auto_resize",         key = "auto_resize"         },
  ignore_patterns     = { mod = "filetree.features.ignore_patterns",     key = "ignore_patterns"     },
  file_watcher        = { mod = "filetree.features.file_watcher",        key = "file_watcher"        },
  hooks_api           = { mod = "filetree.features.hooks_api",           key = "hooks_api"           },
  compare_dirs        = { mod = "filetree.features.compare_dirs",        key = "compare_dirs"        },
  pin_node            = { mod = "filetree.features.pin_node",            key = "pin_node"            },
  workspace           = { mod = "filetree.features.workspace",           key = "workspace"           },
  color_labels        = { mod = "filetree.features.color_labels",        key = "color_labels"        },
  jump_list           = { mod = "filetree.features.jump_list",           key = "jump_list"           },
  outline             = { mod = "filetree.features.outline",             key = "outline"             },
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

  commands.setup()
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
