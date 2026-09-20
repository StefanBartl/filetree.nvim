---@module 'filetree.config.schema'
--- Declarative option schemas for the feature-owned config bodies (ERR-50 /
--- ERR-22).
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
---
--- Spec forms (the values of a `SCHEMA` table):
---   "boolean" | "number" | "string" | "table" | "function"
---                       one Lua type; `|` unites several, and the token
---                       `false` matches the literal `false`:
---                       "string|false" = a string, or `false` to switch off
---   "keymap"            a key, a list of keys, or `false` (unmapped) -- what
---                       `util.bind` hands to lib.nvim's keymap registry
---   { "number", min = 0, max = 10 }
---                       inclusive bounds; NaN and +-inf never pass
---   { "string", enum = { "a", "b" } }
---                       closed value set (applies to string values only)
---   { "table", fields = { key = spec, ... } }
---                       closed record: unknown keys are reported
---   { "table", of = spec }
---                       array or open map whose every value matches `spec`

local levenshtein = require("lib.lua.strings.distance").levenshtein

local M = {}

---Keys every feature body accepts on top of its own `SCHEMA`.
---`autocmds_enabled` is written by `config/init.lua`'s autocmd override after the
---merge, but a user may reasonably set it by hand too.
---@type table<string, FiletreeOptSpec>
local UNIVERSAL = {
  enabled = "boolean",
  autocmds_enabled = "boolean",
}

---@alias FiletreeOptSpec string|FiletreeOptSpecTable

---@class FiletreeOptSpecTable
---@field [1]     string                              Type union, see the header.
---@field min?    number                              Numbers: inclusive lower bound.
---@field max?    number                              Numbers: inclusive upper bound.
---@field enum?   string[]                            Strings: allowed values.
---@field fields? table<string, FiletreeOptSpec>      Tables: closed record.
---@field of?     FiletreeOptSpec                     Tables: spec for every value.

---@alias FiletreeSchema table<string, FiletreeOptSpec>

---`key` with the nearest known one as a hint when there is a plausible one
---(edit distance <= 3).
---@param key any
---@param known table<string, any>
---@param prefix string  dotted path of the table `key` sits in, with a trailing dot (or "")
---@return string
function M.describe_unknown(key, known, prefix)
  local name = tostring(key)
  local best, best_distance = nil, nil
  for candidate in pairs(known) do
    local d = levenshtein(name, candidate)
    if d <= 3 and (best_distance == nil or d < best_distance) then
      best, best_distance = candidate, d
    end
  end
  if best then
    return ("unknown option '%s%s' (did you mean '%s%s'?)"):format(prefix, name, prefix, best)
  end
  return ("unknown option '%s%s'"):format(prefix, name)
end

---@class FiletreeParsedSpec
---@field types   table<string, boolean>  accepted `type()` names
---@field is_false boolean                the literal `false` is accepted
---@field label   string                  human-readable, for messages

---@type table<string, FiletreeParsedSpec>
local parsed_cache = {}

---Parse the type union of a spec (cached per union string).
---@param union string
---@return FiletreeParsedSpec
local function parse_union(union)
  local hit = parsed_cache[union]
  if hit then return hit end
  local types, is_false, labels = {}, false, {}
  for token in union:gmatch("[^|]+") do
    if token == "false" then
      is_false = true
      labels[#labels + 1] = "false"
    else
      types[token] = true
      labels[#labels + 1] = token == "table" and "a table" or ("a " .. token)
    end
  end
  hit = { types = types, is_false = is_false, label = table.concat(labels, " or ") }
  parsed_cache[union] = hit
  return hit
end

---@param value any
---@return string
local function describe_got(value)
  local t = type(value)
  if t == "number" or t == "boolean" then return tostring(value) end
  if t == "string" then return ("%q"):format(value) end
  return t
end

---Validate one value against one spec. Returns the value to keep, or nil when
---it was rejected (an issue is appended) so the module's own default applies.
---@param value any
---@param spec FiletreeOptSpec
---@param path string
---@param issues string[]
---@return any
local function check_value(value, spec, path, issues)
  local t = type(spec) == "table" and spec or { spec }
  local vt = type(value)

  -- `util.bind` passes every keymap field to lib.nvim's keymap registry, which
  -- takes a key, a list of keys, or `false`. A plain "string|false" union would
  -- refuse the list form that already works.
  if t[1] == "keymap" then
    if value == false or vt == "string" then return value end
    if vt == "table" and (vim.islist or vim.tbl_islist)(value) then
      for i, lhs in ipairs(value) do
        if type(lhs) ~= "string" then
          issues[#issues + 1] = ("option '%s.%d' must be a string, got %s -- using the default"):format(
            path,
            i,
            describe_got(lhs)
          )
          return nil
        end
      end
      return vim.list_slice(value)
    end
    issues[#issues + 1] = ("option '%s' must be a string, a list of strings or false, got %s -- using the default"):format(
      path,
      describe_got(value)
    )
    return nil
  end

  local p = parse_union(t[1])

  local matches = p.types[vt] or (value == false and p.is_false)
  if not matches then
    issues[#issues + 1] = ("option '%s' must be %s, got %s -- using the default"):format(
      path,
      p.label,
      describe_got(value)
    )
    return nil
  end

  if vt == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      issues[#issues + 1] = ("option '%s' must be a finite number, got %s -- using the default"):format(
        path,
        tostring(value)
      )
      return nil
    end
    if (t.min and value < t.min) or (t.max and value > t.max) then
      local bound = t.min and t.max and ("between %s and %s"):format(t.min, t.max)
        or t.min and (">= " .. t.min)
        or ("<= " .. t.max)
      issues[#issues + 1] = ("option '%s' must be a number %s, got %s -- using the default"):format(
        path,
        bound,
        tostring(value)
      )
      return nil
    end
    return value
  end

  if vt == "string" and t.enum then
    for _, allowed in ipairs(t.enum) do
      if value == allowed then return value end
    end
    local quoted = {}
    for _, allowed in ipairs(t.enum) do
      quoted[#quoted + 1] = ("%q"):format(allowed)
    end
    issues[#issues + 1] = ("option '%s' must be one of %s, got %s -- using the default"):format(
      path,
      table.concat(quoted, ", "),
      describe_got(value)
    )
    return nil
  end

  if vt == "table" then
    if t.fields then
      local clean = M.check(value, t.fields, path, issues)
      return clean
    end
    if t.of then
      -- A rejected element degrades the whole table: dropping one entry out of
      -- an array would leave a hole (or shift the rest), which is worse than
      -- falling back to the default list.
      local out = {}
      for k, v in pairs(value) do
        local kept = check_value(v, t.of, path .. "." .. tostring(k), issues)
        if kept == nil then return nil end
        out[k] = kept
      end
      return out
    end
  end

  return value
end

---Validate `body` (a user-supplied table) against `fields`, one key at a time.
---Does not mutate `body`. An unknown key and a rejected value are dropped and
---reported, so the module's own default applies -- never a silent merge of a
---value nothing reads, and never a crash from a value nothing expected.
---@param body table
---@param fields FiletreeSchema
---@param path string  dotted path of `body`, e.g. "features.trash"
---@param issues string[]  appended to
---@return table clean
function M.check(body, fields, path, issues)
  local clean = {}
  for key, value in pairs(body) do
    local spec = fields[key] or UNIVERSAL[key]
    if spec == nil then
      local known = vim.tbl_extend("force", UNIVERSAL, fields)
      issues[#issues + 1] = M.describe_unknown(key, known, path .. ".")
    else
      local kept = check_value(value, spec, path .. "." .. tostring(key), issues)
      -- `false` is a real value ("string|false"); only a rejected one is nil.
      if kept ~= nil then clean[key] = kept end
    end
  end
  return clean
end

---The `SCHEMA` a feature exports, or nil when it has none (or does not load).
---@param name string
---@return FiletreeSchema?
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
      describe_got(body)
    )
    return nil
  end
  local schema = M.for_feature(name)
  if not schema then return body end
  return M.check(body, schema, path, issues)
end

return M
