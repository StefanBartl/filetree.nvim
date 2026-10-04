---@module 'filetree.features.nav.quickpick.logic'
---@brief Pure logic of the numbered quick-pick mode: numbering and the input parser.
---@description
--- Everything in here is free of UI, adapters and Neovim state: it takes plain
--- tables and returns plain tables, so it is specified without a tree, a
--- window or a key being pressed (`TESTS/quickpick.lua`). The lifecycle
--- (keys, extmarks, timers) lives in `init.lua` and only calls into this.
---
--- ### Numbering
---
--- `assign()` turns the adapter's visible nodes into numbered entries:
--- filter by content kind, keep only the nodes inside the window's visible
--- line range, order by rendered line, number from 0 and cap at the capacity
--- of the label width (`10^width`; two digits = 00..99). The numbers are
--- therefore always the ones on screen, and scrolling or expanding a folder
--- is a fresh `assign()` -- never a patch of the previous result.
---
--- ### Input
---
--- A label is exactly `width` digits, so there is no "is 1 the number or the
--- start of 12?" ambiguity and no need for Enter. The parser (`feed()`) is a
--- tiny state machine over `{ mode, digits }`:
---
---   * a mode key (`s`/`v`/`t`/`e`) switches the open mode -- only while no
---     digit has been typed yet; afterwards it is ignored (the mode is locked
---     for the number in progress, as the concept asks);
---   * a digit is appended; the `width`-th one completes the number;
---   * backspace drops the last digit.
---
--- It is functional: `feed()` returns the next state and what happened,
--- and never mutates its argument.

local M = {}

---@alias FiletreeQuickpickContent "all"|"files"|"folders"

---@class FiletreeQuickpickEntry
---@field index integer          0-based number (what the user types).
---@field label string           Zero-padded number, exactly `width` characters.
---@field line integer           1-based tree-buffer line.
---@field node FiletreeNode

---@class FiletreeQuickpickInput
---@field mode FiletreeOpenMode  Selected open mode.
---@field digits string          Digits typed so far (0..width-1 characters).

---@class FiletreeQuickpickEvent
---@field kind "digit"|"mode"|"backspace"
---@field value? string          The digit, or the open mode, for those kinds.

---Open modes a mode key can select. `preview` exists in the adapter contract
---but is a plain split on most backends, so it is not offered here.
---@type FiletreeOpenMode[]
M.OPEN_MODES = { "edit", "split", "vsplit", "tab" }

---Content kinds, in cycling order.
---@type FiletreeQuickpickContent[]
M.CONTENT_KINDS = { "all", "files", "folders" }

---Allowed values of the indicator position tuple, per slot.
M.POSITION_SLOTS = {
  { "nvim", "filetree" },
  { "top", "bottom" },
  { "left", "center", "right" },
}

---@type string[]
M.POSITION_DEFAULT = { "nvim", "top", "center" }

---@param list string[]
---@param value any
---@return boolean
local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

---@param kind any
---@return boolean
function M.is_content(kind)
  return contains(M.CONTENT_KINDS, kind)
end

---@param mode any
---@return boolean
function M.is_open_mode(mode)
  return contains(M.OPEN_MODES, mode)
end

---The content kind after `kind` in the cycle all -> files -> folders -> all.
---An unknown value starts the cycle over at "all".
---@param kind any
---@return FiletreeQuickpickContent
function M.next_content(kind)
  for i, k in ipairs(M.CONTENT_KINDS) do
    if k == kind then return M.CONTENT_KINDS[i % #M.CONTENT_KINDS + 1] end
  end
  return "all"
end

---How many labels a width can carry (two digits: 100, i.e. 00..99).
---@param width integer
---@return integer
function M.capacity(width)
  return 10 ^ width
end

---Zero-padded label for `index`.
---@param index integer
---@param width integer
---@return string
function M.format_label(index, width)
  return ("%0" .. width .. "d"):format(index)
end

---A path reduced to a comparison key: forward slashes, runs of slashes
---collapsed (mini.files writes `E://repos` on Windows), no trailing slash.
---@param path string
---@param ignore_case? boolean  Lower-case it too (Windows paths).
---@return string
function M.path_key(path, ignore_case)
  local key = path:gsub("\\", "/"):gsub("(%S)/+", "%1/")
  if #key > 1 then key = key:gsub("/$", "") end
  return ignore_case and key:lower() or key
end

---@param node FiletreeNode
---@param content FiletreeQuickpickContent
---@return boolean
local function matches_content(node, content)
  if content == "files" then return node.type == "file" end
  if content == "folders" then return node.type == "directory" end
  return true
end

---Number the nodes that can be picked right now.
---
--- Nodes without a usable `line_number` are skipped: with no line there is
--- nowhere to draw the label, and a number the user cannot see is a trap.
--- The order is the rendered order (ascending line), not the adapter's
--- array order -- backends disagree on that (neo-tree walks the nui tree,
--- nvim-tree sorts by line, the flat ones read the buffer), and the number
--- must follow what is on screen.
---@param nodes FiletreeNode[]
---@param opts? { content?: FiletreeQuickpickContent, width?: integer, range?: { [1]: integer, [2]: integer }, skip_path?: string, ignore_case?: boolean }
---   `range` = inclusive 1-based first/last buffer line to number (the window's viewport).
---   `skip_path` = a node with this path is not numbered (the tree's own root: some
---   backends list it as a node, and "toggling" it would fold the whole tree);
---   `ignore_case` makes that comparison case-insensitive.
---@return FiletreeQuickpickEntry[] entries
---@return boolean truncated  More nodes qualified than the width can label.
function M.assign(nodes, opts)
  opts = opts or {}
  local content = opts.content or "all"
  local width = opts.width or 2
  local range = opts.range
  local limit = M.capacity(width)
  local skip = nil
  if type(opts.skip_path) == "string" and opts.skip_path ~= "" then
    skip = M.path_key(opts.skip_path, opts.ignore_case)
  end

  ---@type { node: FiletreeNode, line: integer, seq: integer }[]
  local picked = {}
  for seq, node in ipairs(nodes or {}) do
    local line = node.line_number
    if type(line) == "number" and line >= 1 and matches_content(node, content) then
      local is_root = skip ~= nil
        and type(node.path) == "string"
        and M.path_key(node.path, opts.ignore_case) == skip
      if not is_root and (not range or (line >= range[1] and line <= range[2])) then
        picked[#picked + 1] = { node = node, line = line, seq = seq }
      end
    end
  end
  -- `seq` as tie-break: table.sort is not stable, and two nodes on one line
  -- (a grouped chain) must keep the adapter's relative order.
  table.sort(picked, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.seq < b.seq
  end)

  local entries = {}
  for i, p in ipairs(picked) do
    if i > limit then return entries, true end
    entries[i] = {
      index = i - 1,
      label = M.format_label(i - 1, width),
      line = p.line,
      node = p.node,
    }
  end
  return entries, false
end

---The entry carrying number `number`, or nil.
---@param entries FiletreeQuickpickEntry[]
---@param number integer
---@return FiletreeQuickpickEntry?
function M.find(entries, number)
  for _, e in ipairs(entries) do
    if e.index == number then return e end
  end
  return nil
end

---Does `label` still match the digits typed so far?
---@param label string
---@param digits string
---@return boolean
function M.matches_prefix(label, digits)
  return digits == "" or label:sub(1, #digits) == digits
end

---A fresh input state.
---@param mode? FiletreeOpenMode
---@return FiletreeQuickpickInput
function M.new_input(mode)
  return { mode = M.is_open_mode(mode) and mode or "edit", digits = "" }
end

---Advance the input state machine by one event.
---
--- Returns the next state and a result:
---   { kind = "digit" }                       digit appended, number incomplete
---   { kind = "select", number = n }          number complete (digits are reset)
---   { kind = "mode", mode = m }              open mode changed
---   { kind = "locked" }                      mode key refused: a digit is already typed
---   { kind = "backspace" }                   last digit dropped
---   { kind = "none" }                        nothing to do / event not understood
---@param input FiletreeQuickpickInput
---@param ev FiletreeQuickpickEvent
---@param width integer
---@return FiletreeQuickpickInput next
---@return { kind: string, number?: integer, mode?: FiletreeOpenMode } result
function M.feed(input, ev, width)
  local mode, digits = input.mode, input.digits

  if ev.kind == "digit" then
    local d = ev.value
    if type(d) ~= "string" or not d:match("^%d$") then
      return { mode = mode, digits = digits }, { kind = "none" }
    end
    digits = digits .. d
    if #digits >= width then
      return { mode = mode, digits = "" }, { kind = "select", number = tonumber(digits) }
    end
    return { mode = mode, digits = digits }, { kind = "digit" }
  end

  if ev.kind == "mode" then
    if not M.is_open_mode(ev.value) then
      return { mode = mode, digits = digits }, { kind = "none" }
    end
    if digits ~= "" then return { mode = mode, digits = digits }, { kind = "locked" } end
    return { mode = ev.value, digits = "" }, { kind = "mode", mode = ev.value }
  end

  if ev.kind == "backspace" then
    if digits == "" then return { mode = mode, digits = "" }, { kind = "none" } end
    return { mode = mode, digits = digits:sub(1, -2) }, { kind = "backspace" }
  end

  return { mode = mode, digits = digits }, { kind = "none" }
end

---The text of the open-mode indicator: mode, content kind and the number in
---progress, padded with underscores to the label width.
---@param input FiletreeQuickpickInput
---@param content FiletreeQuickpickContent
---@param width integer
---@return string
function M.indicator_text(input, content, width)
  local typed = input.digits .. string.rep("_", math.max(0, width - #input.digits))
  return (" %s | %s | %s "):format(input.mode, content, typed)
end

---Validate a position tuple; any slot that is not an allowed value (or a
---tuple of the wrong shape) falls back to the default for that slot.
---@param pos any
---@return string[] position  { reference, vertical, horizontal }
---@return boolean ok          false when anything had to be replaced.
function M.normalize_position(pos)
  local out, ok = {}, type(pos) == "table"
  for i, allowed in ipairs(M.POSITION_SLOTS) do
    local v = type(pos) == "table" and pos[i] or nil
    if contains(allowed, v) then
      out[i] = v
    else
      out[i] = M.POSITION_DEFAULT[i]
      ok = false
    end
  end
  if type(pos) == "table" and #pos > #M.POSITION_SLOTS then ok = false end
  return out, ok
end

---Top-left corner (0-based, inside the reference area) of an indicator of
---`width` x 1 cells. The width is clamped to the area so a narrow tree window
---still gets a visible (if cut) badge instead of one placed off to its left.
---@param position string[]  Normalized `{ reference, vertical, horizontal }`.
---@param area_w integer     Width of the reference area (editor or tree window).
---@param area_h integer     Height of the reference area.
---@param width integer      Wanted width of the indicator.
---@return integer row, integer col, integer width  `width` after clamping.
function M.indicator_geometry(position, area_w, area_h, width)
  local w = math.max(1, math.min(width, area_w))
  local row = position[2] == "bottom" and math.max(0, area_h - 1) or 0
  local col = 0
  if position[3] == "center" then
    col = math.floor((area_w - w) / 2)
  elseif position[3] == "right" then
    col = area_w - w
  end
  return row, math.max(0, col), w
end

return M
