---@meta
---@module 'filetree.@types.node'
--- Generic filetree node representation used by all adapters.

---@class FiletreeNode
---@field id          string               Unique node identifier (usually absolute path).
---@field name        string               Display name (filename or directory name).
---@field path        string               Absolute filesystem path.
---@field type        "file"|"directory"
---@field depth       integer              Depth in the tree (root children = 1).
---@field line_number integer              1-based line in the tree buffer.
---@field is_expanded boolean?             true when directory is open. nil for files.
---@field is_link     boolean?             true when the entry itself is a symlink. Populated
---                                        from data the backend already holds (no extra stat);
---                                        nil (not just false) means the backend cannot say.
---@field link_to     string?              Raw link target as the backend read it (may be
---                                        relative), when `is_link` is true and the backend
---                                        exposes it.
---@field link_broken boolean?             true when `is_link` is true and the backend already
---                                        knows the target could not be resolved (a dangling
---                                        symlink). nil means unknown, not "not broken" — some
---                                        backends cannot tell without an extra stat.

return {}
