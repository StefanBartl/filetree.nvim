---@module 'filetree.util.env_roots'
--- Named root directories (`$REPOS_DIR`, `$NVIM_CONFIG_DIR`, user-defined
--- ones) as filetree uses them -- a thin layer over lib.nvim's named-roots
--- registry (`lib.nvim.fs.roots`, see its README), which does the actual work:
---
---   * `fold(p)`    absolute path -> `$NAME/rest` -- what inserted links,
---                  notifications and the `env_rooted` copy write instead of
---                  `E:/repos/x`, so the text means the same on a machine
---                  where the checkout sits on another drive. A path copied
---                  as absolute (`[a`) is not folded: that is the real one.
---   * `expand(s)`  `$NAME/rest` -> absolute path -- what a path typed or
---                  configured by the user goes through first, including a
---                  root that has no real environment variable
---                  (`$NVIM_CONFIG_DIR` is `stdpath("config")`, user-defined
---                  `extra` roots are plain config values).
---   * `remap(p)`   an absolute path recorded on ANOTHER machine -> where it
---                  would live under this machine's roots.
---
--- What this layer adds is filetree's own `env_roots` option: it is never
--- handed to the registry's `setup()` (that one belongs to the user's config
--- and replaces it globally) but goes into every call -- `vars` as `opts.vars`
--- (replacing the registry's list, as it always replaced filetree's default),
--- `extra` as `opts.extra`, `nvim_config` as `opts.nvim_config`. The roots of
--- the user's registry config and of other plugins stay visible: a path under
--- a deeper root registered elsewhere folds to that one.
---
--- `enable` stays filetree's own switch: off, nothing is folded or remapped
--- (whatever the registry's `enable` says); on, every call passes
--- `force = true`. Actions that are explicitly relative (`relative`,
--- `buffer_relative`, `project_relative`, Markdown links relative to the
--- buffer) never come through here, and neither do the ones that need a real
--- path (`uri`, `open_with`, the OS clipboard, shell commands).

local roots = require("lib.nvim.fs.roots")
local is_subpath = require("lib.nvim.fs.is_subpath")
local platform = require("filetree.util.platform")

local M = {}

---filetree's own default `vars` (the registry's default too); see `own_root_of`.
---@type string[]
local DEFAULT_VARS = { "REPOS_DIR" }

---@class FiletreeEnvRootsResolved
---@field enable      boolean
---@field vars?       string[]  nil = the registry's own `vars` (default { "REPOS_DIR" })
---@field nvim_config boolean
---@field extra       table<string, string|(fun(): string)>

---@type FiletreeEnvRootsResolved
local _cfg = { enable = true, vars = nil, nvim_config = true, extra = {} }

---Apply the `env_roots` config table (already merged over the defaults and
---type-checked by `filetree.config`). `vars` is deliberately not given a
---default list in `config/DEFAULTS.lua`: the config merge is index-wise for
---lists, so a user's `{ "A" }` would silently keep a default's second entry.
---@param cfg FiletreeEnvRoots|nil
function M.setup(cfg)
  cfg = type(cfg) == "table" and cfg or {}
  _cfg = {
    enable = cfg.enable ~= false,
    vars = type(cfg.vars) == "table" and vim.deepcopy(cfg.vars) or nil,
    nvim_config = cfg.nvim_config ~= false,
    extra = type(cfg.extra) == "table" and vim.deepcopy(cfg.extra) or {},
  }
end

---Whether actions should write the env-var form of an absolute path.
---@return boolean
function M.enabled()
  return _cfg.enable
end

---@class FiletreeEnvRootsOpts
---@field names?       string[]  Extra environment variable names to try on top of the configured ones.
---@field nvim_config? boolean   Override `env_roots.nvim_config` for this call.
---@field force?       boolean   Fold even when `env_roots.enable` is false -- for an action the user asked for by name (`:Filetree copy env_rooted`).

---The registry options of one call: filetree's own `env_roots` config plus the
---caller's `names` / `nvim_config` (never `force`, see `fold_opts`).
---@param opts? FiletreeEnvRootsOpts
---@return Lib.Fs.Roots.Opts
local function roots_opts(opts)
  opts = type(opts) == "table" and opts or {}
  local nvim_config = _cfg.nvim_config
  if type(opts.nvim_config) == "boolean" then nvim_config = opts.nvim_config end
  return {
    vars = _cfg.vars,
    extra = _cfg.extra,
    names = type(opts.names) == "table" and opts.names or nil,
    nvim_config = nvim_config,
  }
end

---`roots_opts` plus `force = true`, or nil when filetree's own switch is off
---and the caller did not ask by name.
---@param opts? FiletreeEnvRootsOpts
---@return Lib.Fs.Roots.FoldOpts|nil
local function fold_opts(opts)
  local forced = type(opts) == "table" and opts.force == true
  if not (_cfg.enable or forced) then return nil end
  local o = roots_opts(opts) --[[@as Lib.Fs.Roots.FoldOpts]]
  o.force = true
  return o
end

---Every root that currently has a value, as `{ name, root }` with `root` an
---absolute, forward-slash path without a trailing slash (uppercase drive
---letter). Independent of `enable`: that switch decides whether callers FOLD,
---not which roots exist. Order and precedence are the registry's (`roots()`
---of `lib.nvim.fs.roots`): the user's `extra`, filetree's `extra`, registered
---roots, `vars`, `names`, `$NVIM_CONFIG_DIR`; the first usable definition of a
---name wins.
---@param opts? FiletreeEnvRootsOpts
---@return { name: string, root: string }[]
function M.roots(opts)
  return roots.roots(roots_opts(opts))
end

---A function that folds absolute paths into `$NAME/rest` (see `fold`) with
---the roots resolved ONCE -- for a caller folding many paths (a recursive file
---list). Anything that is not absolute comes back unchanged.
---@param opts? FiletreeEnvRootsOpts
---@return fun(p: string): string, string|nil
function M.folder(opts)
  local o = fold_opts(opts)
  if not o then return function(p)
    return p, nil
  end end
  return roots.folder(o)
end

---Absolute `p` as `$NAME/rest` when it lives under one of the roots (the
---deepest match wins, so a nested root beats the one around it); `p`
---unchanged otherwise. With `enable = false` (and no `opts.force`) always `p`
---unchanged. `p` must be absolute -- a relative path is returned as is.
---@param p string
---@param opts? FiletreeEnvRootsOpts
---@return string result
---@return string|nil name  The root that matched, when one did.
function M.fold(p, opts)
  return M.folder(opts)(p)
end

---The name of the root `p` lives under (see `fold`), or nil.
---@param p string
---@param opts? FiletreeEnvRootsOpts
---@return string|nil
function M.root_of(p, opts)
  local o = fold_opts(opts)
  if not o then return nil end
  return roots.root_of(p, o)
end

---The deepest of filetree's OWN roots `p` lives under: `env_roots.vars`
---(`{ "REPOS_DIR" }` when unset), `env_roots.extra` and `$NVIM_CONFIG_DIR`
---(unless `nvim_config = false`) -- the roots of the user's registry config
---and the ones other plugins registered do not count here, unlike `root_of`.
---For a decision that must not depend on what somebody else registered: two
---paths under one `$REPOS_DIR` stay "under the same root" when another plugin
---registers a folder inside it. The comparison is lexical (no symlinks
---resolved), case-insensitive on Windows. nil when `enable = false`.
---@param p string  Absolute path.
---@return string|nil
function M.own_root_of(p)
  if not _cfg.enable or type(p) ~= "string" or p == "" then return nil end
  local win = platform.is_windows()
  ---@param n any
  ---@return string|nil
  local function key(n)
    if type(n) ~= "string" then return nil end
    return win and n:upper() or n
  end
  local own = {} ---@type table<string, boolean>
  for _, n in ipairs(_cfg.vars or DEFAULT_VARS) do
    local k = key(n)
    if k then own[k] = true end
  end
  for n in pairs(_cfg.extra) do
    local k = key(n)
    if k then own[k] = true end
  end
  if _cfg.nvim_config then own.NVIM_CONFIG_DIR = true end
  local best, best_len = nil, -1
  for _, r in ipairs(M.roots()) do
    if
      own[key(r.name)]
      and #r.root > best_len
      and is_subpath(p, r.root, { realpath = false, ignore_case = win })
    then
      best, best_len = r.name, #r.root
    end
  end
  return best
end

---A leading `$NAME`, `${NAME}` or `%NAME%` reference, split off -- the same
---spelling rules as the registry's `expand`: the name must be followed by the
---end of the string or a separator (a backslash only on Windows).
---@param s string
---@return string|nil name
---@return string|nil rest
---@return "$"|"${}"|"%%"|nil form  How the reference was written.
local function parse_ref(s)
  local form = "${}"
  local name, rest = s:match("^%$%{([%a_][%w_]*)%}(.*)$")
  if not name then
    form = "$"
    name, rest = s:match("^%$([%a_][%w_]*)(.*)$")
  end
  if not name then
    form = "%%"
    name, rest = s:match("^%%([%a_][%w_]*)%%(.*)$")
  end
  if not name then return nil, nil, nil end
  local win = platform.is_windows()
  if rest ~= "" and not rest:match(win and "^[/\\]" or "^/") then return nil, nil, nil end
  return name, rest, form
end

---`folded` -- a `fold` result `$NAME/rest` whose root is `name` -- written the
---way the leading reference of `original` was: `${NAME}/rest` or
---`%NAME%/rest` when `original` used that form, and with the name spelled as
---in `original` when that names the same root (it may differ in case on
---Windows). For text that is rewritten in place (a moved link target): the
---user's spelling may be meant for a shell or another tool and is kept.
---Anything that does not fit comes back as `folded`.
---@param folded string
---@param name string
---@param original string
---@return string
function M.respell(folded, name, original)
  if type(folded) ~= "string" or type(name) ~= "string" or type(original) ~= "string" then
    return folded
  end
  local head = "$" .. name
  if folded:sub(1, #head) ~= head then return folded end
  local rest = folded:sub(#head + 1)
  local written, _, form = parse_ref(original)
  if not written then return folded end
  local win = platform.is_windows()
  if (win and written:upper() or written) == (win and name:upper() or name) then name = written end
  if form == "${}" then return "${" .. name .. "}" .. rest end
  if form == "%%" then return "%" .. name .. "%" .. rest end
  return "$" .. name .. rest
end

---The root a leading `$NAME` / `${NAME}` / `%NAME%` reference of `s` names,
---among the roots of one registry call (the registry's own `match` knows only
---the globally configured roots, not a plugin's per-call ones). Names compare
---case-insensitively on Windows, like the variables themselves.
---@param s string
---@param opts? Lib.Fs.Roots.Opts  Passed to the registry's `roots()` as is.
---@return string|nil name  The root's name as configured.
---@return string|nil root  Its absolute path.
---@return string|nil rest  The rest of `s` after the reference (`""` or starting with a separator).
function M.match(s, opts)
  if type(s) ~= "string" then return nil, nil, nil end
  local ref, rest = parse_ref(s)
  if not ref then return nil, nil, nil end
  local win = platform.is_windows()
  local want = win and ref:upper() or ref
  for _, r in ipairs(roots.roots(opts)) do
    if (win and r.name:upper() or r.name) == want then return r.name, r.root, rest end
  end
  return nil, nil, nil
end

---`$NAME/rest`, `${NAME}/rest` or `%NAME%/rest` -> absolute path, for the
---roots known here (including ones without a real environment variable, and
---filetree's own `extra`); `~/rest` too. Anything else -- other variables, a
---reference in the middle, a name followed by something that is not a
---separator -- comes back untouched, for `path.to_absolute` to deal with. On
---Windows the rest's backslashes become slashes. Works whatever `enable` says:
---it only ever acts on text the user wrote.
---@param s string
---@return string
function M.expand(s)
  if type(s) ~= "string" then return s end
  local _, root, rest = M.match(s, roots_opts())
  if not root then return roots.expand(s) end
  rest = rest or ""
  if platform.is_windows() then rest = rest:gsub("\\", "/") end
  return root .. rest
end

---Candidates for an absolute path that was recorded on ANOTHER machine,
---re-anchored under this machine's roots (the registry's `remap`): the root's
---own folder name is the anchor, so the part of `E:/repos/casedesk.nvim/x.md`
---after `repos` is looked for under this machine's `$REPOS_DIR`. Only
---candidates that exist are returned, the outermost anchor first, each once.
---Empty when `enable = false`, `p` is not absolute, or nothing matches.
---@param p string
---@return string[]
function M.remap(p)
  local o = fold_opts()
  if not o or type(p) ~= "string" then return {} end
  return roots.remap(p, o)
end

---Each name filetree's own `env_roots` config asks for (`vars`, `extra`) that
---is no root here, with the likely reason -- for `:checkhealth filetree`.
---@return { name: string, kind: "var"|"extra", reason: string }[]
function M.unresolved()
  local win = platform.is_windows()
  local have = {}
  for _, r in ipairs(M.roots()) do
    have[win and r.name:upper() or r.name] = true
  end
  local out = {}
  ---@param name any
  ---@param kind "var"|"extra"
  local function check(name, kind)
    if type(name) ~= "string" or have[win and name:upper() or name] then return end
    local reason
    if not name:match("^[%a_][%w_]*$") then
      reason = "not a valid name (letters, digits and underscores only)"
    elseif kind == "var" and (vim.env[name] or "") == "" then
      reason = "the environment variable is not set"
    else
      reason = "no usable value (relative, a whole drive, or a `$VAR` without a value)"
    end
    out[#out + 1] = { name = name, kind = kind, reason = reason }
  end
  for _, name in ipairs(_cfg.vars or {}) do
    check(name, "var")
  end
  local extra_names = {}
  for name in pairs(_cfg.extra) do
    if type(name) == "string" then extra_names[#extra_names + 1] = name end
  end
  table.sort(extra_names)
  for _, name in ipairs(extra_names) do
    check(name, "extra")
  end
  return out
end

return M
