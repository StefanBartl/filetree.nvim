---@meta
---@module 'filetree.@types.config'

---@alias FiletreeBuiltinAlias
---| "Ft"       Short alias registered by default.
---| "FT"       Uppercase variant.
---| "Filetree" Original full name (use as alias when renaming).
---| "Tree"     Short alternative.
---| "NT"       "NeoTree" shorthand.
---| "FTree"    Verbose short form.

---@class FiletreeCommandConfig
---@field name    string                             Name for the user command (default: "Filetree").
---@field aliases (FiletreeBuiltinAlias|string)[]?   Aliases to also register. Omit to keep the default :Ft alias.

---@class FiletreeMenuConfig
---@field enable    boolean?  Provide nvzone/menu entries at all (default true).
---@field fileops   boolean?  create / rename / batch rename / template (default true).
---@field clipboard boolean?  copy / cut / paste (default true).
---@field delete    boolean?  trash (default true).
---@field open      boolean?  vsplit / split / tab / system app / file manager (default true).
---@field paths     boolean?  copy path / markdown link (default true).
---@field search    boolean?  find files / grep in dir (default true).
---@field info      boolean?  node info (default true).

---@class FiletreeConfig
---@field adapter          FiletreeAdapterName|"auto"       Which adapter to use. "auto" picks the first available one.
---@field debug            boolean?                         true → show notifier.debug(...) messages for troubleshooting (default false).
---@field features         FiletreeFeaturesConfig
---@field keymaps          table<string,string|false>?      Global keymap remap: { ["<old>"] = "<new>" } or { ["<key>"] = false } to disable.
---@field adapter_keymaps  table<string,string|false>?      Override the adapter's own native keymaps: false → <Nop>, string → remap target. Applied after the adapter sets its keymaps. Example: { ["i"] = false } noops neotree's built-in `i` (toggle-info).
---@field command          FiletreeCommandConfig|string|nil User command name (string) or config table. Default: "Filetree" + "Ft" alias.
---@field autocmds         table<string,false>?             Disable per-feature autocmds: { auto_reveal = false }. Sets feature.autocmds_enabled = false.
---@field ignore_list      boolean|string[]|nil             true (default) = hide common dirs (.git, node_modules…); false = show all; string[] = custom list.
---@field menu             FiletreeMenuConfig?              nvzone/menu integration entries (group-level opt-out; entries provided by filetree.integrations.menu).
---@field confirmations    boolean|FiletreeConfirmationsConfig|nil  Confirmable actions: paste/rename_batch default to *no* prompt, delete defaults to *prompt*. true/false applies to all three at once; a table applies per action, e.g. { delete = false } to opt out of just the delete prompt. A feature's own `features.<name>.confirm` (if explicitly set) always wins over this.

---@class FiletreeConfirmationsConfig
---@field paste        boolean?  copy_move's paste-staged-nodes prompt (default false).
---@field delete       boolean?  trash's send-to-trash prompt (default false).
---@field rename_batch boolean?  rename_batch's apply-plan prompt (default false).

---@class FiletreeFeaturesConfig
---@field ignore_list         FiletreeIgnoreListConfig?
---@field cursor_hide         FiletreeCursorHideConfig?
---@field tree_reset          FiletreeTreeResetConfig?
---@field open_replace        FiletreeOpenReplaceConfig?
---@field open_variants       FiletreeOpenVariantsConfig?
---@field reveal_alt          FiletreeRevealAltConfig?
---@field buffer_save         FiletreeBufferSaveConfig?
---@field window_size_cycler  FiletreeWindowSizeCyclerConfig?
---@field open_in_fm          FiletreeOpenInFmConfig?
---@field shell_run           FiletreeShellRunConfig?
---@field layout_guard        FiletreeLayoutGuardConfig?
---@field cwd_sync            FiletreeCwdSyncConfig?
---@field current_hl          FiletreeCurrentHlConfig?
---@field safety              FiletreeSafetyConfig?
---@field trash               FiletreeTrashConfig?
---@field watcher_quarantine  FiletreeWatcherQuarantineConfig?
---@field marks               FiletreeMarksConfig?
---@field diff                FiletreeDiffConfig?
---@field project_root        FiletreeProjectRootConfig?
---@field git_status          FiletreeGitStatusConfig?
---@field preview             FiletreePreviewConfig?
---@field rename_batch        FiletreeRenameBatchConfig?
---@field session             FiletreeSessionConfig?
---@field copy_move           FiletreeCopyMoveConfig?
---@field find_files          FiletreeFindFilesConfig?
---@field filter              FiletreeFilterConfig?
---@field grep_in_dir         FiletreeGrepInDirConfig?
---@field breadcrumbs         FiletreeBreadcrumbsConfig?
---@field lsp_diagnostics      FiletreeLspDiagnosticsConfig?
---@field size_info            FiletreeSizeInfoConfig?
---@field opened_sync          FiletreeOpenedSyncConfig?
---@field cheatsheet           FiletreeCheatsheetConfig?
---@field create_from_template FiletreeCreateFromTemplateConfig?
---@field auto_reveal          FiletreeAutoRevealConfig?
---@field auto_resize          FiletreeAutoResizeConfig?
---@field file_watcher         FiletreeFileWatcherConfig?
---@field hooks_api            FiletreeHooksApiConfig?
---@field open_with               FiletreeOpenWithConfig?
---@field smart_rename            FiletreeSmartRenameConfig?
---@field path_copy               FiletreePathCopyConfig?
---@field live_search             FiletreeLiveSearchConfig?
---@field node_info               FiletreeNodeInfoConfig?
---@field tree_traverse           FiletreeTreeTraverseConfig?
---@field lua_require_copy        FiletreeLuaRequireCopyConfig?
---@field copy_file_list          FiletreeCopyFileListConfig?
---@field markdown_links          FiletreeMarkdownLinksConfig?
---@field smart_create            FiletreeSmartCreateConfig?
---@field window_style            FiletreeWindowStyleConfig?

-- ── layout_guard ──────────────────────────────────────────────────────────────

---@class FiletreeLayoutGuardConfig
---@field enabled    boolean
---@field delay_ms   integer   Milliseconds before guard fires after a window closes (default 50).

-- ── cwd_sync ──────────────────────────────────────────────────────────────────

---@class FiletreeCwdSyncConfig
---@field enabled          boolean
---@field debounce_ms      integer   Debounce delay for buffer-change events (default 150).
---@field parent_levels    integer   How many parent dirs to ascend when revealing (default 0).
---@field keep_focus       boolean   Keep focus in the editor window after reveal (default true).
---@field change_dir       boolean   Actually change Neovim's cwd (default true). Never prompts —
---                                  always applies silently.
---@field reveal           boolean   Also reveal/root the tree from cwd_sync (default true). Set
---                                  false when the tree plugin already follows the cwd (e.g.
---                                  neo-tree bind_to_cwd + follow_current_file) so the two
---                                  reveals don't fight and land on the file's parent.
---@field use_project_root boolean   Target the detected project root instead of the file's
---                                  immediate parent directory (default true; see project_root).
---@field root_markers     string[]|false  Marker names to anchor the cwd to the nearest ancestor
---                                  containing one (default { ".git" }), via a cached lib.nvim
---                                  finder. Keeps the cwd at a stable high-level root to avoid
---                                  frequent cwd jumps. `false` disables it (falls back to
---                                  use_project_root / parent dir). Takes priority over use_project_root.

-- ── current_hl ────────────────────────────────────────────────────────────────

---@class FiletreeCurrentHlConfig
---@field enabled     boolean
---@field file_hl     string|table  Highlight spec for the current file node.
---@field parent_hl   string|table  Highlight spec for the parent directory node.
---@field debounce_ms integer
---@field icon        string?  Sign-column marker placed on the current file's line (nil = off). e.g. "▸".
---@field icon_hl     string?  Highlight group for the icon (default: the file_hl group).

--- ── opened_sync ───────────────────────────────────────────────────────────────
---@class FiletreeOpenedSyncConfig
---@field enabled     boolean
---@field debounce_ms integer  Delay (ms) before re-rendering after a buffer open/close (default 60).

-- ── safety ────────────────────────────────────────────────────────────────────

---@class FiletreeSafetyConfig
---@field enabled        boolean
---@field backup_dir     string?  Absolute path for backups. Defaults to stdpath("data")/filetree/backups.
---@field max_backups    integer  Maximum number of backup copies kept per file (default 5).
---@field dry_run        boolean  Log operations without executing them (default false).

-- ── trash ─────────────────────────────────────────────────────────────────────

---@class FiletreeTrashConfig
---@field enabled             boolean
---@field confirm             boolean  Ask before trashing (default true, unlike paste/rename_batch; see top-level `confirmations`).
---@field use_safety          boolean  Create a backup before trashing (default false).
---@field dry_run             boolean  Log without actually trashing (default false).
---@field check_markdown_refs boolean  Warn about markdown files linking to the target, via markdown.nvim's optional `find_references` (default true; no-op if markdown.nvim isn't installed).
---@field refs_picker_prefer  "auto"|"telescope"|"fzf-lua"|"quickfix"  Backend for the "Inspect references" chooser option (default "auto": telescope -> fzf-lua -> quickfix).
---@field keymap              string?  Trash current node / all marked (default "d").
---@field keymap_undo         string?  Undo last trash operation (default "U").
---@field keymap_history      string?  Show trash history (default "<leader>th").

-- ── watcher_quarantine ────────────────────────────────────────────────────────

---@class FiletreeWatcherQuarantineConfig
---@field enabled     boolean
---@field duration_ms integer  Default quarantine duration in ms (default 500).
---@field silent      boolean  Suppress quarantine notifications (default true).

-- ── marks ─────────────────────────────────────────────────────────────────────

---@class FiletreeMarksConfig
---@field enabled          boolean
---@field indicator        string   Character shown before marked nodes (default "✓").
---@field hl_group         string   Highlight group for the indicator (default "DiagnosticOk").
---@field keymap           string?  Toggle mark on current node (default "m").
---@field keymap_all       string?  Mark all files in current directory (default "]m").
---@field keymap_unmark_all string? Unmark all files in current directory (default "[m").
---@field keymap_clear     string?  Clear all marks (default "<C-m>").
---@field keymap_show      string?  Show floating list of marked nodes (default "<leader>ms").

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
---@field cache     boolean           Cache resolved roots per directory for the session (default true).

-- ── create_from_template ──────────────────────────────────────────────────────

---@class FiletreeCreateFromTemplateConfig
---@field enabled       boolean
---@field keymap        string?   Key inside tree (default "t").
---@field template_dir  string?   Custom template directory. Defaults to stdpath("data")/filetree/templates/.
---@field author        string?   Author name for ${author} substitution.
---@field open_after    boolean   Open created file in editor (default true).

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

-- ── grep_in_dir ───────────────────────────────────────────────────────────────

---@class FiletreeGrepInDirConfig
---@field enabled          boolean
---@field keymap           string?    Key in tree for grep with prompt (default "gr").
---@field keymap_cword     string?    Key in tree for grep cword (default nil, off).
---@field keymap_telescope string?    Key in tree to force telescope specifically (default "tg").
---@field prefer           "auto"|"telescope"|"fzf-lua"|"builtin"
---@field hidden           boolean    Include hidden files (default false).
---@field extra_args       string[]   Additional args passed to rg/grep.

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
---@field copy   string?  Stage for copy  (default "c")
---@field cut    string?  Stage for cut   (default "x")
---@field paste  string?  Paste staged    (default "p")
---@field show   string?  Show clipboard  (default "P")
---@field clear  string?  Clear clipboard (default "<C-c>")

---@class FiletreeCopyMoveConfig
---@field enabled             boolean
---@field keymaps             FiletreeCopyMoveKeymaps?
---@field confirm             boolean  Ask before paste (default false; see top-level `confirmations`).
---@field use_safety          boolean  Create backup before move (default true).
---@field dry_run             boolean  Log without executing (default false).
---@field check_markdown_refs boolean  After a paste, offer to update markdown `[text](path)` links pointing at any **cut** (moved) item -- copies never break a reference -- via markdown.nvim's optional `find_references` (default true; no-op if markdown.nvim isn't installed).
---@field refs_picker_prefer  "auto"|"telescope"|"fzf-lua"|"quickfix"  Backend for the "Inspect references" chooser option (default "auto").

-- ── find_files ────────────────────────────────────────────────────────────────

---@class FiletreeFindFilesConfig
---@field enabled          boolean
---@field keymap_tree      string?  Key inside tree buffer (default "f").
---@field keymap_telescope string?  Key to force telescope specifically (default "tf").
---@field keymap_global    string?  Global normal-mode key (default nil).
---@field prefer           "auto"|"telescope"|"fzf-lua"|"mini.pick"|"builtin"
---@field reveal_on_open   boolean  Reveal selected file in tree (default true).
---@field hidden           boolean  Include hidden files (default false).

-- ── filter ────────────────────────────────────────────────────────────────────

---@class FiletreeFilterConfig
---@field enabled          boolean
---@field keymap           string?  Key inside tree to enter filter mode (default "/").
---@field keymap_clear     string?  Key inside tree to clear an applied filter directly (default "<C-c>").
---@field case_sensitive   boolean  Case-sensitive matching (default false).
---@field dim_hl_group     string   Highlight group for non-matching lines (default "Comment").
---@field debounce_ms      integer  Input debounce delay (default 80ms).

-- ── rename_batch ──────────────────────────────────────────────────────────────

---@class FiletreeRenameBatchConfig
---@field enabled             boolean
---@field keymap              string?  Normal-mode key inside tree (default "<leader>rb").
---@field confirm             boolean  Ask for confirmation before renaming (default false; see top-level `confirmations`).
---@field use_safety          boolean  Create safety backup before renaming (default true).
---@field dry_run             boolean  Log plan without executing (default false).
---@field check_markdown_refs boolean  After the batch, offer to update markdown `[text](path)` links pointing at any renamed item, via markdown.nvim's optional `find_references` (default true; no-op if markdown.nvim isn't installed).
---@field refs_picker_prefer  "auto"|"telescope"|"fzf-lua"|"quickfix"  Backend for the "Inspect references" chooser option (default "auto").

-- ── session ───────────────────────────────────────────────────────────────────

---@class FiletreeSessionConfig
---@field enabled        boolean
---@field auto_save      boolean  Save on VimLeavePre and tree BufHidden (default true).
---@field auto_restore   boolean  Restore on first FileType neo-tree/NvimTree (default true).
---@field max_sessions   integer  Maximum stored project sessions (default 50).

-- ── git_status ────────────────────────────────────────────────────────────────

---@class FiletreeGitStatusSign
---@field text string
---@field hl   string

---@class FiletreeGitStatusConfig
---@field enabled      boolean
---@field debounce_ms  integer              Delay between write and re-query (default 300ms).
---@field show_ignored boolean              Also show ignored files (default false).
---@field signs        table<string, FiletreeGitStatusSign>?

-- ── preview ───────────────────────────────────────────────────────────────────

---@alias FiletreeImageBackend "auto"|"snacks"|"image.nvim"|"system"|false
---@alias FiletreePdfBackend   "pdfport"|"system"|false

---@class FiletreePreviewImageConfig
---@field backend FiletreeImageBackend  "auto" tries snacks → image.nvim → system (default "auto").

---@class FiletreePreviewPdfConfig
---@field backend FiletreePdfBackend  "pdfport" tries pdfport.nvim, falls back to system (default "pdfport").

---@class FiletreePreviewConfig
---@field enabled              boolean
---@field mode                 "buffer"|"float"         Preview target: "buffer" shows the file in the editor window (default); "float" uses a floating window.
---@field highlight            boolean                  Syntax/treesitter highlighting in the preview (default true).
---@field cursor_debounce_ms   integer?                 Debounce (ms) for the live-update while scrolling the tree (default 80).
---@field keymap               string?                  Normal-mode key: toggle text preview; dispatch image/PDF (default "<Tab>").
---@field keymap_open          string?                  Normal-mode key: dispatch image/PDF; adapter default for other nodes (default "<CR>").
---@field max_lines            integer                  Max lines to read for text preview (default 40).
---@field max_width            integer                  Max floating window width in columns (default 80).
---@field max_height           integer                  Max floating window height in lines (default 25).
---@field wrap                 boolean                  Enable line wrapping in the preview window (default false).
---@field keymap_scroll_up     string?                  Scroll preview up 1 line (default "<C-b>").
---@field keymap_scroll_down   string?                  Scroll preview down 1 line (default "<C-f>").
---@field keymap_scroll_up10   string?                  Scroll preview up 10 lines (default "<PageUp>").
---@field keymap_scroll_down10 string?                  Scroll preview down 10 lines (default "<PageDown>").
---@field image                FiletreePreviewImageConfig?  Image-open config.
---@field pdf                  FiletreePreviewPdfConfig?    PDF-open config.

-- ── ignore_list ───────────────────────────────────────────────────────────────

---@class FiletreeIgnoreListConfig
---@field enabled boolean     Hide the ignore list (default true). Toggle with adapter's native hide-hidden keymap (e.g. `H` in neotree).
---@field names   string[]?   Basenames to hide. nil = built-in defaults (or lib.nvim list when available).

-- ── file_watcher ─────────────────────────────────────────────────────────────

---@class FiletreeFileWatcherConfig
---@field enabled          boolean
---@field debounce_ms      integer   Event debounce before refresh (default 500ms).
---@field watch_recursive  boolean   Watch subdirectories (default true).
---@field ignore_events    string[]  uv event types to ignore.

-- ── hooks_api ─────────────────────────────────────────────────────────────────

---@class FiletreeHooksApiConfig
---@field enabled boolean

-- ── auto_resize ───────────────────────────────────────────────────────────────

---@class FiletreeAutoResizeBreakpoint
---@field cols  integer  Minimum editor column count to activate this width.
---@field width integer  Tree window width to use.

---@class FiletreeAutoResizeConfig
---@field enabled      boolean
---@field breakpoints  FiletreeAutoResizeBreakpoint[]
---@field min_width    integer  Absolute minimum (default 20).
---@field max_width    integer  Absolute maximum (default 60).

-- ── open_with ─────────────────────────────────────────────────────────────────

---@class FiletreeOpenWithApp
---@field name    string    Display name.
---@field cmd     string    Executable.
---@field args    string[]? Extra args before path.
---@field keymap  string?   Optional tree keymap.

---@class FiletreeOpenWithConfig
---@field enabled  boolean
---@field keymap   string?              System-default open key (default "<leader>sm").
---@field apps     FiletreeOpenWithApp[]  Custom application entries.

-- ── smart_rename ─────────────────────────────────────────────────────────────

---@class FiletreeSmartRenameConfig
---@field enabled             boolean
---@field keymap              string?   Key inside tree (default "r").
---@field use_safety          boolean   Create safety backup before rename (default true).
---@field dry_run             boolean   Log without executing (default false).
---@field update_references   boolean   Fallback require()/import rewrite across the
---                                     project when no LSP client applied a
---                                     workspace edit, or the file is Lua (default true).
---@field check_markdown_refs boolean   After a successful rename, offer to update markdown `[text](path)` links pointing at the old path, via markdown.nvim's optional `find_references` (default true; no-op if markdown.nvim isn't installed).
---@field refs_picker_prefer  "auto"|"telescope"|"fzf-lua"|"quickfix"  Backend for the "Inspect references" chooser option (default "auto").

-- ── path_copy ────────────────────────────────────────────────────────────────

---@class FiletreePathCopyConfig
---@field enabled             boolean
---@field keymap_pick         string?  Opens format picker (default nil, off).
---@field keymap_abs          string?  Copy absolute path (default "[a").
---@field keymap_dirname      string?  Copy absolute parent directory (default "]a").
---@field keymap_name         string?  Copy filename only (default nil, off).
---@field keymap_project_root string?  Copy absolute project root path (default "[R").
---@field keymap_project_rel  string?  Copy path relative to project root (default "]R").
---@field root_markers        string[]|false  Markers for project-root detection (default { ".git" }); false → use cwd.
---@field notify              boolean  Show notification after copy (default true).

-- ── live_search ──────────────────────────────────────────────────────────────

---@class FiletreeLiveSearchConfig
---@field enabled           boolean
---@field keymap            string?  Key to open live search (default "gs").
---@field match             "name"|"path"  Match against filename or full path (default "name").
---@field hl_match          string   Highlight for matched nodes (default "Search").
---@field hl_dim            string   Highlight for non-matched nodes (default "Comment").
---@field commit_to_filter  boolean  Enter pushes query to filter feature (default true).
---@field debounce_ms       integer  TextChanged debounce (default 80ms).

-- ── node_info ────────────────────────────────────────────────────────────────

---@class FiletreeNodeInfoConfig
---@field enabled          boolean
---@field keymap           string?   Key inside tree (default "I").
---@field show_lines       boolean   Show line count for files (default true).
---@field max_lines_size   integer   Skip line count for files larger than this in bytes (default 5MB).
---@field max_entries      integer?  Cap for the recursive directory scan behind Items/Size (default 100000).

-- ── cheatsheet ────────────────────────────────────────────────────────────────

---@class FiletreeCheatsheetConfig
---@field enabled boolean
---@field keymap  string?  Key inside tree (default "?"). No-op on the neotree adapter (native `?` already covers it via attach.lua).

-- ── tree_traverse ─────────────────────────────────────────────────────────────

---@class FiletreeTreeTraverseConfig
---@field enabled       boolean
---@field keymap_up     string?   Navigate to parent directory (default "-").
---@field keymap_down   string?   Set current dir as root (default "+").
---@field sync_cwd      boolean   Also change Vim's cwd (default true).

-- ── lua_require_copy ─────────────────────────────────────────────────────────

---@class FiletreeLuaRequireCopyConfig
---@field enabled   boolean
---@field keymap    string?   Key inside tree (default "rq").

-- ── copy_file_list ────────────────────────────────────────────────────────────

---@class FiletreeCopyFileListConfig
---@field enabled          boolean
---@field keymap_files_abs string?   Copy absolute file paths (default "[f").
---@field keymap_files_rel string?   Copy relative file paths (default "]f").
---@field keymap_dirs_abs  string?   Copy absolute dir paths  (default "[F").
---@field keymap_dirs_rel  string?   Copy relative dir paths  (default "]F").
---@field preview_limit    integer   Max lines shown in notification (default 5).
---@field separator        string    Separator between paths (default "\\n").

-- ── markdown_links ────────────────────────────────────────────────────────────

---@class FiletreeMarkdownLinksConfig
---@field enabled            boolean
---@field keymap             string?  Markdown link for current node (default "ML").
---@field keymap_recursive   string?  Markdown links recursively (default "MR").
---@field keymap_from_marked string?  Markdown links from marked nodes (default "MM").

-- ── smart_create ──────────────────────────────────────────────────────────────

---@class FiletreeSmartCreateConfig
---@field enabled              boolean
---@field keymap               string?   Key inside tree (default "a").
---@field auto_init_lua        boolean   Dirs → create init.lua (default true).
---@field auto_types_template  boolean   @types dirs → ---@meta template (default true).
---@field auto_module_annot    boolean   .lua files → ---@module annotation (default true).
---@field ask_clipboard        boolean   Ask whether to paste clipboard content (default true).
---@field notify_level         "verbose"|"short"|"off"  Success-message verbosity (default "verbose").
---                                     "verbose": "Created file/directory: <path>". "short": just
---                                     "Path: <path>". "off": no notification at all.

-- ── cursor_hide ───────────────────────────────────────────────────────────────

---@class FiletreeCursorHideConfig
---@field enabled  boolean  Hide block cursor while tree window is focused (uses winhighlight, not global Cursor hl).

-- ── tree_reset ────────────────────────────────────────────────────────────────

---@class FiletreeTreeResetConfig
---@field enabled  boolean
---@field keymap   string?  Key in tree buffer (default "<Esc>"). Clears preview, filter, live-search, watcher quarantine, and search highlights.

-- ── open_replace ──────────────────────────────────────────────────────────────

---@class FiletreeOpenReplaceConfig
---@field enabled     boolean
---@field keymap      string?   Key in tree buffer (default "O").
---@field close_tree  boolean   Close the tree after opening the file (default true).

-- ── open_variants ─────────────────────────────────────────────────────────────

---@class FiletreeOpenVariantsConfig
---@field enabled          boolean
---@field keymap_vsplit    string?  Open in a vertical split (default "sg").
---@field keymap_split     string?  Open in a horizontal split (default "sv").
---@field keymap_tabnew    string?  Open in a new tab (default "st").
---@field keymap_badd      string?  Add to buffer list without switching focus (default "gb").
---@field keymap_badd_alt  string?  Same as keymap_badd (default "<S-CR>").

-- ── reveal_alt ────────────────────────────────────────────────────────────────

---@class FiletreeRevealAltConfig
---@field enabled  boolean
---@field keymap   string?  Key in tree buffer (default "B"). Reveals the alternate buffer (#) in the tree.

-- ── buffer_save ───────────────────────────────────────────────────────────────

---@class FiletreeBufferSaveConfig
---@field enabled          boolean
---@field keymap_adjacent  string?   Save last adjacent editor buffer (default "<C-s>").
---@field keymap_node      string?   Save buffer matching node under cursor (default "<M-s>").
---@field force            boolean   Use write! (default true). false → update (no-op when unmodified).

-- ── window_size_cycler ────────────────────────────────────────────────────────

---@class FiletreeWindowSizeCyclerConfig
---@field enabled  boolean
---@field keymap   string?     Key in tree buffer (default "w").
---@field sizes    integer[]?  Width presets to cycle through (default { 30, 50, 15 }).

-- ── open_in_fm ────────────────────────────────────────────────────────────────

---@class FiletreeOpenInFmConfig
---@field enabled   boolean
---@field keymap    string?  Key in tree buffer (default "<leader>fm").
---@field command   string?  Override launch binary (auto-detected per OS by default).

-- ── shell_run ─────────────────────────────────────────────────────────────────

---@class FiletreeShellRunConfig
---@field enabled      boolean
---@field keymap       string?   Key in tree buffer (default "i").
---@field close_on_ok  boolean   Auto-close terminal when command exits 0 (default true).
---@field split        string?   "split" | "vsplit" (default "split").
---@field height       integer?  Terminal height in lines for horizontal split (default 12).

return {}
