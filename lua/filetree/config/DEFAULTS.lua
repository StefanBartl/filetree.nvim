---@module 'filetree.config.DEFAULTS'
---@brief Plugin-side default configuration.
---@description
--- The single source of truth for filetree.nvim's built-in defaults. User config
--- passed to `require("filetree").setup({})` is deep-merged on top of this table
--- (see `filetree.config`). Per-feature defaults that are not listed here live in
--- the feature module itself; this table only carries the cross-cutting options
--- and the few features whose defaults are worth surfacing centrally.

---@type FiletreeConfig
return {
  adapter     = "auto",
  ignore_list = true,   -- hide .git, node_modules, etc. by default
  features = {
    picker = {
      enabled     = true,
      index_width = 2,
      timeout_ms  = 3000,
      keymaps = {
        trigger_reveal = "<leader>ftp",
        trigger_cwd    = "<leader>ftc",
      },
    },
    layout_guard = {
      enabled  = true,
      delay_ms = 50,
    },
    cwd_sync = {
      enabled       = false,
      debounce_ms   = 150,
      parent_levels = 0,
      keep_focus    = true,
    },
    current_hl = {
      enabled     = false,
      file_hl     = { fg = "#7aa2f7", bold = true },
      parent_hl   = { fg = "#565f89" },
      debounce_ms = 100,
    },
    safety = {
      enabled     = false,
      backup_dir  = nil,
      max_backups = 5,
      dry_run     = false,
    },
  },
}
