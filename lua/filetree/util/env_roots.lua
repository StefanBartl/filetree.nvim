---@module 'filetree.util.env_roots'
--- Named root directories (`$REPOS_DIR`, `$NVIM_CONFIG_DIR`, user-defined
--- ones) and the three things filetree does with them:
---
---   * `fold(p)`    absolute path -> `$NAME/rest` -- what every action that
---                  hands an ABSOLUTE path to the user (clipboard, inserted
---                  links, notifications) writes instead of `E:/repos/x`, so
---                  the text means the same on a machine where the checkout
---                  sits on another drive.
---   * `expand(s)`  `$NAME/rest` -> absolute path -- what a path typed or
---                  configured by the user goes through first, including a
---                  root that has no real environment variable
---                  (`$NVIM_CONFIG_DIR` is `stdpath("config")`, user-defined
---                  `extra` roots are plain config values).
---   * `remap(p)`   an absolute path recorded on ANOTHER machine -> where it
---                  would live under this machine's roots (see the function).
---
--- Configured by the top-level `env_roots` option (see `FiletreeEnvRoots`);
--- `enable = false` turns every fold off, so an action that used to write an
--- absolute path writes the plain absolute path again. Actions that are
--- explicitly relative (`relative`, `buffer_relative`, `project_relative`,
--- Markdown links relative to the buffer) never come through here, and
--- neither do the ones that need a real path (`uri`, `open_with`, the OS
--- clipboard, shell commands).

local path = require("filetree.util.path")
local platform = require("filetree.util.platform")

local uv = vim.uv or vim.loop

local M = {}

---@type string[]
local DEFAULT_VARS = { "REPOS_DIR" }

---@class FiletreeEnvRootsResolved
---@field enable      boolean
---@field vars        string[]
---@field nvim_config boolean
---@field extra       table<string, string|(fun(): string)>

---@type FiletreeEnvRootsResolved
local _cfg = { enable = true, vars = DEFAULT_VARS, nvim_config = true, extra = {} }

---Apply the `env_roots` config table (already merged over the defaults).
---`vars` is deliberately not given a default list in `config/DEFAULTS.lua`:
---the config merge is index-wise for lists, so a user's `{ "A" }` would
---silently keep a default's second entry.
---@param cfg FiletreeEnvRoots|nil
function M.setup(cfg)
  cfg = type(cfg) == "table" and cfg or {}
  _cfg = {
    enable = cfg.enable ~= false,
    vars = type(cfg.vars) == "table" and cfg.vars or DEFAULT_VARS,
    nvim_config = cfg.nvim_config ~= false,
    extra = type(cfg.extra) == "table" and cfg.extra or {},
  }
end

---Whether actions should write the env-var form of an absolute path.
---@return boolean
function M.enabled()
  return _cfg.enable
end

---@internal
---@param v any  a path, or a function returning one
---@return string|nil
local function resolve_value(v)
  if type(v) == "function" then
    local ok, r = pcall(v)
    v = ok and r or nil
  end
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

---@class FiletreeEnvRootsOpts
---@field names?       string[]  Extra environment variable names to try on top of the configured ones.
---@field nvim_config? boolean   Override `env_roots.nvim_config` for this call.
---@field force?       boolean   Fold even when `env_roots.enable` is false -- for an action the user asked for by name (`:Filetree copy env_rooted`).

---Every root that currently has a value, as `{ name, root }` with `root` an
---absolute, forward-slash path without a trailing slash. Independent of
---`enable`: that switch decides whether callers FOLD, not which roots exist.
---Order: user-defined `extra` roots (sorted by name, so a result never
---depends on table iteration order), then `vars`, then `names`, then
---`$NVIM_CONFIG_DIR`; the first definition of a name wins, so an `extra`
---entry overrides an environment variable of the same name.
---@param opts? FiletreeEnvRootsOpts
---@return { name: string, root: string }[]
function M.roots(opts)
  opts = type(opts) == "table" and opts or {}
  local out, seen = {}, {}

  ---@param name any
  ---@param value any
  local function add(name, value)
    if type(name) ~= "string" or name == "" or seen[name] then return end
    local root = resolve_value(value)
    if not root then return end
    local abs = path.to_unix(root):gsub("/+$", "")
    if abs == "" then return end
    seen[name] = true
    out[#out + 1] = { name = name, root = abs }
  end

  local extra_names = {}
  for name in pairs(_cfg.extra) do
    extra_names[#extra_names + 1] = tostring(name)
  end
  table.sort(extra_names)
  for _, name in ipairs(extra_names) do
    add(name, _cfg.extra[name])
  end
  for _, name in ipairs(_cfg.vars) do
    add(name, vim.env[name])
  end
  for _, name in ipairs(opts.names or {}) do
    add(name, vim.env[name])
  end
  local want_nvim = opts.nvim_config
  if want_nvim == nil then want_nvim = _cfg.nvim_config end
  if want_nvim then add("NVIM_CONFIG_DIR", vim.fn.stdpath("config")) end
  return out
end

---Absolute `p` as `$NAME/rest` when it lives under one of the roots (the
---longest match wins, so a nested root beats the one around it); `p`
---unchanged otherwise. With `enable = false` (and no `opts.force`) always `p`
---unchanged. `p` must
---be absolute -- a relative path is returned as is.
---@param p string
---@param opts? FiletreeEnvRootsOpts
---@return string result
---@return string|nil name  The root that matched, when one did.
function M.fold(p, opts)
  if not (_cfg.enable or (opts and opts.force)) or type(p) ~= "string" or p == "" then
    return p, nil
  end
  local folded, name = path.env_rooted(p, {}, M.roots(opts))
  if not name then return p, nil end
  return folded, name
end

---The name of the root `p` lives under (see `fold`), or nil.
---@param p string
---@param opts? FiletreeEnvRootsOpts
---@return string|nil
function M.root_of(p, opts)
  local _, name = M.fold(p, opts)
  return name
end

---`$NAME/rest` or `${NAME}/rest` -> absolute path, for the roots known here
---(including ones without a real environment variable). Anything else --
---other variables, a path without a leading variable -- comes back untouched,
---for `path.to_absolute` and its generic `$VAR` expansion to deal with.
---Works whatever `enable` says: it only ever acts on text the user wrote.
---@param s string
---@return string
function M.expand(s)
  if type(s) ~= "string" then return s end
  local name, rest = s:match("^%$%{?([%a_][%w_]*)%}?(.*)$")
  if not name or not (rest == "" or rest:match("^[/\\]")) then return s end
  for _, r in ipairs(M.roots()) do
    if r.name == name then return r.root .. rest end
  end
  return s
end

---@internal
---@param s string
---@return string
local function fold_case(s)
  return platform.is_windows() and vim.fn.tolower(s) or s
end

---Candidates for an absolute path that was recorded on ANOTHER machine,
---re-anchored under this machine's roots. The root's own folder name is the
---anchor: a root `D:/repos` is called `repos` on every machine, so the part of
---`E:/repos/casedesk.nvim/x.md` after `repos` is looked for under `D:/repos`
---(likewise `nvim` for `$NVIM_CONFIG_DIR`, whatever drive or home it sits
---on). Only candidates that exist are returned, nearest anchor first, each
---once. Empty when `enable = false`, `p` is not absolute, or nothing matches.
---@param p string
---@return string[]
function M.remap(p)
  if not _cfg.enable or type(p) ~= "string" then return {} end
  local raw = path.slashify(p)
  if not (raw:match("^%a:/") or raw:sub(1, 1) == "/") then return {} end

  local segs = vim.split(raw, "/", { plain = true, trimempty = true })
  local folded_raw = fold_case(raw)
  local hits, seen = {}, {}
  for _, r in ipairs(M.roots()) do
    local leaf = r.root:match("([^/]+)$")
    if leaf then
      local folded_leaf = fold_case(leaf)
      for i = 1, #segs - 1 do
        if fold_case(segs[i]) == folded_leaf then
          local cand = r.root .. "/" .. table.concat(segs, "/", i + 1)
          local key = fold_case(cand)
          if not seen[key] and key ~= folded_raw and uv.fs_stat(cand) then
            seen[key] = true
            hits[#hits + 1] = cand
          end
        end
      end
    end
  end
  return hits
end

return M
