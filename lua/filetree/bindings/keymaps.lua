---@module 'filetree.bindings.keymaps'
---@brief Catalog of default keymaps, grouped by feature category.
---@description
--- Reference catalog of the keymaps filetree.nvim binds out of the box. It mirrors
--- the per-feature defaults (which remain the runtime source of truth and stay
--- user-configurable). Used for the `docs/BINDINGS.lua` cheatsheet and the
--- optional which-key integration.
---
--- Each entry: { lhs, desc, feature, scope = "tree"|"global", opt_in? = true }
---   scope "tree"   — buffer-local in the tree window
---   scope "global" — normal-mode, everywhere
---   opt_in         — feature is disabled by default (see DEFAULT_DISABLED)

---@class FiletreeBinding
---@field lhs     string
---@field desc    string
---@field feature string
---@field scope   "tree"|"global"
---@field opt_in? boolean

---@type table<string, FiletreeBinding[]>
return {
  nav = {
    { lhs = "<leader>ftp", desc = "Picker — reveal current file", feature = "picker", scope = "global" },
    { lhs = "<leader>ftc", desc = "Picker — open at cwd",          feature = "picker", scope = "global" },
    { lhs = "-",  desc = "Parent directory (up)",       feature = "tree_traverse", scope = "tree" },
    { lhs = "+",  desc = "Set dir under cursor as root", feature = "tree_traverse", scope = "tree" },
    { lhs = "<C-o>", desc = "Jump list: back",    feature = "jump_list", scope = "tree" },
    { lhs = "<C-i>", desc = "Jump list: forward", feature = "jump_list", scope = "tree" },
    { lhs = "<C-p>", desc = "Quick open (frecency)", feature = "quick_open", scope = "tree" },
    { lhs = "B",  desc = "Reveal alternate buffer (#)", feature = "reveal_alt", scope = "tree" },
    { lhs = "<leader>el", desc = "Toggle tree (left)",    feature = "tree_open_keymaps", scope = "global", opt_in = true },
    { lhs = "<leader>er", desc = "Toggle tree (right)",   feature = "tree_open_keymaps", scope = "global", opt_in = true },
    { lhs = "<leader>ef", desc = "Toggle tree (float)",   feature = "tree_open_keymaps", scope = "global", opt_in = true },
    { lhs = "<leader>ec", desc = "Open tree (current window)", feature = "tree_open_keymaps", scope = "global", opt_in = true },
  },
  ui = {
    { lhs = "<Tab>", desc = "Preview toggle; image/PDF dispatch", feature = "preview", scope = "tree" },
    { lhs = "<CR>",  desc = "Image/PDF dispatch; else adapter default", feature = "preview", scope = "tree" },
    { lhs = "I",  desc = "Node info float",       feature = "node_info", scope = "tree" },
    { lhs = "w",  desc = "Cycle window size",     feature = "window_size_cycler", scope = "tree" },
    { lhs = "<Esc>", desc = "Reset preview + filter + search", feature = "tree_reset", scope = "tree" },
    { lhs = "cl", desc = "Open color-label picker", feature = "color_labels", scope = "tree" },
    { lhs = "gi", desc = "Toggle ignore-pattern dim", feature = "ignore_patterns", scope = "tree" },
  },
  fileops = {
    { lhs = "a",  desc = "Smart create file/dir",  feature = "smart_create", scope = "tree" },
    { lhs = "yy", desc = "Stage node for copy",    feature = "copy_move", scope = "tree" },
    { lhs = "xx", desc = "Stage node for cut",     feature = "copy_move", scope = "tree" },
    { lhs = "p",  desc = "Paste staged nodes",     feature = "copy_move", scope = "tree" },
    { lhs = "P",  desc = "Show copy/cut clipboard", feature = "copy_move", scope = "tree" },
    { lhs = "<C-d>", desc = "Duplicate node",      feature = "duplicate_node", scope = "tree" },
    { lhs = "R",  desc = "Batch rename buffer",    feature = "rename_batch", scope = "tree" },
    { lhs = "<F2>", desc = "Rename with LSP refs", feature = "smart_rename", scope = "tree" },
    { lhs = "sl", desc = "Follow symlink",         feature = "symlink", scope = "tree" },
    { lhs = "sL", desc = "Create symlink",         feature = "symlink", scope = "tree" },
    { lhs = "t",  desc = "Create from template",   feature = "create_from_template", scope = "tree" },
    { lhs = "az", desc = "Zip current node",       feature = "archive", scope = "tree" },
    { lhs = "at", desc = "Tar.gz current node",    feature = "archive", scope = "tree" },
    { lhs = "O",  desc = "Open (replace buffer)",  feature = "open_replace", scope = "tree" },
    { lhs = "<C-s>", desc = "Save adjacent buffer", feature = "buffer_save", scope = "tree" },
    { lhs = "<M-s>", desc = "Save node buffer",     feature = "buffer_save", scope = "tree" },
    { lhs = "gx", desc = "Toggle execute bit",     feature = "file_permissions", scope = "tree" },
    { lhs = "gX", desc = "Interactive chmod",      feature = "file_permissions", scope = "tree" },
    { lhs = "gP", desc = "Show stat details",      feature = "file_permissions", scope = "tree" },
  },
  search = {
    { lhs = "/",  desc = "Filter tree",            feature = "filter", scope = "tree" },
    { lhs = "gs", desc = "Live search",            feature = "live_search", scope = "tree" },
    { lhs = "f",  desc = "Find files",             feature = "find_files", scope = "tree" },
    { lhs = "<M-p>", desc = "Find/grep menu",      feature = "find_or_grep_menu", scope = "tree" },
    { lhs = "gr", desc = "Grep in dir",            feature = "grep_in_dir", scope = "tree" },
    { lhs = "gR", desc = "Grep <cword> in dir",    feature = "grep_in_dir", scope = "tree" },
    { lhs = "r",  desc = "Recent files",           feature = "recent_files", scope = "tree" },
  },
  paths = {
    { lhs = "[a", desc = "Copy absolute path",     feature = "path_copy", scope = "tree" },
    { lhs = "]a", desc = "Copy relative path",     feature = "path_copy", scope = "tree" },
    { lhs = "<leader>yp", desc = "Copy path (pick format)", feature = "path_copy", scope = "tree" },
    { lhs = "<leader>yn", desc = "Copy filename",  feature = "path_copy", scope = "tree" },
    { lhs = "rq", desc = "Copy as require(\"…\")",  feature = "lua_require_copy", scope = "tree" },
    { lhs = "[f", desc = "Copy file list (abs)",   feature = "copy_file_list", scope = "tree" },
    { lhs = "]f", desc = "Copy file list (rel)",   feature = "copy_file_list", scope = "tree" },
    { lhs = "[F", desc = "Copy dir list (abs)",    feature = "copy_file_list", scope = "tree" },
    { lhs = "]F", desc = "Copy dir list (rel)",    feature = "copy_file_list", scope = "tree" },
    { lhs = "ya", desc = "Copy absolute path",     feature = "path_utils", scope = "tree", opt_in = true },
    { lhs = "yr", desc = "Copy relative path",     feature = "path_utils", scope = "tree", opt_in = true },
    { lhs = "yn", desc = "Copy filename",          feature = "path_utils", scope = "tree", opt_in = true },
    { lhs = "yd", desc = "Copy parent directory",  feature = "path_utils", scope = "tree", opt_in = true },
    { lhs = "yq", desc = "Copy as require()",       feature = "path_utils", scope = "tree", opt_in = true },
    { lhs = "ym", desc = "Copy as Markdown link",  feature = "path_utils", scope = "tree", opt_in = true },
  },
  git = {
    { lhs = "gB", desc = "Toggle git blame float", feature = "git_blame", scope = "tree" },
    { lhs = "gs", desc = "Stage node ⚠ conflicts with live_search", feature = "git_actions", scope = "tree", opt_in = true },
    { lhs = "gS", desc = "Unstage node",           feature = "git_actions", scope = "tree", opt_in = true },
    { lhs = "gl", desc = "Git log for file",       feature = "git_actions", scope = "tree", opt_in = true },
  },
  org = {
    { lhs = "m",  desc = "Toggle mark",            feature = "marks", scope = "tree" },
    { lhs = "]m", desc = "Mark all visible",       feature = "marks", scope = "tree" },
    { lhs = "[m", desc = "Unmark all visible",     feature = "marks", scope = "tree" },
    { lhs = "<C-m>", desc = "Clear all marks",     feature = "marks", scope = "tree" },
    { lhs = "<leader>ms", desc = "Show marked nodes", feature = "marks", scope = "tree" },
    { lhs = "b",  desc = "Toggle bookmark",        feature = "bookmarks", scope = "tree" },
    { lhs = "gp", desc = "Pin current node",       feature = "pin_node", scope = "tree" },
    { lhs = "gt", desc = "Edit tags",              feature = "tag_system", scope = "tree" },
    { lhs = "gn", desc = "Toggle note",            feature = "notes", scope = "tree" },
    { lhs = "gw", desc = "Switch workspace root",  feature = "workspace", scope = "tree" },
  },
  system = {
    { lhs = "<leader>fm", desc = "Open dir in file manager", feature = "open_in_fm", scope = "tree" },
    { lhs = "ox", desc = "Open with system default", feature = "open_with", scope = "tree" },
    { lhs = "T",  desc = "Open terminal in dir",   feature = "open_terminal", scope = "tree" },
    { lhs = "i",  desc = "Run shell command in dir", feature = "shell_run", scope = "tree" },
  },
  lsp = {
    { lhs = "go", desc = "LSP outline for file",   feature = "outline", scope = "tree" },
    { lhs = "df", desc = "Toggle diagnostic filter", feature = "diagnostics_filter", scope = "tree" },
  },
  compare = {
    { lhs = "D",  desc = "Diff current node",      feature = "diff", scope = "tree" },
    { lhs = "cd", desc = "Compare directories",    feature = "compare_dirs", scope = "tree" },
  },
  integration = {
    { lhs = "gh", desc = "Add to harpoon",         feature = "harpoon_integration", scope = "tree", opt_in = true },
    { lhs = "gH", desc = "Open harpoon menu",      feature = "harpoon_integration", scope = "tree", opt_in = true },
  },
}
