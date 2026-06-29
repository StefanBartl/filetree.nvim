---@meta
---@module 'filetree.@types.node'
---@brief Generic filetree node representation used by all adapters.

---@class FiletreeNode
---@field id          string               Unique node identifier (usually absolute path).
---@field name        string               Display name (filename or directory name).
---@field path        string               Absolute filesystem path.
---@field type        "file"|"directory"
---@field depth       integer              Depth in the tree (root children = 1).
---@field line_number integer              1-based line in the tree buffer.
---@field is_expanded boolean?             true when directory is open. nil for files.

return {}
