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
}

-- ── Detection ─────────────────────────────────────────────────────────────────

---@param dir string   Absolute directory path to search from.
---@return string?     Found root, or nil.
local function find_from(dir)
  local current = dir
  local prev    = nil

  while current ~= prev do
    for _, marker in ipairs(_cfg.markers) do
      -- Support simple glob patterns like "*.rockspec"
      if marker:find("*", 1, true) then
        local pattern = current .. "/" .. marker:gsub("%*", ".*")
        local ok, files = pcall(vim.fn.glob, current .. "/" .. marker, false, true)
        if ok and files and #files > 0 then
          return current
        end
      else
        local candidate = current .. "/" .. marker
        if vim.fn.isdirectory(candidate) == 1 or vim.fn.filereadable(candidate) == 1 then
          return current
        end
      end
    end
    prev    = current
    current = vim.fn.fnamemodify(current, ":h")
  end

  return nil
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
