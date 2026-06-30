---@module 'filetree.health'
---@brief :checkhealth filetree — validates adapter availability and feature config.

local M = {}

function M.check()
  vim.health.start("filetree.nvim")

  -- ── Neovim version ────────────────────────────────────────────────────────
  local version = vim.version()
  if version.major == 0 and version.minor < 8 then
    vim.health.error("Neovim >= 0.8 is required (found " .. tostring(version) .. ")")
  else
    vim.health.ok("Neovim " .. tostring(version))
  end

  -- ── Configuration ─────────────────────────────────────────────────────────
  local ok_cfg, config_mod = pcall(require, "filetree.config")
  if not ok_cfg then
    vim.health.error("filetree.config could not be loaded: " .. tostring(config_mod))
    return
  end

  local cfg = config_mod.get()
  if vim.tbl_isempty(cfg) then
    vim.health.warn("filetree.setup() has not been called yet")
    return
  end
  vim.health.ok("Configuration loaded (adapter = " .. tostring(cfg.adapter) .. ")")

  local valid, err = config_mod.validate()
  if not valid then
    vim.health.error("Config validation failed: " .. (err or "unknown"))
  else
    vim.health.ok("Config validated")
  end

  -- ── Adapters ──────────────────────────────────────────────────────────────
  vim.health.start("filetree.nvim — adapters")

  local adapters = {
    { name = "neotree",  plugin = "neo-tree" },
    { name = "nvimtree", plugin = "nvim-tree" },
  }

  local found_any = false
  for _, a in ipairs(adapters) do
    local avail = pcall(require, a.plugin)
    if avail then
      vim.health.ok(a.name .. " (" .. a.plugin .. ") — available")
      found_any = true
    else
      vim.health.warn(a.name .. " (" .. a.plugin .. ") — not installed")
    end
  end

  if not found_any then
    vim.health.error("No supported filetree plugin found. Install neo-tree.nvim or nvim-tree.lua.")
  end

  -- ── Active adapter ────────────────────────────────────────────────────────
  local ok_reg, adapter_mod = pcall(require, "filetree.adapter")
  if ok_reg then
    local active = adapter_mod.get()
    if active then
      local is_open = active.is_open()
      vim.health.ok("Active adapter: " .. active.name .. (is_open and " (open)" or " (closed)"))
    else
      vim.health.info("No adapter resolved yet (call setup() first)")
    end
  end

  -- ── Features ──────────────────────────────────────────────────────────────
  vim.health.start("filetree.nvim — features")

  local feat_cfg = cfg.features or {}
  local features = {
    { key = "picker",             name = "Quick Picker"          },
    { key = "layout_guard",       name = "Layout Guard"          },
    { key = "cwd_sync",           name = "CWD Sync"              },
    { key = "current_hl",         name = "Current Highlight"     },
    { key = "safety",             name = "Safety / Backup"       },
    { key = "trash",              name = "Trash + Undo"          },
    { key = "watcher_quarantine", name = "Watcher Quarantine"    },
    { key = "marks",              name = "Node Marks"            },
    { key = "diff",               name = "File Diff"             },
    { key = "project_root",       name = "Project Root"          },
    { key = "path_utils",         name = "Path Utilities"        },
    { key = "git_status",         name = "Git Status"            },
    { key = "bookmarks",          name = "Bookmarks"             },
    { key = "preview",            name = "File Preview"          },
    { key = "rename_batch",       name = "Rename Batch"          },
    { key = "session",            name = "Session"               },
    { key = "open_terminal",      name = "Open Terminal"         },
    { key = "copy_move",          name = "Copy / Move"           },
    { key = "find_files",         name = "Find Files"            },
    { key = "filter",             name = "Filter"                },
    { key = "grep_in_dir",        name = "Grep In Dir"           },
    { key = "recent_files",       name = "Recent Files"          },
    { key = "breadcrumbs",        name = "Breadcrumbs"           },
    { key = "lsp_diagnostics",    name = "LSP Diagnostics"       },
    { key = "size_info",          name = "Size Info"             },
    { key = "notes",              name = "Notes"                 },
    { key = "create_from_template", name = "Create From Template" },
    { key = "symlink",            name = "Symlink"               },
    { key = "auto_reveal",        name = "Auto Reveal"           },
    { key = "archive",            name = "Archive (zip/tar)"     },
    { key = "git_actions",        name = "Git Actions"           },
    { key = "auto_resize",        name = "Auto Resize"           },
    { key = "ignore_patterns",    name = "Ignore Patterns"       },
    { key = "file_watcher",       name = "File Watcher"          },
    { key = "hooks_api",          name = "Hooks API"             },
    { key = "compare_dirs",       name = "Compare Dirs"          },
    { key = "pin_node",           name = "Pin Node"              },
    { key = "workspace",          name = "Workspace"             },
    { key = "color_labels",       name = "Color Labels"          },
    { key = "jump_list",          name = "Jump List"             },
    { key = "outline",            name = "Outline"               },
    { key = "duplicate_node",         name = "Duplicate Node"          },
    { key = "git_blame",              name = "Git Blame"               },
    { key = "open_with",              name = "Open With"               },
    { key = "smart_rename",           name = "Smart Rename (LSP)"      },
    { key = "tag_system",             name = "Tag System"              },
    { key = "telescope_integration",  name = "Telescope Integration"   },
    { key = "path_copy",              name = "Path Copy"               },
    { key = "diagnostics_filter",     name = "Diagnostics Filter"      },
    { key = "live_search",            name = "Live Search"             },
  }

  -- Extra check for trash backend availability
  local trash_cfg = feat_cfg["trash"]
  if trash_cfg and trash_cfg.enabled then
    local ok_tp, tp = pcall(require, "filetree.features.trash.platform")
    if ok_tp then
      if tp.available() then
        vim.health.ok("Trash backend: " .. tp.backend_name())
      else
        vim.health.warn("No trash backend found — trash feature may not work")
      end
    end
  end

  -- Watcher quarantine: note Windows-only relevance
  local wq_cfg = feat_cfg["watcher_quarantine"]
  if wq_cfg and wq_cfg.enabled then
    local plat_ok, plat = pcall(require, "filetree.util.platform")
    if plat_ok and not plat.is_windows() and not plat.is_wsl() then
      vim.health.info("watcher_quarantine: no-op on non-Windows platforms")
    end
  end

  for _, f in ipairs(features) do
    local fcfg = feat_cfg[f.key]
    if fcfg and fcfg.enabled then
      vim.health.ok(f.name .. " — enabled")
    elseif fcfg then
      vim.health.info(f.name .. " — disabled")
    else
      vim.health.info(f.name .. " — not configured (using defaults)")
    end
  end

  -- ── Optional dependencies ─────────────────────────────────────────────────
  vim.health.start("filetree.nvim — optional dependencies")

  local optionals = {
    { mod = "telescope",    label = "Telescope (for future telescope integration)" },
    { mod = "fzf-lua",      label = "fzf-lua (for future fzf integration)"        },
  }
  for _, o in ipairs(optionals) do
    if pcall(require, o.mod) then
      vim.health.ok(o.label .. " — found")
    else
      vim.health.info(o.label .. " — not installed (optional)")
    end
  end
end

return M
