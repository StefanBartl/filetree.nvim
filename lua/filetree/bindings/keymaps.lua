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
    { lhs = "-",  desc = "Parent directory (up)",       feature = "tree_traverse", scope = "tree" },
    { lhs = "+",  desc = "Set dir under cursor as root", feature = "tree_traverse", scope = "tree" },
    { lhs = "B",  desc = "Reveal alternate buffer (#)", feature = "reveal_alt", scope = "tree" },
  },
  ui = {
    { lhs = "<Tab>", desc = "Preview toggle; image/PDF dispatch", feature = "preview", scope = "tree" },
    { lhs = "<CR>",  desc = "Image/PDF dispatch; else adapter default", feature = "preview", scope = "tree" },
    { lhs = "I",  desc = "Node info float",       feature = "node_info", scope = "tree" },
    { lhs = "w",  desc = "Cycle window size",     feature = "window_size_cycler", scope = "tree" },
    { lhs = "<Esc>", desc = "Reset preview + filter + search", feature = "tree_reset", scope = "tree" },
    { lhs = "?",  desc = "Keymap cheatsheet (native `?` on neotree instead)", feature = "cheatsheet", scope = "tree" },
  },
  fileops = {
    { lhs = "a",  desc = "Smart create file/dir",  feature = "smart_create", scope = "tree" },
    { lhs = "c",  desc = "Stage node for copy",    feature = "copy_move", scope = "tree" },
    { lhs = "x",  desc = "Stage node for cut",     feature = "copy_move", scope = "tree" },
    { lhs = "p",  desc = "Paste staged nodes",     feature = "copy_move", scope = "tree" },
    { lhs = "P",  desc = "Show copy/cut clipboard", feature = "copy_move", scope = "tree" },
    { lhs = "<C-c>", desc = "Clear copy/cut clipboard ⚠ conflicts with filter.keymap_clear", feature = "copy_move", scope = "tree" },
    { lhs = "<leader>rb", desc = "Batch rename buffer", feature = "rename_batch", scope = "tree" },
    { lhs = "r",  desc = "Rename with LSP refs",   feature = "smart_rename", scope = "tree" },
    { lhs = "t",  desc = "Create from template",   feature = "create_from_template", scope = "tree" },
    { lhs = "O",  desc = "Open (replace buffer)",  feature = "open_replace", scope = "tree" },
    { lhs = "sg", desc = "Open in vertical split", feature = "open_variants", scope = "tree" },
    { lhs = "sv", desc = "Open in horizontal split", feature = "open_variants", scope = "tree" },
    { lhs = "st", desc = "Open in new tab",        feature = "open_variants", scope = "tree" },
    { lhs = "gb", desc = "Add to buffer list (no focus switch)", feature = "open_variants", scope = "tree" },
    { lhs = "<S-CR>", desc = "Add to buffer list (no focus switch)", feature = "open_variants", scope = "tree" },
    { lhs = "d",  desc = "Trash current node (or marked)", feature = "trash", scope = "tree" },
    { lhs = "U",  desc = "Undo last trash operation", feature = "trash", scope = "tree" },
    { lhs = "<leader>th", desc = "Show trash history", feature = "trash", scope = "tree" },
    { lhs = "<C-s>", desc = "Save adjacent buffer", feature = "buffer_save", scope = "tree" },
    { lhs = "<M-s>", desc = "Save node buffer",     feature = "buffer_save", scope = "tree" },
  },
  search = {
    { lhs = "/",  desc = "Filter tree",            feature = "filter", scope = "tree" },
    { lhs = "<C-c>", desc = "Clear applied filter ⚠ conflicts with copy_move.keymaps.clear", feature = "filter", scope = "tree" },
    { lhs = "gs", desc = "Live search",            feature = "live_search", scope = "tree" },
    { lhs = "f",  desc = "Find files",             feature = "find_files", scope = "tree" },
    { lhs = "tf", desc = "Find files via telescope specifically", feature = "find_files", scope = "tree" },
    { lhs = "gr", desc = "Grep in dir",            feature = "grep_in_dir", scope = "tree" },
    { lhs = "tg", desc = "Grep via telescope specifically", feature = "grep_in_dir", scope = "tree" },
  },
  paths = {
    { lhs = "[a", desc = "Copy absolute path",     feature = "path_copy", scope = "tree" },
    { lhs = "]a", desc = "Copy absolute parent directory", feature = "path_copy", scope = "tree" },
    { lhs = "rq", desc = "Copy as require(\"…\")",  feature = "lua_require_copy", scope = "tree" },
    { lhs = "[f", desc = "Copy file list (abs)",   feature = "copy_file_list", scope = "tree" },
    { lhs = "]f", desc = "Copy file list (rel)",   feature = "copy_file_list", scope = "tree" },
    { lhs = "[F", desc = "Copy dir list (abs)",    feature = "copy_file_list", scope = "tree" },
    { lhs = "]F", desc = "Copy dir list (rel)",    feature = "copy_file_list", scope = "tree" },
    { lhs = "ML", desc = "Markdown link for current node", feature = "markdown_links", scope = "tree" },
    { lhs = "MR", desc = "Markdown links recursively",     feature = "markdown_links", scope = "tree" },
    { lhs = "MM", desc = "Markdown links from marked",     feature = "markdown_links", scope = "tree" },
  },
  git = {
  },
  org = {
    { lhs = "m",  desc = "Toggle mark",            feature = "marks", scope = "tree" },
    { lhs = "]m", desc = "Mark all visible",       feature = "marks", scope = "tree" },
    { lhs = "[m", desc = "Unmark all visible",     feature = "marks", scope = "tree" },
    { lhs = "<C-m>", desc = "Clear all marks",     feature = "marks", scope = "tree" },
    { lhs = "<leader>ms", desc = "Show marked nodes", feature = "marks", scope = "tree" },
  },
  system = {
    { lhs = "<leader>fm", desc = "Open dir in file manager", feature = "open_in_fm", scope = "tree" },
    { lhs = "<leader>sm", desc = "Open with system default", feature = "open_with", scope = "tree" },
    { lhs = "i",  desc = "Run shell command in dir", feature = "shell_run", scope = "tree" },
  },
  lsp = {
  },
  compare = {
    { lhs = "D",  desc = "Diff current node",      feature = "diff", scope = "tree" },
  },
}
