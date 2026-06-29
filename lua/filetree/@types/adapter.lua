---@meta
---@module 'filetree.@types.adapter'
---@brief Adapter interface every filetree backend must implement.
---@description
--- All methods are called from feature modules and from the adapter registry.
--- Methods must not throw — return false/nil on failure and log internally.

---@class FiletreeAdapter
---@field name string                         Unique adapter identifier ("neotree", "nvimtree", …).
---@field is_available  fun(): boolean         True when the underlying plugin is installed and loaded.
---@field is_open       fun(): boolean, integer?   True when the tree window is visible; second return is bufnr.
---@field get_winid     fun(): integer?            Window id of the tree panel, or nil.
---@field get_root_path fun(): string?             Absolute path of the current tree root.
---@field get_current_node fun(): FiletreeNode?    Node under the cursor, or nil.
---@field get_visible_nodes fun(filter?: FiletreeFilterMode): FiletreeNode[]   All currently rendered nodes.
---@field get_node_line    fun(path: string): integer?   1-based line number of `path` in the tree buffer, or nil.
---@field expand_node      fun(node: FiletreeNode): boolean
---@field collapse_node    fun(node: FiletreeNode): boolean
---@field open_file        fun(path: string, mode?: FiletreeOpenMode): boolean
---@field open_reveal      fun(path: string, parent_levels?: integer): boolean  Open tree and reveal file.
---@field open_cwd         fun(): boolean                                        Open tree at cwd.
---@field close            fun(): boolean
---@field refresh          fun(): boolean
---@field scroll_to_line   fun(line: integer): boolean
---@field highlight_node   fun(path: string, hl_group: string): boolean          Optional — return false if unsupported.
---@field unhighlight_node fun(path: string): boolean                            Optional — return false if unsupported.

---@alias FiletreeAdapterName "neotree"|"nvimtree"|string

---@alias FiletreeFilterMode
---| "all"       All visible nodes (default)
---| "files"     Files only
---| "folders"   Directories only

---@alias FiletreeOpenMode
---| "edit"    Open in current window
---| "split"   Horizontal split
---| "vsplit"  Vertical split
---| "tab"     New tab
---| "preview" Preview (no focus)

return {}
