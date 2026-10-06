---@module 'filetree.features.ui.node_info'
---@brief Toggleable hover window showing filesystem metadata for the current tree node.

local line_count = require("filetree.util.line_count")
local ftpath = require("filetree.util.path")

local notify = require("filetree.util.notify").create("[filetree]")
local kit = require("ui.kit")
local bind = require("filetree.util.bind")
local M = {}

---@type FiletreeNodeInfoConfig
local _cfg = {}
---@type FiletreeAdapter?
local _adapter = nil

---@type Ui.Kit.Surface|nil
local _surf = nil
local _last_path = nil

local function close_win()
  if _surf then _surf:close() end
end

---Format bytes into human-readable string.
---@param bytes integer
---@return string
local function fmt_bytes(bytes)
  if bytes < 1024 then
    return bytes .. " B"
  elseif bytes < 1024 * 1024 then
    return string.format("%.1f KiB", bytes / 1024)
  else
    return string.format("%.2f MiB", bytes / (1024 * 1024))
  end
end

---Recursively walk a directory, counting files/subdirs and summing file sizes.
---Bounded by `max_entries` so pressing `I` on a huge tree cannot freeze Neovim;
---if the cap is hit, the result is flagged as truncated.
---@param root string
---@param max_entries integer
---@return { files: integer, dirs: integer, bytes: integer, truncated: boolean }
local function scan_dir(root, max_entries)
  local uv = vim.uv or vim.loop
  local files, dirs, bytes = 0, 0, 0
  local visited = 0
  local truncated = false
  local stack = { root }

  while #stack > 0 do
    local dir = table.remove(stack)
    local fd = uv.fs_scandir(dir)
    if fd then
      while true do
        local name, typ = uv.fs_scandir_next(fd)
        if not name then break end

        visited = visited + 1
        if visited > max_entries then
          truncated = true
          break
        end

        local full = dir .. "/" .. name
        if typ == nil then
          local st = uv.fs_stat(full)
          if st then typ = st.type end
        end

        if typ == "directory" then
          dirs = dirs + 1
          stack[#stack + 1] = full
        else
          -- files, symlinks and other entries count toward the file total
          files = files + 1
          local st = uv.fs_stat(full)
          if st and st.size then bytes = bytes + st.size end
        end
      end
    end
    if truncated then break end
  end

  return { files = files, dirs = dirs, bytes = bytes, truncated = truncated }
end

---Convert stat mode bits to rwxrwxrwx string.
---@param mode integer
---@return string
local function fmt_permissions(mode)
  local bits = { "r", "w", "x", "r", "w", "x", "r", "w", "x" }
  local result = {}
  for i = 8, 0, -1 do
    local bit = math.floor(mode / (2 ^ i)) % 2
    result[#result + 1] = bit == 1 and bits[9 - i] or "-"
  end
  return table.concat(result)
end

---Build human-readable metadata lines for a path (Path/Type/Size/Mode/Modified,
---plus item counts for a directory and a line count for a file). Public so other
---features (e.g. the trash confirm popup) can show the same info without
---duplicating the formatting. Works standalone — no setup() required.
---
---Link-aware: `fs_lstat` (not `fs_stat`) decides the entry's own type first, so
---a symlink is reported as such even when it dangles — `fs_stat` alone would
---see nothing at all through a broken link and fall straight into the
---"No stat info" case, hiding a link that does exist. A file with more than
---one hard-linked name (`nlink > 1`) gets that noted too; every one of its
---names is an equal hard link, so this is "shares its data with N-1 other
---name(s)" rather than "this dirent IS the hard link" — there is no such
---thing as a single dirent to single out. This on-demand check is the only
---place hard links are surfaced at all: unlike the free `is_link`/`link_to`
---the `link_marker` decoration reads off the adapter node, telling a hard
---link apart from an ordinary file needs an actual `stat` per node, which is
---exactly the per-render cost that feature exists to avoid.
---@param path string
---@return string[]
function M.info_lines(path)
  local uv = vim.uv or vim.loop
  local lst = uv.fs_lstat(path)
  if not lst then return { "  No stat info for:", "  " .. path } end

  local is_link = lst.type == "link"
  -- Resolved target stat when the entry is a link; nil for a dangling one.
  local target_stat = is_link and uv.fs_stat(path) or nil
  -- Everything below describes the link's target when it resolves, else
  -- falls back to the link's own (l)stat — e.g. its "Size" is then the raw
  -- link text rather than a target that was never there to measure.
  local stat = target_stat or lst

  local lines = {}
  lines[#lines + 1] = "  Path:     " .. path
  -- The same path as it would be copied (`$REPOS_DIR/...`), when it differs.
  local folded = require("filetree.util.env_roots").fold(path)
  if folded ~= path then lines[#lines + 1] = "  Env path: " .. folded end

  local type_str = stat.type or "unknown"
  if is_link then
    type_str = type_str .. " (symlink)"
  elseif lst.nlink and lst.nlink > 1 and lst.type == "file" then
    type_str = type_str .. string.format(" (hardlink, %d names)", lst.nlink)
  end
  lines[#lines + 1] = "  Type:     " .. type_str

  if is_link then
    local target = uv.fs_readlink(path)
    local broken = target_stat == nil
    lines[#lines + 1] = "  Link to:  "
      .. (target or "?")
      .. (broken and "  (broken — target missing)" or "")
  end

  if stat.type == "directory" then
    -- vim.uv.fs_stat().size is only the directory entry itself (0 on Windows),
    -- so aggregate the real contents instead of showing a misleading size.
    local info = scan_dir(path, _cfg.max_entries or 100000)
    local plus = info.truncated and "+" or ""
    lines[#lines + 1] = string.format(
      "  Items:    %d file%s, %d folder%s%s",
      info.files,
      info.files == 1 and "" or "s",
      info.dirs,
      info.dirs == 1 and "" or "s",
      info.truncated and "  (truncated)" or ""
    )
    lines[#lines + 1] = "  Size:     " .. fmt_bytes(info.bytes) .. plus
  else
    lines[#lines + 1] = "  Size:     " .. fmt_bytes(stat.size)
  end

  -- Permissions (POSIX mode bits, lower 9 bits)
  if stat.mode then lines[#lines + 1] = "  Mode:     " .. fmt_permissions(stat.mode) end

  -- Modified time
  if stat.mtime then
    local t = stat.mtime.sec
    lines[#lines + 1] = "  Modified: " .. os.date("%Y-%m-%d %H:%M:%S", t)
  end

  -- Line count for files
  if _cfg.show_lines ~= false and stat.type == "file" then
    local e = path:match("%.([^.]+)$") or ""
    local limit = _cfg.max_lines_size or line_count.MAX_BYTES
    local count = line_count.count(path, e, limit)
    if count then
      lines[#lines + 1] = "  Lines:    " .. line_count.format(count)
    elseif stat.size > limit then
      lines[#lines + 1] = "  Lines:    (file too large)"
    end
  end

  return lines
end

-- ── References section ────────────────────────────────────────────────────────
-- "Who points at this file", appended to the info only when somebody does. The
-- scan is asynchronous (a project-wide search), so it is cached for a while
-- and the popup does not wait for it.

-- Files listed in the section before "… and N more", and line numbers shown
-- per file. The full list is one command away (`:Filetree references`).
local MAX_REF_FILES = 12
local MAX_REF_LINES = 6
-- How long a count stays valid, in ms. A save elsewhere can change it, so it
-- is short rather than invalidated precisely.
local REFS_TTL_MS = 30000

---@type table<string, { at: integer, u: FiletreeRefUsage }>
local _refs_cache = {}

---@param path string
---@return FiletreeRefUsage?
local function cache_get(path)
  local hit = _refs_cache[path]
  if hit and (vim.uv or vim.loop).now() - hit.at < REFS_TTL_MS then return hit.u end
  _refs_cache[path] = nil
  return nil
end

---Lines of the references section for `u`, or `{}` when nothing references
---the file (no heading, no placeholder).
---@param u FiletreeRefUsage?
---@param root? string  Paths are shown relative to this (default: the cwd).
---@return string[]
function M.references_lines(u, root)
  if not u or u.count == 0 then return {} end

  local lines = { "", string.format("  References (%d)", u.count) }
  local order, by_file = {}, {}
  for _, r in ipairs(u.refs) do
    if not by_file[r.file] then
      by_file[r.file] = {}
      order[#order + 1] = r.file
    end
    local nums = by_file[r.file]
    if nums[#nums] ~= r.line then nums[#nums + 1] = r.line end
  end

  for i, file in ipairs(order) do
    if i > MAX_REF_FILES then
      lines[#lines + 1] =
        string.format("    … and %d more file(s)  (:Filetree references)", #order - MAX_REF_FILES)
      break
    end
    local nums = by_file[file]
    local shown = {}
    for j = 1, math.min(#nums, MAX_REF_LINES) do
      shown[j] = tostring(nums[j])
    end
    lines[#lines + 1] = string.format(
      "    %s:%s%s",
      ftpath.relative(file, root),
      table.concat(shown, ","),
      #nums > MAX_REF_LINES and ",…" or ""
    )
  end
  return lines
end

---Whether `path` gets a references section at all: the option is on and it is
---a file (a directory would mean a scan over everything beneath it per `I`).
---@param path string
---@return boolean
local function wants_references(path)
  if _cfg.references == false then return false end
  local stat = (vim.uv or vim.loop).fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

---Open the viewer for `path` with `lines` and track it as the current one.
---@param path string
---@param lines string[]
---@return boolean ok
local function open_viewer(path, lines)
  local surf = kit.viewer({
    lines = lines,
    title = "Node Info",
    filetype = "filetree_node_info",
  })
  if not surf then
    _surf, _last_path = nil, nil
    return false
  end
  _surf = surf
  _last_path = path
  surf:on_close(function()
    -- A reopen replaces the surface; the old one closing late must not
    -- clear the state of the new one.
    if _surf == surf then
      _surf = nil
      _last_path = nil
    end
  end)
  return true
end

---Count the references to `path` and, when the popup for it is still the
---open one and the count is above zero, reopen it with the section appended.
---@param path string  Slashified key.
---@param node_path string  The path as the tree reported it (what `_last_path` holds).
---@param base_lines string[]  The info lines without a references section.
local function request_references(path, node_path, base_lines)
  require("filetree.refs.usage").count({ path }, nil, function(by_path, meta)
    local u = by_path[path]
    if meta.cancelled or not u then return end
    _refs_cache[path] = { at = (vim.uv or vim.loop).now(), u = u }

    if _last_path ~= node_path or not _surf or not _surf:is_valid() then return end
    local root = require("filetree.refs").resolve_root(path)
    local section = M.references_lines(u, root)
    if #section == 0 then return end

    close_win()
    open_viewer(node_path, vim.list_extend(vim.deepcopy(base_lines), section))
  end)
end

---Show or toggle the hover window for the current node.
function M.show_current()
  if not _adapter then return end

  local node = _adapter.get_current_node()
  if not node or not node.path then
    notify.warn("node_info: no current node")
    return
  end

  -- Toggle: same path closes the window
  if _last_path == node.path then
    close_win()
    return
  end

  -- Close any existing window first
  close_win()

  local path = ftpath.slashify(node.path)
  local lines = M.info_lines(node.path)
  local want_refs = wants_references(path)
  local cached = want_refs and cache_get(path) or nil
  local base_lines = lines
  if cached then lines = vim.list_extend(vim.deepcopy(lines), M.references_lines(cached)) end

  if not open_viewer(node.path, lines) then return end

  -- Not cached: the popup is already up; the section is added (by reopening
  -- with the longer text) as soon as the scan answers, if it found anything.
  if want_refs and not cached then request_references(path, node.path, base_lines) end
end

---Close any open node_info hover window.
function M.close()
  close_win()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type FiletreeNodeInfoConfig
local DEFAULTS = {
  keymap = "I",
  show_lines = true,
  max_entries = 100000, -- cap for the recursive directory scan behind Items/Size
  references = true, -- append a "References (N)" section for a file somebody references
}

---Option schema (see `filetree.config.schema`): exactly what
---`features.node_info` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {
  keymap = "keymap",
  show_lines = "boolean",
  references = "boolean",
  -- The line count is read synchronously on the main loop, so it is capped: a
  -- typo of a few zeros must not freeze Neovim on a large file.
  max_lines_size = { "number", min = 1, max = 256 * 1024 * 1024 },
  max_entries = { "number", min = 1 },
}

---@param cfg FiletreeNodeInfoConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg = vim.tbl_extend("force", DEFAULTS, cfg or {})
  cfg = _cfg
  _adapter = adapter

  bind.bind("node_info", cfg, {
    {
      name = "show",
      field = "keymap",
      desc = "node info",
      rhs = function()
        M.show_current()
      end,
    },
  })
end

function M.teardown()
  close_win()
  _refs_cache = {}
  _adapter = nil
end

return M
