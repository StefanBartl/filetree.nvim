---@module 'filetree.util.path'
--- Pure path operations: normalize, convert, transform, escape.
---
--- No global state, no project-root lookup — every function derives its result
--- purely from its arguments (relative paths resolve against an explicit base or
--- the cwd). Features that need project-root-relative paths pass the base in.

local platform = require("filetree.util.platform")

-- Optional: lib.nvim ships the same pure separator-unify transform under
-- lib.nvim.cross.fs.separators.unify_slashes. Prefer it when present so both
-- plugins share one implementation; fall back to the local gsub otherwise
-- (mirrors the lib.nvim-optional pattern used by features.ignore_list).
local _ok_cross, _cross_unify = pcall(require, "lib.nvim.cross.fs.separators.unify_slashes")
local _has_cross_unify = _ok_cross and type(_cross_unify) == "function"

-- Optional: lib.nvim.fs.relpath implements the identical "strip base prefix"
-- algorithm used below for the case where `p` lives under `base`. Prefer it
-- when present (same reasoning as unify_slashes above); its behavior for the
-- non-descendant case (return the path unchanged) is intentionally simpler
-- than this module's `:~:.`-tildified fallback, so that fallback stays local.
local _ok_relpath, _lib_relpath = pcall(require, "lib.nvim.fs.relpath")
local _has_lib_relpath = _ok_relpath and type(_lib_relpath) == "function"

-- Optional: lib.nvim.cross.fs.expand_path resolves ~/$VAR/${VAR}/%VAR% before
-- fnamemodify runs. Prefer it when present (same reasoning as unify_slashes
-- above); without it, fall back to vim.fn.expand, which covers ~/$VAR but
-- never %VAR% on Windows.
local _ok_expand, _lib_expand_path = pcall(require, "lib.nvim.cross.fs.expand_path")
local _has_lib_expand_path = _ok_expand and type(_lib_expand_path) == "function"

local M = {}

---Expand env references, resolve to absolute path and strip surrounding quotes.
---@param p string
---@return string
function M.to_absolute(p)
  if _has_lib_expand_path then
    local ok, expanded = pcall(_lib_expand_path, p)
    if ok and type(expanded) == "string" then p = expanded end
  else
    p = vim.fn.expand(p)
  end
  p = vim.fn.fnamemodify(p, ":p")
  return (p:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1"))
end

---Expand to absolute path and normalize separators to the OS default.
---Kept as an alias of to_absolute for backwards compatibility.
---@param p string
---@return string
function M.normalize(p)
  return M.to_absolute(p)
end

---Convert to a Unix-style absolute path (forward slashes).
---@param p string
---@return string
function M.to_unix(p)
  return (M.to_absolute(p):gsub("\\", "/"))
end

---Replace backslashes with forward slashes, without touching absoluteness or
---the path's meaning otherwise (no fnamemodify, no cwd resolution) — a pure
---string transform. This is filetree's single canonical separator: prompts,
---notifications and any other path shown to the user always display with `/`,
---on every OS, and any raw path typed by the user (who may type either `/` or
---`\`) is sanitized to this form immediately after `vim.ui.input` returns, before
---it is used for anything. Forward slashes work fine for Neovim's own path/buffer
---APIs and for libuv on Windows; only literal OS-shell invocations (e.g.
---explorer.exe, cmd /c) need native backslashes, and those call sites convert
---explicitly at the point of use (see open_in_fm/open_with).
---@param p string
---@return string
function M.slashify(p)
  if _has_cross_unify then
    local ok, result = pcall(_cross_unify, p)
    if ok and type(result) == "string" then return result end
  end
  return (p:gsub("\\", "/"))
end

---Convert to a Windows-style absolute path (backslashes).
---@param p string
---@return string
function M.to_win(p)
  return (M.to_absolute(p):gsub("/", "\\"))
end

---Return the parent directory of a path (forward-slash, see M.slashify).
---@param p string
---@return string
function M.parent(p)
  return M.slashify(vim.fn.fnamemodify(p, ":h"))
end

---Return the filename (tail) of a path.
---@param p string
---@return string
function M.basename(p)
  return vim.fn.fnamemodify(p, ":t")
end

---Resolve a path to a directory: a file yields its parent, a directory yields
---itself. Used to turn a node path into a working directory.
---@param p string
---@return string
function M.ensure_dir(p)
  if p == nil or p == "" then return platform.get_cwd() end
  if vim.fn.isdirectory(p) == 1 then return p end
  local parent = M.parent(p)
  if parent == "" or parent == "." then return platform.get_cwd() end
  return parent
end

---Return `p` relative to `base` (default: cwd). Falls back to `:~:.` form when
---`p` is not under `base`. Purely argument-driven — no project-root lookup.
---@param p    string
---@param base string?  Base directory (default: cwd).
---@return string
function M.relative(p, base)
  base = base or platform.get_cwd()
  local abs_p = M.to_unix(p):gsub("/$", "")
  local abs_base = M.to_unix(base):gsub("/$", "")

  -- Descendant check happens locally first (not by inspecting lib.nvim's
  -- return value) so this stays correct regardless of what lib.nvim.fs.relpath
  -- does for the non-descendant case — it only gets called for the exact case
  -- both algorithms are known to agree on.
  if abs_p:sub(1, #abs_base) == abs_base then
    if _has_lib_relpath then
      local ok, rel = pcall(_lib_relpath, abs_p, abs_base)
      if ok and type(rel) == "string" then return rel end
    end
    local rel = abs_p:sub(#abs_base + 2)
    return rel == "" and "." or rel
  end

  -- Not under base (or lib.nvim absent): fall back to fnamemodify's ":~:.",
  -- which additionally tildifies the home directory — a UX nicety this
  -- plugin's display convention wants that lib.nvim.fs.relpath doesn't do.
  -- slashify keeps the result consistent with the forward-slash convention.
  return M.slashify(vim.fn.fnamemodify(abs_p, ":~:."))
end

---@internal
---POSIX-style relative path from `base` to `p`, climbing with `..` when `p` is
---not a descendant. Both arguments must already be absolute, forward-slash and
---without a trailing slash. Mirrors `lib.nvim.fs.relpath`; used only when that
---is unavailable, so both paths produce the same string.
---@param abs_p    string
---@param abs_base string
---@return string
local function relpath_fallback(abs_p, abs_base)
  if abs_p == abs_base then return "." end
  if abs_p:sub(1, #abs_base + 1) == abs_base .. "/" then return abs_p:sub(#abs_base + 2) end

  -- Two Windows drive letters share no root, so no relative form exists.
  local function root_of(s)
    return s:match("^(%a:)/") or (s:sub(1, 1) == "/" and "/") or ""
  end
  if root_of(abs_p) ~= root_of(abs_base) then return abs_p end

  local base_segs, path_segs = {}, {}
  for seg in abs_base:gmatch("[^/]+") do
    base_segs[#base_segs + 1] = seg
  end
  for seg in abs_p:gmatch("[^/]+") do
    path_segs[#path_segs + 1] = seg
  end

  local i = 1
  while base_segs[i] and path_segs[i] and base_segs[i] == path_segs[i] do
    i = i + 1
  end

  local parts = {}
  for _ = i, #base_segs do
    parts[#parts + 1] = ".."
  end
  for j = i, #path_segs do
    parts[#parts + 1] = path_segs[j]
  end
  return #parts > 0 and table.concat(parts, "/") or "."
end

---Return `p` relative to `base` in the form a Markdown link target needs:
---`./x/y` for a descendant, `../x/y` for anything else under a shared root.
---
---This is deliberately not `M.relative`. That one answers "how do I *show* this
---path" and falls back to a `~`-tildified `:~:.` form for a non-descendant,
---which is unusable as a link target; this one answers "what do I *write* into
---a file living in `base`", so it climbs out with `..` and marks a descendant
---with an explicit `./` — a bare `docs/X.md` resolves against the reader's cwd
---in some renderers, `./docs/X.md` never does.
---
---Returns the absolute path unchanged when the two share no root at all
---(different Windows drive letters) — there is no relative form then.
---@param p    string
---@param base string  Base *directory* (for a file, pass its parent).
---@return string
function M.dot_relative(p, base)
  local abs_p = M.to_unix(p):gsub("/+$", "")
  local abs_base = M.to_unix(base):gsub("/+$", "")

  local rel
  if _has_lib_relpath then
    local ok, r = pcall(_lib_relpath, abs_p, abs_base)
    if ok and type(r) == "string" then rel = r end
  end
  rel = rel or relpath_fallback(abs_p, abs_base)

  -- An absolute result is the "no relative form exists" case; leave it be.
  if rel:match("^%a:/") or rel:sub(1, 1) == "/" then return rel end
  if rel == "." or rel == ".." then return rel end
  if rel:match("^%.%.?/") then return rel end
  return "./" .. rel
end

---Rewrite `p` as `$VAR/rest` when it lives under the directory one of `names`
---points at. The longest match wins, so `$REPOS_DIR` beats a `$HOME` that
---contains it. Unset, empty and non-matching variables are skipped; when none
---matches, the plain absolute path comes back.
---
---The point is a path that survives being pasted into a note read on another
---machine, where the repo checkout sits on a different drive: `$REPOS_DIR/x`
---means the same thing on both, `E:/repos/x` does not.
---@param p     string
---@param names string[]  Environment variable names, written without the `$`.
---@return string path
---@return string? name  The variable that matched, if any.
function M.env_rooted(p, names)
  local abs = M.to_unix(p):gsub("/+$", "")
  -- Windows compares paths case-insensitively, and the drive letter alone can
  -- differ in case between `$REPOS_DIR` and what the tree reports for a file
  -- under it — a case-sensitive compare would just never match there.
  local function fold(s)
    return platform.is_windows() and s:lower() or s
  end
  local folded = fold(abs)

  local best_name, best_len
  for _, name in ipairs(names or {}) do
    local root = vim.env[name]
    if type(root) == "string" and root ~= "" then
      local abs_root = M.to_unix(root):gsub("/+$", "")
      local folded_root = fold(abs_root)
      local under = folded == folded_root or folded:sub(1, #folded_root + 1) == folded_root .. "/"
      if abs_root ~= "" and under and (not best_len or #abs_root > best_len) then
        best_name, best_len = name, #abs_root
      end
    end
  end

  if not best_name then return abs end
  local rest = abs:sub(best_len + 2)
  if rest == "" then return "$" .. best_name, best_name end
  return "$" .. best_name .. "/" .. rest, best_name
end

---Escape a path for use as a vim command argument.
---@param p string
---@return string
function M.fnameescape(p)
  return vim.fn.fnameescape(p)
end

---Escape a path as a single shell argument (cross-platform quoting).
---@param p string
---@return string
function M.escape_shell_arg(p)
  if platform.is_windows() then return '"' .. p:gsub('"', '""') .. '"' end
  return "'" .. p:gsub("'", "'\\''") .. "'"
end

---Wrap a path in double quotes only when it contains whitespace.
---@param p string
---@return string
function M.quote_if_needed(p)
  if p:find("%s") then return '"' .. p .. '"' end
  return p
end

return M
