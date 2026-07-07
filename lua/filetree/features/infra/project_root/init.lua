---@module 'filetree.features.project_root'
---@brief Project root detection from a file path.
---@description
--- Walks up the directory tree from a given path looking for root markers.
--- Returns the deepest directory that contains a recognized marker file,
--- or the original directory when no marker is found.
---
--- Integrates with cwd_sync: when enabled, open_reveal uses the project root
--- as the tree root instead of the buffer's immediate parent directory.

local M = {}

---@type FiletreeProjectRootConfig
local _cfg = {
  enabled  = false,
  markers  = {
    ".git", ".hg", ".svn",
    "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
    "Cargo.toml",
    "go.mod",
    "pyproject.toml", "setup.py", "setup.cfg",
    "Makefile", "CMakeLists.txt",
    "*.rockspec",
    ".luarc.json", "selene.toml",
    "mix.exs",
    "build.zig",
  },
  fallback = "parent",
  cache    = true,
}

-- ── Cache ─────────────────────────────────────────────────────────────────────
-- A directory's project root essentially never changes within a session, so
-- every directory visited on a walk is cached, not just the query directory
-- itself -- e.g. resolving "/a/b/c/d" (root "/a") also caches "/a/b/c" and
-- "/a/b" as root "/a", so a later query for either hits the cache directly
-- instead of re-walking. Keyed by directory (not by file), since every file
-- in the same directory shares the same root -- this is deliberately a plain
-- hash map (O(1) lookup by path), not a ring buffer: a ring buffer bounds an
-- ordered *history*, but what's needed here is key-based lookup, which a
-- table already gives for free. Capped and cleared in one shot (not a real
-- LRU) once it grows past MAX_CACHE_ENTRIES, so a very long session visiting
-- many one-off directories can't grow this unboundedly.
---@type table<string, string|false>  dir -> root, or false for "no root found"
local _cache = {}
local MAX_CACHE_ENTRIES = 1000

---Clear the project-root cache. Call this if a `.git` (or other marker) gets
---added/removed under a directory already visited this session.
function M.clear_cache()
  _cache = {}
end

-- ── Detection ─────────────────────────────────────────────────────────────────

---@param dir string   Absolute directory path to search from.
---@return string?     Found root, or nil.
local function find_from(dir)
  if _cfg.cache ~= false then
    local cached = _cache[dir]
    if cached ~= nil then
      return cached or nil
    end
  end

  local visited = { dir }
  local current = dir
  local prev    = nil
  local found   = nil

  while current ~= prev do
    for _, marker in ipairs(_cfg.markers) do
      -- Support simple glob patterns like "*.rockspec"
      if marker:find("*", 1, true) then
        local ok, files = pcall(vim.fn.glob, current .. "/" .. marker, false, true)
        if ok and files and #files > 0 then
          found = current
          break
        end
      else
        local candidate = current .. "/" .. marker
        if vim.fn.isdirectory(candidate) == 1 or vim.fn.filereadable(candidate) == 1 then
          found = current
          break
        end
      end
    end
    if found then break end
    prev    = current
    current = vim.fn.fnamemodify(current, ":h")
    if current ~= prev then visited[#visited + 1] = current end
  end

  if _cfg.cache ~= false then
    if vim.tbl_count(_cache) >= MAX_CACHE_ENTRIES then
      _cache = {}
    end
    for _, d in ipairs(visited) do
      _cache[d] = found or false
    end
  end

  return found
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Find the project root for a given file path.
---@param path string  Absolute file or directory path.
---@return string      Project root, or fallback (cwd/parent directory).
function M.find(path)
  local dir = vim.fn.isdirectory(path) == 1
    and path
    or vim.fn.fnamemodify(path, ":h")

  local root = find_from(dir)
  if root then return root end

  if _cfg.fallback == "cwd" then
    return vim.fn.getcwd()
  end
  return dir
end

---Return true when `path` is inside a detectable project root.
---@param path string
---@return boolean
function M.has_root(path)
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
  return find_from(dir) ~= nil
end

---Add custom root markers at runtime.
---@param markers string[]
function M.add_markers(markers)
  for _, m in ipairs(markers) do
    _cfg.markers[#_cfg.markers + 1] = m
  end
  -- A negative (no-root-found) cache entry could now resolve differently.
  M.clear_cache()
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeProjectRootConfig
---@param _adapter FiletreeAdapter
function M.setup(config, _adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)
end

function M.teardown()
  _cfg.enabled = false
end

return M
