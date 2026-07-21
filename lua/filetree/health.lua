---@module 'filetree.health'
---@brief :checkhealth filetree — validates adapter availability and feature config.

local M = {}

function M.check()
  vim.health.start("filetree.nvim")

  -- lib.nvim: required for the :Filetree/:Ft command layer
  -- (lib.nvim.usercmd.composer), which registers unconditionally (no pcall).
  if pcall(require, "lib.nvim.usercmd.composer") then
    vim.health.ok("lib.nvim detected (:Filetree/:Ft command layer available)")
  else
    vim.health.error(
      "lib.nvim not found — :Filetree/:Ft will fail to register",
      { "Install \"StefanBartl/lib.nvim\" as a dependency" }
    )
  end

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
    { name = "neotree",  plugin = "neo-tree"        },
    { name = "nvimtree", plugin = "nvim-tree"       },
    { name = "netrw",    plugin = "netrw (builtin)" },
    { name = "oil",        plugin = "oil.nvim"   },
    { name = "mini_files", plugin = "mini.files" },
  }

  local found_any = false
  for _, a in ipairs(adapters) do
    -- netrw is always available as it is built in to Neovim
    local avail = a.name == "netrw" or pcall(require, a.plugin)
    if avail then
      vim.health.ok(a.name .. " (" .. a.plugin .. ") — available")
      found_any = true
    else
      vim.health.warn(a.name .. " (" .. a.plugin .. ") — not installed")
    end
  end

  if not found_any then
    vim.health.error("No supported filetree plugin found. Install neo-tree.nvim, nvim-tree.lua, oil.nvim, or mini.files.")
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

  -- ── Features (grouped by category, driven by the registry) ─────────────────
  local feat_cfg = cfg.features or {}
  local registry = require("filetree.features")

  -- Resolve enabled-state under the opt-out model (on by default unless the
  -- user disabled it, or it is in the default-disabled set).
  local ok_ft, ft = pcall(require, "filetree")
  local function is_enabled(key)
    if ok_ft and type(ft.is_feature_enabled) == "function" then
      return ft.is_feature_enabled(key)
    end
    local fc = feat_cfg[key]
    return type(fc) == "table" and fc.enabled == true
  end

  -- Extra check for trash backend availability
  if is_enabled("trash") then
    local ok_tp, tp = pcall(require, "filetree.features.fileops.trash.platform")
    if ok_tp then
      if tp.available() then
        vim.health.ok("Trash backend: " .. tp.backend_name())
      else
        vim.health.warn("No trash backend found — trash feature may not work")
      end
    end
  end

  -- pdf_open: pdfport.nvim is optional; without it PDFs open in the system viewer
  if is_enabled("pdf_open") and not pcall(require, "pdfport_nvim") then
    vim.health.info("pdf_open: pdfport.nvim not installed — PDFs open in the system viewer only")
  end

  -- Watcher quarantine: note Windows-only relevance
  if is_enabled("watcher_quarantine") then
    local plat_ok, plat = pcall(require, "filetree.util.platform")
    if plat_ok and not plat.is_windows() and not plat.is_wsl() then
      vim.health.info("watcher_quarantine: no-op on non-Windows platforms")
    end
  end

  -- handle_guard: report install state + flag leaked watchers (a tracked handle
  -- still pointing at a path that no longer exists = neo-tree left it behind).
  if is_enabled("handle_guard") then
    local ok_hg, hg = registry.load("handle_guard")
    if ok_hg and hg then
      if hg.installed() then
        local list = hg.handles()
        local leaked = 0
        for _, h in ipairs(list) do
          if not h.exists then leaked = leaked + 1 end
        end
        if leaked > 0 then
          vim.health.warn(("handle_guard: %d of %d tracked watcher(s) point at a "
            .. "gone path (see :Filetree handles)"):format(leaked, #list))
        else
          vim.health.ok(("handle_guard installed (%d watcher(s) tracked)"):format(#list))
        end
      else
        local plat_ok, plat = pcall(require, "filetree.util.platform")
        if plat_ok and not plat.is_windows() and not plat.is_wsl() then
          vim.health.info("handle_guard: no-op on non-Windows platforms")
        else
          vim.health.info("handle_guard enabled but not installed "
            .. "(needs the neo-tree adapter; fs_watch not reachable yet)")
        end
      end
    end
  end

  -- Human-readable category headings + feature names.
  local CATEGORY_LABELS = {
    nav = "navigation & reveal", ui = "display / UI", fileops = "file operations",
    search = "search & filter",  paths = "paths & clipboard", git = "git",
    org = "marks & organization", system = "system integration", lsp = "LSP",
    compare = "diff & compare",  integration = "plugin integrations",
    infra = "infrastructure",
  }
  local ACRONYM = { lsp = "LSP", fm = "FM", ui = "UI" }
  local function humanize(key)
    local out = {}
    for word in key:gmatch("[^_]+") do
      out[#out + 1] = ACRONYM[word] or (word:sub(1, 1):upper() .. word:sub(2))
    end
    return table.concat(out, " ")
  end

  local by_cat = registry.by_category()
  for _, cat in ipairs(registry.CATEGORY_ORDER) do
    vim.health.start("filetree.nvim — features: " .. (CATEGORY_LABELS[cat] or cat))
    for _, name in ipairs(by_cat[cat] or {}) do
      if is_enabled(name) then
        vim.health.ok(humanize(name) .. " — enabled")
      else
        vim.health.info(humanize(name) .. " — disabled")
      end
    end
  end

  -- ── Optional dependencies ─────────────────────────────────────────────────
  vim.health.start("filetree.nvim — optional dependencies")

  local optionals = {
    { mod = "telescope",    label = "Telescope (for future telescope integration)" },
    { mod = "fzf-lua",      label = "fzf-lua (for future fzf integration)"        },
    { mod = "pdfport_nvim", label = "pdfport.nvim (for pdf_open text extraction)" },
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
