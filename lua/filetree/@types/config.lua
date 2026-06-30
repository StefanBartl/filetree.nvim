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
---@field diff                FiletreeDiffConfig?
---@field project_root        FiletreeProjectRootConfig?
---@field path_utils          FiletreePathUtilsConfig?
---@field git_status          FiletreeGitStatusConfig?
---@field bookmarks           FiletreeBookmarksConfig?
---@field preview             FiletreePreviewConfig?

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

-- ── diff ──────────────────────────────────────────────────────────────────────

---@class FiletreeDiffConfig
---@field enabled  boolean
---@field split    "vsplit"|"split"  Layout for diff windows (default "vsplit").
---@field keymap   string?           Key inside tree to stage/diff current node (default "D").

-- ── project_root ──────────────────────────────────────────────────────────────

---@class FiletreeProjectRootConfig
---@field enabled   boolean
---@field markers   string[]          Files/dirs that signal a project root.
---@field fallback  "cwd"|"parent"    What to use when no root is found (default "parent").

-- ── path_utils ────────────────────────────────────────────────────────────────

---@class FiletreePathUtilsConfig
---@field enabled   boolean
---@field lua_root  string?             Lua source root for require() conversion. Auto-detected when nil.
---@field keymaps   FiletreePathUtilsKeymaps?

---@class FiletreePathUtilsKeymaps
---@field copy_abs   string?  Copy absolute path       (default "ya")
---@field copy_rel   string?  Copy relative path       (default "yr")
---@field copy_name  string?  Copy filename only       (default "yn")
---@field copy_dir   string?  Copy parent directory    (default "yd")
---@field to_require string?  Copy as require() string (default "yq")
---@field md_link    string?  Copy as Markdown link    (default "ym")

-- ── git_status ────────────────────────────────────────────────────────────────

---@class FiletreeGitStatusSign
---@field text string
---@field hl   string

---@class FiletreeGitStatusConfig
---@field enabled      boolean
---@field debounce_ms  integer              Delay between write and re-query (default 300ms).
---@field show_ignored boolean              Also show ignored files (default false).
---@field signs        table<string, FiletreeGitStatusSign>?

-- ── bookmarks ─────────────────────────────────────────────────────────────────

---@class FiletreeBookmarksConfig
---@field enabled    boolean
---@field indicator  string   Character shown at eol for bookmarked nodes (default "★").
---@field hl_group   string   Highlight group for the indicator (default "DiagnosticHint").
---@field keymap     string?  Normal-mode key inside tree buffer to toggle (default "b").
---@field persist    boolean  Save bookmarks to disk across sessions (default true).

-- ── preview ───────────────────────────────────────────────────────────────────

---@class FiletreePreviewConfig
---@field enabled    boolean
---@field keymap     string?  Normal-mode key inside tree buffer (default "<Space>").
---@field max_lines  integer  Max lines to read for text preview (default 40).
---@field max_width  integer  Max floating window width in columns (default 80).
---@field max_height integer  Max floating window height in lines (default 25).
---@field wrap       boolean  Enable line wrapping in the preview window (default false).

return {}
