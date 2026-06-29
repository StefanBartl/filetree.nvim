---@meta
---@module 'filetree.@types.config'

---@class FiletreeConfig
---@field adapter  FiletreeAdapterName|"auto"  Which adapter to use. "auto" picks the first available one.
---@field features FiletreeFeaturesConfig

---@class FiletreeFeaturesConfig
---@field picker              FiletreePickerConfig?
---@field layout_guard        FiletreeLayoutGuardConfig?
---@field cwd_sync            FiletreeCwdSyncConfig?
---@field current_hl          FiletreeCurrentHlConfig?
---@field safety              FiletreeSafetyConfig?
---@field trash               FiletreeTrashConfig?
---@field watcher_quarantine  FiletreeWatcherQuarantineConfig?
---@field marks               FiletreeMarksConfig?

-- ── picker ────────────────────────────────────────────────────────────────────

---@class FiletreePickerConfig
---@field enabled    boolean
---@field index_width integer   Digits per node index (default 2 → "01".."99").
---@field timeout_ms integer    Auto-exit after this many ms of inactivity (default 3000).
---@field keymaps    FiletreePickerKeymaps?

---@class FiletreePickerKeymaps
---@field trigger_reveal string   Normal-mode key to enter picker + reveal current file.
---@field trigger_cwd    string   Normal-mode key to enter picker at cwd.

-- ── layout_guard ──────────────────────────────────────────────────────────────

---@class FiletreeLayoutGuardConfig
---@field enabled    boolean
---@field delay_ms   integer   Milliseconds before guard fires after a window closes (default 50).

-- ── cwd_sync ──────────────────────────────────────────────────────────────────

---@class FiletreeCwdSyncConfig
---@field enabled       boolean
---@field debounce_ms   integer   Debounce delay for buffer-change events (default 150).
---@field parent_levels integer   How many parent dirs to ascend when revealing (default 0).
---@field keep_focus    boolean   Keep focus in the editor window after reveal (default true).

-- ── current_hl ────────────────────────────────────────────────────────────────

---@class FiletreeCurrentHlConfig
---@field enabled     boolean
---@field file_hl     string|table  Highlight spec for the current file node.
---@field parent_hl   string|table  Highlight spec for the parent directory node.
---@field debounce_ms integer

-- ── safety ────────────────────────────────────────────────────────────────────

---@class FiletreeSafetyConfig
---@field enabled        boolean
---@field backup_dir     string?  Absolute path for backups. Defaults to stdpath("data")/filetree/backups.
---@field max_backups    integer  Maximum number of backup copies kept per file (default 5).
---@field dry_run        boolean  Log operations without executing them (default false).

-- ── trash ─────────────────────────────────────────────────────────────────────

---@class FiletreeTrashConfig
---@field enabled      boolean
---@field confirm      boolean  Ask before trashing (default true).
---@field use_safety   boolean  Create a backup before trashing (default false).
---@field dry_run      boolean  Log without actually trashing (default false).

-- ── watcher_quarantine ────────────────────────────────────────────────────────

---@class FiletreeWatcherQuarantineConfig
---@field enabled     boolean
---@field duration_ms integer  Default quarantine duration in ms (default 500).
---@field silent      boolean  Suppress quarantine notifications (default true).

-- ── marks ─────────────────────────────────────────────────────────────────────

---@class FiletreeMarksConfig
---@field enabled    boolean
---@field indicator  string   Character shown before marked nodes (default "✓").
---@field hl_group   string   Highlight group for the indicator (default "DiagnosticOk").
---@field keymap     string?  Normal-mode key inside tree buffer to toggle mark (default "m").

return {}
