---@module 'filetree.config.schema'
--- Declarative option schemas for the feature-owned config bodies (ERR-50 /
--- ERR-22).
---
--- The engine -- spec forms, messages, typo hints -- is `lib.lua.config.schema`
--- (see its README for the forms). What stays here is filetree's own part:
--- the keys every feature body accepts, and finding the `SCHEMA` a feature
--- exports.
---
--- `config/init.lua`'s `sanitize()` validates top-level keys and feature names.
--- Every feature owns its option shape, so it also owns the description of it:
--- a feature module exports `M.SCHEMA` next to its own defaults, and
--- `check_feature()` below applies it to the body the user supplied, BEFORE the
--- feature's own merge. Keeping the schema in the module (rather than a second
--- key list in `config/`) is what stops it drifting from the code that reads the
--- options -- an earlier central list did drift and rejected `current_hl.icon`.
--- `TESTS/config_schema.lua` fails when a module reads a key its schema does
--- not declare, or when the schema rejects the module's own defaults.
---
--- A feature without a `SCHEMA` is passed through untouched; the test above
--- makes that a failure for every feature in the registry.

local lib_schema = require("lib.lua.config.schema")

local M = {}

---Keys every feature body accepts on top of its own `SCHEMA`.
---`autocmds_enabled` is written by `config/init.lua`'s autocmd override after the
---merge, but a user may reasonably set it by hand too.
---@type table<string, string|table>
local UNIVERSAL = {
  enabled = "boolean",
  autocmds_enabled = "boolean",
}

M.describe_unknown = lib_schema.describe_unknown

---Validate `body` (a user-supplied table) against `fields` plus the keys every
---feature accepts. Does not change `body`. An unknown key and a rejected value
---are dropped and reported, so the module's own default applies.
---@param body table
---@param fields table<string, string|table>
---@param path string  dotted path of `body`, e.g. "features.trash"
---@param issues string[]  appended to
---@return table clean
function M.check(body, fields, path, issues)
  return lib_schema.check_record(body, vim.tbl_extend("keep", fields, UNIVERSAL), path, issues)
end

---The `SCHEMA` a feature exports, or nil when it has none (or does not load).
---@param name string
---@return table<string, string|table>?
function M.for_feature(name)
  local ok, mod = require("filetree.features").load(name)
  if ok and type(mod) == "table" and type(mod.SCHEMA) == "table" then return mod.SCHEMA end
  return nil
end

---Validate the body the user gave for `features.<name>`.
---
---  * not a table  -> rejected (`nil`): a boolean/string/number there would take
---                    the setup loop down at `fcfg.enabled = true`
---  * no SCHEMA    -> returned as is
---  * otherwise    -> `check()`ed against the feature's own SCHEMA
---@param name string
---@param body any
---@param issues string[]  appended to
---@return table? clean  nil when the body is dropped
function M.check_feature(name, body, issues)
  local path = "features." .. name
  if type(body) ~= "table" then
    issues[#issues + 1] = ("option '%s' must be a table, got %s -- using the default"):format(
      path,
      lib_schema.describe_got(body)
    )
    return nil
  end
  local schema = M.for_feature(name)
  if not schema then return body end
  return M.check(body, schema, path, issues)
end

return M
