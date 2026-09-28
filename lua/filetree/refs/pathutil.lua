---@module 'filetree.refs.pathutil'
--- Path comparison and resolution helpers shared by every reference provider.
---
--- The rule the whole engine follows: a reference is never matched *textually*
--- against the moved path. It is resolved (relative to the file it appears in)
--- into an absolute path first, and only then compared. Otherwise `../Test.md`
--- written in `docs/` would be missed and a bare `Test.md` would match in every
--- directory of the project.

local ftpath = require("filetree.util.path")
local platform = require("filetree.util.platform")

-- lib.nvim owns the canonical path-key and subpath primitives; both are pure
-- and already handle the Windows separator/drive-letter cases this module
-- would otherwise re-derive. `realpath = false` matters here: half of the
-- comparisons run against a path that has *already* been moved away (or is
-- about to be), so resolving symlinks would either fail or resolve to the
-- wrong side of the mutation.
local normkey = require("lib.nvim.fs.normkey")
local is_subpath = require("lib.nvim.fs.is_subpath")
local relpath = require("lib.nvim.fs.relpath")
local expand_path = require("lib.nvim.cross.fs.expand_path")

local M = {}

---@type boolean  Windows and macOS compare filenames case-insensitively.
local CASE_INSENSITIVE = platform.is_windows() or platform.is_mac()

---Absolute, `.`/`..`-collapsed, forward-slash form of `p`.
---
---Deliberately **lexical**: `vim.fs.normalize` collapses the dot segments
---without ever touching the filesystem, and nothing here calls
---`fnamemodify(":p")`. That matters more than it sounds — on Windows,
---`fnamemodify(":p")` canonicalizes a path it has to rewrite, silently
---expanding an 8.3 short name (`C:/Users/STEFAN~1/…`) to its long form, while
---leaving an already-clean path alone. Two spellings of the same file would
---then key differently for the single reason that one of them was written
---`./Test.md`, and every dotted reference would be missed.
---
---Environment expansion is off too: a link target is a path, not a shell word.
---@param p string
---@return string
function M.abs(p)
  if not p or p == "" then return "" end
  local unified = p:gsub("\\", "/")
  local is_absolute = unified:match("^%a:/") ~= nil
    or unified:sub(1, 1) == "/"
    or unified:sub(1, 1) == "~"
  if not is_absolute then
    local uv = vim.uv or vim.loop
    local cwd = ((uv and uv.cwd and uv.cwd()) or vim.fn.getcwd()):gsub("\\", "/")
    unified = cwd:gsub("/+$", "") .. "/" .. unified
  end
  return (vim.fs.normalize(unified, { expand_env = false }):gsub("/+$", ""))
end

---Canonical comparison key for a path: absolute, forward slashes, uppercased
---drive letter, and lowercased as a whole on case-insensitive filesystems.
---@param p string
---@return string
function M.key(p)
  if not p or p == "" then return "" end
  local k = normkey(M.abs(p), { realpath = false })
  if k == "" then k = ftpath.to_unix(p) end
  k = k:gsub("/+$", "")
  if CASE_INSENSITIVE then k = k:lower() end
  return k
end

---Whether two paths denote the same file.
---@param a string
---@param b string
---@return boolean
function M.same(a, b)
  return M.key(a) == M.key(b)
end

---Whether `p` is `base` or lives underneath it.
---@param p string
---@param base string
---@return boolean
function M.under(p, base)
  if M.same(p, base) then return true end
  return is_subpath(M.key(p), M.key(base))
end

---Environment roots an "as-written" `$VAR/...` target may be anchored on —
---threaded in explicitly by the caller (own_links, wiki-free) rather than
---read from `filetree.refs`'s own config here, to avoid a load cycle
---(providers require this module; `refs/init.lua` requires the providers).
---@class FiletreeRefEnvRoots
---@field names? string[]                        Environment variable names, written without the leading `$`.
---@field extra? { name: string, root: string }[]  Already-resolved roots to try alongside `names` (e.g. `$NVIM_CONFIG_DIR`, backed by `vim.fn.stdpath("config")` rather than an actual env var).

---Resolve `target` (as written in `from_file`) into an absolute path.
---Handles `$VAR/x` (only when `env` is given and `VAR` resolves), `./x`,
---`../x`, `x`, `~/x`, `/x` and Windows drive paths. A leading `/` is
---ambiguous in markdown — it can mean "filesystem root" or "project root" —
---so both readings are returned, in that order, and the caller keeps
---whichever one matches.
---@param target string
---@param from_file string   The file the reference is written in.
---@param root string        Project root, for the root-relative reading.
---@param env? FiletreeRefEnvRoots
---@return string[] candidates  never empty
---@return string[] styles  same length as `candidates`; "env"|"fs"|"root"|"relative" per entry
function M.resolve_candidates(target, from_file, root, env)
  local out, styles = {}, {}
  local t = target:gsub("\\", "/")

  local var = env and t:match("^%$([%w_]+)")
  if env and var then
    local resolved_root ---@type string?
    for _, name in ipairs(env.names or {}) do
      local v = vim.env[name]
      if name == var and type(v) == "string" and v ~= "" then
        resolved_root = v
        break
      end
    end
    if not resolved_root then
      for _, e in ipairs(env.extra or {}) do
        if e.name == var and type(e.root) == "string" and e.root ~= "" then
          resolved_root = e.root
          break
        end
      end
    end
    if resolved_root then
      -- Past "$NAME", stripping one leading "/" so "$VAR" (bare) and
      -- "$VAR/rest" join the same way.
      local rest = t:sub(#var + 2):gsub("^/", "")
      local joined = rest == "" and resolved_root or (resolved_root:gsub("/+$", "") .. "/" .. rest)
      out[#out + 1] = M.abs(joined)
      styles[#styles + 1] = "env"
      return out, styles
    end
    -- Named but unresolved (unset env var, no matching `extra` root): fall
    -- through to the ordinary readings below rather than giving up — an
    -- unset `$VAR` in a target most likely just fails every reading, same as
    -- today's behavior before this branch existed.
  end

  if t:sub(1, 1) == "~" or t:match("^%a:/") then
    -- expand_path, not vim.fn.expand (SEC-34): `target` is a raw reference
    -- string parsed out of a file the user wrote or edited.
    out[#out + 1] = M.abs(expand_path(t))
    styles[#styles + 1] = "fs"
    return out, styles
  end

  if t:sub(1, 1) == "/" then
    out[#out + 1] = M.abs(t)
    styles[#styles + 1] = "fs"
    if root and root ~= "" then
      out[#out + 1] = M.abs(root:gsub("/+$", "") .. t)
      styles[#styles + 1] = "root"
    end
    return out, styles
  end

  out[#out + 1] = M.abs(ftpath.parent(from_file) .. "/" .. t)
  styles[#styles + 1] = "relative"
  return out, styles
end

---Which of `resolve_candidates`' readings actually points at `wanted` (or, for
---a directory move, at something under it). Returns the matching absolute path
---and how it was read, so `retarget` can reproduce the same style.
---@param target string
---@param from_file string
---@param root string
---@param wanted string      The path being moved.
---@param is_dir boolean     Whether `wanted` is a directory (prefix match).
---@param env? FiletreeRefEnvRoots
---@return string? resolved, "env"|"fs"|"root"|"relative"|nil style
function M.match(target, from_file, root, wanted, is_dir, env)
  local candidates, styles = M.resolve_candidates(target, from_file, root, env)
  for i, cand in ipairs(candidates) do
    local hit = is_dir and M.under(cand, wanted) or M.same(cand, wanted)
    if hit then return cand, styles[i] or styles[#styles] end
  end
  return nil, nil
end

---Re-express a moved path in the style the original reference used.
---
---  * `env`      — `$VAR/rest`, refolded via `util.path.env_rooted` (falls
---                 back to `fs` when `opts.env` is missing or nothing matches
---                 anymore — the target's anchor itself moved out from under
---                 every configured root)
---  * `fs`       — absolute filesystem path (`~` re-tildified when the original was)
---  * `root`     — leading-slash, project-root-relative
---  * `relative` — relative to the referencing file's directory, keeping an
---                 explicit `./` prefix when the original had one
---@param opts { style: "env"|"fs"|"root"|"relative", target: string, from_file: string, root: string, new_path: string, env?: FiletreeRefEnvRoots }
---@return string
function M.retarget(opts)
  local style, new_path = opts.style, opts.new_path

  if style == "env" and opts.env then
    local folded, matched = ftpath.env_rooted(new_path, opts.env.names, opts.env.extra)
    if matched then return folded end
    -- Fall through to "fs" below: the moved-to location no longer sits under
    -- any configured env root, so an env-relative spelling cannot be kept.
  end

  if style == "fs" or style == "env" then
    if opts.target:sub(1, 1) == "~" then
      return (vim.fn.fnamemodify(new_path, ":~"):gsub("\\", "/"))
    end
    return ftpath.to_unix(new_path)
  end

  if style == "root" then return "/" .. relpath(new_path, opts.root):gsub("\\", "/") end

  local rel = relpath(new_path, ftpath.parent(opts.from_file)):gsub("\\", "/")
  -- Keep an explicit "./" only when the original had one; a bare "sub/x.md"
  -- stays bare, "./x.md" stays dotted, and anything climbing out with ".."
  -- never gets a "./" prefix.
  if opts.target:sub(1, 2) == "./" and rel:sub(1, 1) ~= "." then rel = "./" .. rel end
  return rel
end

---Apply a directory move to a path that lives underneath it:
---`old_dir/a/b.md` + (old_dir → new_dir) = `new_dir/a/b.md`.
---@param resolved string   Absolute path of the referenced file (under old_dir).
---@param old_dir string
---@param new_dir string
---@return string
function M.remap_under(resolved, old_dir, new_dir)
  local rest = relpath(M.abs(resolved), M.abs(old_dir)):gsub("\\", "/")
  if rest == "." then return M.abs(new_dir) end
  return M.abs(new_dir:gsub("/+$", "") .. "/" .. rest)
end

---Relative path from a directory to a target, POSIX style, with `..` segments.
---Thin pass-through to lib.nvim so providers don't each re-implement it.
---@param target_path string
---@param from_dir string
---@return string
function M.relative(target_path, from_dir)
  return (relpath(target_path, from_dir):gsub("\\", "/"))
end

return M
