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
---@field rename_batch        FiletreeRenameBatchConfig?
---@field session             FiletreeSessionConfig?
---@field open_terminal       FiletreeOpenTerminalConfig?
---@field copy_move           FiletreeCopyMoveConfig?
---@field find_files          FiletreeFindFilesConfig?
---@field filter              FiletreeFilterConfig?
---@field grep_in_dir         FiletreeGrepInDirConfig?
---@field recent_files        FiletreeRecentFilesConfig?
---@field breadcrumbs         FiletreeBreadcrumbsConfig?
---@field lsp_diagnostics      FiletreeLspDiagnosticsConfig?
---@field size_info            FiletreeSizeInfoConfig?
---@field notes                FiletreeNotesConfig?
---@field create_from_template FiletreeCreateFromTemplateConfig?
---@field symlink              FiletreeSymlinkConfig?
---@field auto_reveal          FiletreeAutoRevealConfig?
---@field archive              FiletreeArchiveConfig?
---@field git_actions          FiletreeGitActionsConfig?
---@field auto_resize          FiletreeAutoResizeConfig?
---@field ignore_patterns      FiletreeIgnorePatternsConfig?
---@field file_watcher         FiletreeFileWatcherConfig?
---@field hooks_api            FiletreeHooksApiConfig?
---@field compare_dirs         FiletreeCompareDirsConfig?
---@field pin_node             FiletreePinNodeConfig?
---@field workspace            FiletreeWorkspaceConfig?
---@field color_labels         FiletreeColorLabelsConfig?
---@field jump_list            FiletreeJumpListConfig?
---@field outline              FiletreeOutlineConfig?
---@field duplicate_node          FiletreeDuplicateNodeConfig?
---@field git_blame               FiletreeGitBlameConfig?
---@field open_with               FiletreeOpenWithConfig?
---@field smart_rename            FiletreeSmartRenameConfig?
---@field tag_system              FiletreeTagSystemConfig?
---@field telescope_integration   FiletreeTelescopeConfig?
---@field path_copy               FiletreePathCopyConfig?
---@field diagnostics_filter      FiletreeDiagnosticsFilterConfig?
---@field live_search             FiletreeLiveSearchConfig?
---@field quick_open              FiletreeQuickOpenConfig?
---@field harpoon_integration     FiletreeHarpoonConfig?
---@field file_permissions        FiletreeFilePermissionsConfig?
---@field node_info               FiletreeNodeInfoConfig?
---@field tree_traverse           FiletreeTreeTraverseConfig?
---@field lua_require_copy        FiletreeLuaRequireCopyConfig?
---@field find_or_grep_menu       FiletreeFindOrGrepMenuConfig?
---@field copy_file_list          FiletreeCopyFileListConfig?
---@field smart_create            FiletreeSmartCreateConfig?

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

-- ── create_from_template ──────────────────────────────────────────────────────

---@class FiletreeCreateFromTemplateConfig
---@field enabled       boolean
---@field keymap        string?   Key inside tree (default "t").
---@field template_dir  string?   Custom template directory. Defaults to stdpath("data")/filetree/templates/.
---@field author        string?   Author name for ${author} substitution.
---@field open_after    boolean   Open created file in editor (default true).

-- ── symlink ───────────────────────────────────────────────────────────────────

---@class FiletreeSymlinkConfig
---@field enabled          boolean
---@field keymap_follow    string?  Key to follow symlink (default "sl").
---@field keymap_create    string?  Key to create symlink (default "sL").
---@field show_target_eol  boolean  Show target path as eol extmark (default true).
---@field hl_group         string   Highlight group for target text (default "Comment").

-- ── auto_reveal ───────────────────────────────────────────────────────────────

---@class FiletreeAutoRevealConfig
---@field enabled      boolean
---@field debounce_ms  integer   Delay after BufEnter (default 150ms).
---@field ignore_ft    string[]  Filetypes that never trigger reveal.
---@field only_if_open boolean   Only reveal when tree window is visible (default true).

-- ── lsp_diagnostics ──────────────────────────────────────────────────────────

---@class FiletreeLspDiagnosticsConfig
---@field enabled        boolean
---@field show_errors    boolean   Show error count (default true).
---@field show_warnings  boolean   Show warning count (default true).
---@field show_hints     boolean   Show hint count (default false).
---@field show_info      boolean   Show info count (default false).
---@field format         fun(counts: table): string?  Custom formatter. Return nil to hide.
---@field debounce_ms    integer   Delay after DiagnosticChanged (default 300ms).

-- ── size_info ─────────────────────────────────────────────────────────────────

---@class FiletreeSizeInfoConfig
---@field enabled     boolean
---@field show_files  boolean  Show file sizes (default true).
---@field show_dirs   boolean  Show directory sizes (default true).
---@field hl_group    string   Highlight group for size text (default "Comment").
---@field dir_async   boolean  Use `du`/PowerShell for dir sizes (default true).

-- ── notes ─────────────────────────────────────────────────────────────────────

---@class FiletreeNotesConfig
---@field enabled    boolean
---@field keymap     string?  Normal-mode key inside tree (default "gn").
---@field indicator  string   Extmark indicator character (default "📝").
---@field hl_group   string   Highlight group for the indicator (default "DiagnosticHint").

-- ── grep_in_dir ───────────────────────────────────────────────────────────────

---@class FiletreeGrepInDirConfig
---@field enabled       boolean
---@field keymap        string?    Key in tree for grep with prompt (default "gr").
---@field keymap_cword  string?    Key in tree for grep cword (default "gR").
---@field prefer        "auto"|"telescope"|"fzf-lua"|"builtin"
---@field hidden        boolean    Include hidden files (default false).
---@field extra_args    string[]   Additional args passed to rg/grep.

-- ── recent_files ──────────────────────────────────────────────────────────────

---@class FiletreeRecentFilesConfig
---@field enabled          boolean
---@field max_files        integer   Max entries to keep (default 100).
---@field keymap_tree      string?   Key inside tree (default "r").
---@field keymap_global    string?   Global normal-mode key (default nil).
---@field reveal_on_open   boolean   Reveal in tree on open (default true).
---@field exclude          string[]  Lua patterns for paths to never record.

-- ── breadcrumbs ───────────────────────────────────────────────────────────────

---@class FiletreeBreadcrumbsConfig
---@field enabled    boolean
---@field mode       "winbar"|"float"|"statusline"  Display mode (default "winbar").
---@field separator  string   Part separator (default "  ").
---@field max_depth  integer  Max number of path segments (default 5).
---@field hl_dir     string   Highlight group for directory parts (default "Comment").
---@field hl_file    string   Highlight group for the file/leaf part (default "Normal").
---@field hl_sep     string   Highlight group for separators (default "NonText").
---@field winbar_hl  string   Background group for the whole winbar (default "WinBar").

-- ── copy_move ─────────────────────────────────────────────────────────────────

---@class FiletreeCopyMoveKeymaps
---@field copy   string?  Stage for copy (default "yy")
---@field cut    string?  Stage for cut  (default "xx")
---@field paste  string?  Paste staged   (default "p")
---@field show   string?  Show clipboard (default "P")

---@class FiletreeCopyMoveConfig
---@field enabled     boolean
---@field keymaps     FiletreeCopyMoveKeymaps?
---@field confirm     boolean  Ask before paste (default true).
---@field use_safety  boolean  Create backup before move (default true).
---@field dry_run     boolean  Log without executing (default false).

-- ── find_files ────────────────────────────────────────────────────────────────

---@class FiletreeFindFilesConfig
---@field enabled         boolean
---@field keymap_tree     string?  Key inside tree buffer (default "f").
---@field keymap_global   string?  Global normal-mode key (default nil).
---@field prefer          "auto"|"telescope"|"fzf-lua"|"mini.pick"|"builtin"
---@field reveal_on_open  boolean  Reveal selected file in tree (default true).
---@field hidden          boolean  Include hidden files (default false).

-- ── filter ────────────────────────────────────────────────────────────────────

---@class FiletreeFilterConfig
---@field enabled          boolean
---@field keymap           string?  Key inside tree to enter filter mode (default "/").
---@field case_sensitive   boolean  Case-sensitive matching (default false).
---@field dim_hl_group     string   Highlight group for non-matching lines (default "Comment").
---@field debounce_ms      integer  Input debounce delay (default 80ms).

-- ── rename_batch ──────────────────────────────────────────────────────────────

---@class FiletreeRenameBatchConfig
---@field enabled     boolean
---@field keymap      string?  Normal-mode key inside tree (default "R").
---@field confirm     boolean  Ask for confirmation before renaming (default true).
---@field use_safety  boolean  Create safety backup before renaming (default true).
---@field dry_run     boolean  Log plan without executing (default false).

-- ── session ───────────────────────────────────────────────────────────────────

---@class FiletreeSessionConfig
---@field enabled        boolean
---@field auto_save      boolean  Save on VimLeavePre and tree BufHidden (default true).
---@field auto_restore   boolean  Restore on first FileType neo-tree/NvimTree (default true).
---@field max_sessions   integer  Maximum stored project sessions (default 50).

-- ── open_terminal ─────────────────────────────────────────────────────────────

---@class FiletreeOpenTerminalConfig
---@field enabled  boolean
---@field keymap   string?                          Key inside tree (default "T").
---@field prefer   "auto"|"snacks"|"toggleterm"|"builtin"  Terminal backend (default "auto").
---@field split    "horizontal"|"vertical"|"float"  Builtin split direction (default "horizontal").

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

-- ── color_labels ─────────────────────────────────────────────────────────────

---@class FiletreeColorLabelsConfig
---@field enabled   boolean
---@field indicator string    Left-column indicator character (default "●").
---@field keymap    string?   Opens color picker (default "cl").
---@field labels    FiletreeLabel[]?  Override default label definitions.

-- ── jump_list ─────────────────────────────────────────────────────────────────

---@class FiletreeJumpListConfig
---@field enabled      boolean
---@field max_jumps    integer   Ring buffer size (default 50).
---@field debounce_ms  integer   Dwell time before recording (default 500ms).
---@field keymap_back  string?   Navigate backwards (default "<C-o>").
---@field keymap_fwd   string?   Navigate forwards  (default "<C-i>").

-- ── outline ───────────────────────────────────────────────────────────────────

---@class FiletreeOutlineConfig
---@field enabled    boolean
---@field keymap     string?   Key inside tree (default "go").
---@field max_width  integer   Float max width (default 60).
---@field max_height integer   Float max height (default 25).
---@field depth      integer   LSP symbol nesting depth (default 3).

-- ── compare_dirs ─────────────────────────────────────────────────────────────

---@class FiletreeCompareDirsConfig
---@field enabled       boolean
---@field prefer        "auto"|"meld"|"bc"|"delta"|"builtin"  Visual diff tool preference.
---@field keymap        string?   Key inside tree (default "cd").
---@field open_quickfix boolean   Auto-open quickfix after builtin diff (default true).

-- ── pin_node ─────────────────────────────────────────────────────────────────

---@class FiletreePinNodeConfig
---@field enabled    boolean
---@field indicator  string   EOL indicator (default "📌").
---@field hl_group   string   Highlight group (default "DiagnosticWarn").
---@field keymap     string?  Key inside tree (default "gp").
---@field global     boolean  Store globally across projects (default true).

-- ── workspace ────────────────────────────────────────────────────────────────

---@class FiletreeWorkspaceConfig
---@field enabled          boolean
---@field keymap_switch    string?  Key inside tree for picker (default "gw").
---@field auto_add         boolean  Auto-add cwd to workspace on setup (default false).
---@field max_roots        integer  Maximum stored roots (default 20).
---@field session_restore  boolean  Call session.restore() after switching (default true).

-- ── ignore_patterns ──────────────────────────────────────────────────────────

---@class FiletreeIgnorePatternsConfig
---@field enabled   boolean
---@field patterns  string[]             Lua patterns or globs to hide/dim.
---@field mode      "dim"|"hide"         How to apply (default "dim").
---@field keymap    string?              Toggle key inside tree (default "gi").
---@field hl_group  string               Highlight for dimmed lines (default "Comment").

-- ── file_watcher ─────────────────────────────────────────────────────────────

---@class FiletreeFileWatcherConfig
---@field enabled          boolean
---@field debounce_ms      integer   Event debounce before refresh (default 500ms).
---@field watch_recursive  boolean   Watch subdirectories (default true).
---@field ignore_events    string[]  uv event types to ignore.

-- ── hooks_api ─────────────────────────────────────────────────────────────────

---@class FiletreeHooksApiConfig
---@field enabled boolean

-- ── archive ───────────────────────────────────────────────────────────────────

---@class FiletreeArchiveConfig
---@field enabled     boolean
---@field prefer      "auto"|"zip"|"tar"  Default format hint (default "auto").
---@field keymap_zip  string?             Key inside tree for zip (default "az").
---@field keymap_tar  string?             Key inside tree for tar.gz (default "at").

-- ── git_actions ───────────────────────────────────────────────────────────────

---@class FiletreeGitActionsConfig
---@field enabled         boolean
---@field keymap_stage    string?  Key inside tree to stage current node (default "gs").
---@field keymap_unstage  string?  Key inside tree to unstage current node (default "gS").
---@field keymap_log      string?  Key inside tree to show git log (default "gl").

-- ── auto_resize ───────────────────────────────────────────────────────────────

---@class FiletreeAutoResizeBreakpoint
---@field cols  integer  Minimum editor column count to activate this width.
---@field width integer  Tree window width to use.

---@class FiletreeAutoResizeConfig
---@field enabled      boolean
---@field breakpoints  FiletreeAutoResizeBreakpoint[]
---@field min_width    integer  Absolute minimum (default 20).
---@field max_width    integer  Absolute maximum (default 60).

-- ── duplicate_node ───────────────────────────────────────────────────────────

---@class FiletreeDuplicateNodeConfig
---@field enabled            boolean
---@field keymap             string?   Key inside tree (default "<C-d>").
---@field suffix             string    Default copy suffix (default "_copy").
---@field open_after         boolean   Open new file after creation (default false).
---@field confirm_overwrite  boolean   Warn before overwriting (default true).

-- ── git_blame ─────────────────────────────────────────────────────────────────

---@class FiletreeGitBlameConfig
---@field enabled      boolean
---@field mode         "inline"|"float"|"both"  Default "inline".
---@field debounce_ms  integer   CursorMoved debounce (default 300ms).
---@field keymap       string?   Float keymap (default "gb").
---@field hl_group     string    Inline highlight group (default "Comment").
---@field format       string    Inline format string with {hash}/{author}/{date}/{subject}.

-- ── open_with ─────────────────────────────────────────────────────────────────

---@class FiletreeOpenWithApp
---@field name    string    Display name.
---@field cmd     string    Executable.
---@field args    string[]? Extra args before path.
---@field keymap  string?   Optional tree keymap.

---@class FiletreeOpenWithConfig
---@field enabled  boolean
---@field keymap   string?              System-default open key (default "ox").
---@field apps     FiletreeOpenWithApp[]  Custom application entries.

-- ── smart_rename ─────────────────────────────────────────────────────────────

---@class FiletreeSmartRenameConfig
---@field enabled     boolean
---@field keymap      string?   Key inside tree (default "<F2>").
---@field use_safety  boolean   Create safety backup before rename (default true).
---@field dry_run     boolean   Log without executing (default false).

-- ── tag_system ────────────────────────────────────────────────────────────────

---@class FiletreeTagSystemConfig
---@field enabled    boolean
---@field keymap     string?   Key to edit tags for current node (default "gt").
---@field hl_group   string    Highlight for tag virtual text (default "Special").
---@field filter_hl  string    Highlight for dimmed non-matching nodes (default "Comment").

-- ── telescope_integration ─────────────────────────────────────────────────────

---@class FiletreeTelescopeConfig
---@field enabled        boolean
---@field backend        "auto"|"telescope"|"fzf-lua"|"builtin"  Backend (default "auto").
---@field keymap_prefix  string?  Global keymap prefix for all pickers.

-- ── path_copy ────────────────────────────────────────────────────────────────

---@class FiletreePathCopyConfig
---@field enabled       boolean
---@field keymap_pick   string?  Opens format picker (default "yp").
---@field keymap_abs    string?  Copy absolute path (default "ya").
---@field keymap_rel    string?  Copy relative path (default "yr").
---@field keymap_name   string?  Copy filename only (default "yn").
---@field notify        boolean  Show notification after copy (default true).

-- ── diagnostics_filter ───────────────────────────────────────────────────────

---@class FiletreeDiagnosticsFilterConfig
---@field enabled       boolean
---@field min_severity  integer  Minimum severity to show in filter (1=ERROR, default).
---@field show_counts   boolean  Render EOL error/warning counts (default true).
---@field count_icons   string[] Icons for error/warn/info/hint (default " E"/" W"/" I"/" H").
---@field hl_groups     string[] Hl groups for each severity (DiagnosticError etc.).
---@field filter_hl     string   Hl for dimmed non-diagnostic nodes (default "Comment").
---@field debounce_ms   integer  DiagnosticChanged debounce (default 500ms).
---@field keymap        string?  Toggle filter key inside tree (default "df").

-- ── live_search ──────────────────────────────────────────────────────────────

---@class FiletreeLiveSearchConfig
---@field enabled           boolean
---@field keymap            string?  Key to open live search (default "/").
---@field match             "name"|"path"  Match against filename or full path (default "name").
---@field hl_match          string   Highlight for matched nodes (default "Search").
---@field hl_dim            string   Highlight for non-matched nodes (default "Comment").
---@field commit_to_filter  boolean  Enter pushes query to filter feature (default true).
---@field debounce_ms       integer  TextChanged debounce (default 80ms).

-- ── quick_open ────────────────────────────────────────────────────────────────

---@class FiletreeQuickOpenConfig
---@field enabled     boolean
---@field keymap      string?    Key inside tree to open picker (default "<C-p>").
---@field max_items   integer    Max items shown in picker (default 50).
---@field decay_rate  number     Frecency decay per hour (default 0.5).
---@field sources     string[]   Collections to include: "recent","bookmarks","pins".
---@field split       "edit"|"vsplit"|"split"  How to open selected file.

-- ── harpoon_integration ──────────────────────────────────────────────────────

---@class FiletreeHarpoonConfig
---@field enabled       boolean
---@field keymap_add    string?  Key to add node to harpoon (default "gh").
---@field keymap_menu   string?  Key to open harpoon quick-menu (default "gH").
---@field indicator_hl  string   Highlight for slot indicator (default "DiagnosticHint").
---@field debounce_ms   integer  Mark refresh debounce (default 250ms).

-- ── file_permissions ─────────────────────────────────────────────────────────

---@class FiletreeFilePermissionsConfig
---@field enabled       boolean
---@field show_inline   boolean  Render permission string as EOL virt_text (default false).
---@field hl_exec       string   Highlight for executable files (default "DiagnosticOk").
---@field hl_default    string   Highlight for non-executable files (default "Comment").
---@field keymap_exec   string?  Toggle execute bit (default "gx").
---@field keymap_chmod  string?  Interactive chmod prompt (default "gX").
---@field keymap_show   string?  Show stat details (default "gP").

-- ── node_info ────────────────────────────────────────────────────────────────

---@class FiletreeNodeInfoConfig
---@field enabled          boolean
---@field keymap           string?   Key inside tree (default "I").
---@field show_lines       boolean   Show line count for files (default true).
---@field max_lines_size   integer   Skip line count for files larger than this in bytes (default 5MB).

-- ── tree_traverse ─────────────────────────────────────────────────────────────

---@class FiletreeTreeTraverseConfig
---@field enabled       boolean
---@field keymap_up     string?   Navigate to parent directory (default "<BS>").
---@field keymap_down   string?   Set current dir as root (default "]r").
---@field sync_cwd      boolean   Also change Vim's cwd (default true).

-- ── lua_require_copy ─────────────────────────────────────────────────────────

---@class FiletreeLuaRequireCopyConfig
---@field enabled   boolean
---@field keymap    string?   Key inside tree (default "rq").

-- ── find_or_grep_menu ─────────────────────────────────────────────────────────

---@class FiletreeFindOrGrepMenuConfig
---@field enabled   boolean
---@field keymap    string?                               Key inside tree (default "<M-p>").
---@field prefer    "auto"|"telescope"|"fzf-lua"          Backend preference (default "auto").

-- ── copy_file_list ────────────────────────────────────────────────────────────

---@class FiletreeCopyFileListConfig
---@field enabled          boolean
---@field keymap_files_abs string?   Copy absolute file paths (default "[f").
---@field keymap_files_rel string?   Copy relative file paths (default "]f").
---@field keymap_dirs_abs  string?   Copy absolute dir paths  (default "[F").
---@field keymap_dirs_rel  string?   Copy relative dir paths  (default "]F").
---@field preview_limit    integer   Max lines shown in notification (default 5).
---@field separator        string    Separator between paths (default "\\n").

-- ── smart_create ──────────────────────────────────────────────────────────────

---@class FiletreeSmartCreateConfig
---@field enabled              boolean
---@field keymap               string?   Key inside tree (default "a").
---@field auto_init_lua        boolean   Dirs → create init.lua (default true).
---@field auto_types_template  boolean   @types dirs → ---@meta template (default true).
---@field auto_module_annot    boolean   .lua files → ---@module annotation (default true).
---@field ask_clipboard        boolean   Ask whether to paste clipboard content (default true).

return {}
