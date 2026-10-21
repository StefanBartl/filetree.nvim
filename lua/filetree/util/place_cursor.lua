---@module 'filetree.util.place_cursor'
--- Put the tree cursor on a path once the tree has actually rendered it.
---
--- A refresh or reveal only guarantees the node turns up *eventually*: neo-tree
--- rescans asynchronously, and on the way it puts the cursor back on whatever
--- node it was on before. So the line is looked up again on a short, bounded
--- schedule until it is there, then the cursor is moved onto it.
---
--- Used by `auto_reveal` (after an `open_reveal`) and by `smart_create` (after
--- creating a file or directory and refreshing the tree).

local M = {}

---Default retry schedule, as successive delays in ms: about a second in total,
---then it gives up rather than fighting whatever else is moving the cursor.
---@type integer[]
M.DELAYS_MS = { 60, 120, 240, 480 }

---@class FiletreePlaceCursorOpts
---@field anchor? integer  Tree cursor line when the operation started. When set, give up as soon as the cursor is somewhere else: either the tree plugin focused the node itself or the user moved on.
---@field hold? FiletreePlaceCursorHold  Where the tree cursor was when a REFRESH was started (`smart_create`). A refresh puts the cursor back where it was when it renders -- possibly after the cursor was already placed (the path was in the tree before the refresh drew). neo-tree puts it back on the same LINE (it saves `lnum`), other trees on the same NODE. So the cursor is not left after the first hit: through the whole schedule, a cursor found back on that line or that node is placed again; one found anywhere else but the path means the user moved, and that ends it.
---@field delays? integer[]  Retry schedule in ms (default `M.DELAYS_MS`).
---@field key? string  Calls with the same key replace each other: a second create within the schedule ends the first one's retries, which would otherwise pull the cursor back to the first path.

---@class FiletreePlaceCursorHold
---@field line integer the tree cursor line
---@field path string|nil the path of the node on it

--- The latest call per `opts.key`.
---@type table<string, table>
local latest = {}

---@internal
---@param winid integer
---@return integer|nil
local function cursor_line(winid)
  local ok, pos = pcall(vim.api.nvim_win_get_cursor, winid)
  return ok and pos[1] or nil
end

---@internal
---@param adapter FiletreeAdapter|fun(): FiletreeAdapter?
---@param path string
---@param opts FiletreePlaceCursorOpts
---@param attempt integer
local function try(adapter, path, opts, attempt)
  if opts.key and latest[opts.key] ~= opts then return end
  local a = type(adapter) == "function" and adapter() or adapter
  if
    type(a) ~= "table"
    or type(a.get_node_line) ~= "function"
    or type(a.scroll_to_line) ~= "function"
  then
    return
  end
  local winid = a.get_winid and a.get_winid() or -1
  if not winid or winid <= 0 or not vim.api.nvim_win_is_valid(winid) then return end
  if opts.anchor and cursor_line(winid) ~= opts.anchor then return end

  local line = a.get_node_line(path)
  if opts.hold then
    local cur = cursor_line(winid)
    local back_on_node = opts.hold.path and cur == a.get_node_line(opts.hold.path)
    -- Anywhere but where it started (that line, or that node) or on the path:
    -- the user moved it.
    if cur ~= line and cur ~= opts.hold.line and not back_on_node then return end
    if line and cur ~= line then a.scroll_to_line(line) end
  elseif line then
    a.scroll_to_line(line)
    return
  end
  local delay = (opts.delays or M.DELAYS_MS)[attempt]
  if not delay then return end
  vim.defer_fn(function()
    try(adapter, path, opts, attempt + 1)
  end, delay)
end

---Move the tree cursor onto `path` now if it is rendered, otherwise as soon as
---it is (within `opts.delays`). A path that never shows up -- its parent is
---collapsed, the tree is closed -- leaves the cursor alone.
---@param adapter FiletreeAdapter|fun(): FiletreeAdapter?  The adapter, or a getter (re-read on every retry, so a torn-down feature stops).
---@param path string
---@param opts? FiletreePlaceCursorOpts
function M.when_rendered(adapter, path, opts)
  opts = vim.tbl_extend("force", {}, opts or {})
  if opts.key then latest[opts.key] = opts end
  try(adapter, path, opts, 1)
end

return M
