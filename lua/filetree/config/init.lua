---@module 'filetree.config'
--- Configuration management — defaults, merging, validation.
---
--- Plugin-side defaults live in `filetree.config.DEFAULTS`; this module deep-merges
--- the user's `setup({})` config on top and exposes the active config.

local M = {}

-- lib.nvim is a hard dependency here, same regime as the rest of the plugin
-- (commands.lua:19 bare-requires it too, so require("filetree") cannot
-- succeed without it regardless) -- a soft pcall'd fallback would only add
-- one more unreachable path.
local levenshtein = require("lib.lua.strings.distance").levenshtein

---@type FiletreeConfig
local _defaults = require("filetree.config.DEFAULTS")

--- Starts at the defaults rather than an empty table: `get()` is called from
--- feature modules that can run before `setup()` (a test, a lazy-loaded
--- command), and every one of them reads `cfg.features.<name>` as if the
--- plugin's own defaults were in place. `setup()` replaces this wholesale.
---@type FiletreeConfig
local _active = vim.deepcopy(_defaults)

---Deep-merge src into dst (modifies dst in place).
---@internal
---@param dst table
---@param src table
---@return table
local function deep_merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      deep_merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

-- ── Validation (ERR-50 / ERR-22) ─────────────────────────────────────────────
-- Runs BEFORE the merge, not after: a typo'd top-level option or feature name
-- must be caught and reported here, or it silently vanishes into the default
-- forever with nothing downstream ever able to tell the two apart.

---Top-level `FiletreeOpts` fields `setup()` recognizes. `features` is
---special-cased in `sanitize()` below: its own sub-keys are checked against
---the feature registry (`filetree.features`), the single source of truth for
---feature names, rather than a second fixed list kept here.
---@type table<string, boolean>
local KNOWN_TOP = {
  adapter = true,
  debug = true,
  features = true,
  keymaps = true,
  adapter_keymaps = true,
  command = true,
  autocmds = true,
  ignore_list = true,
  menu = true,
  confirmations = true,
  deps_popup = true,
  refs = true,
  progress_style = true,
  max_visible_nodes = true,
}

---What the last `M.setup()` call had to drop, for `:checkhealth`. Reset on
---every call so issues from an earlier setup() never linger.
---@type string[]
local issues = {}

---@internal
---`key` with the nearest known one as a hint when there is a plausible one
---(edit distance <= 3).
---@param key any
---@param known table<string, any>
---@param prefix string
---@return string
local function describe_unknown(key, known, prefix)
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

---Validate `opts` before the merge (ERR-50): an unknown top-level key or
---feature name is dropped with a did-you-mean hint instead of silently
---vanishing into the default forever, and a wrongly-typed `adapter`/`features`
---is dropped so the built-in default applies instead of taking the whole
---plugin down (ERR-22 — see `filetree/init.lua`'s `M.setup`, which is the
---other half of that fix: it never aborts on a validation issue). Does not
---mutate `opts`. Deliberately shallow beyond the `features` name check: each
---feature module owns and validates its own option shape.
---@internal
---@param opts table
---@return table clean
---@return string[] found_issues
local function sanitize(opts)
  local clean, found_issues = {}, {}
  local feature_registry = require("filetree.features").FEATURES

  for key, value in pairs(opts) do
    if not KNOWN_TOP[key] then
      found_issues[#found_issues + 1] = describe_unknown(key, KNOWN_TOP, "")
    elseif key == "adapter" and type(value) ~= "string" then
      found_issues[#found_issues + 1] = ("option 'adapter' must be a string, got %s -- using the default"):format(
        type(value)
      )
    elseif key == "features" then
      if type(value) ~= "table" then
        found_issues[#found_issues + 1] = ("option 'features' must be a table, got %s -- using the default"):format(
          type(value)
        )
      else
        local clean_features = {}
        for fname, fval in pairs(value) do
          if feature_registry[fname] then
            clean_features[fname] = fval
          else
            found_issues[#found_issues + 1] = describe_unknown(fname, feature_registry, "features.")
          end
        end
        clean[key] = clean_features
      end
    else
      clean[key] = value
    end
  end

  table.sort(found_issues)
  return clean, found_issues
end

---Scan all feature keymap fields and apply the global `keymaps` remap table.
---Covers two patterns:
---  1. Fields whose key starts with "keymap"  (e.g. keymap, keymap_open, keymap_scroll_up)
---  2. All string values inside a sub-table whose key is "keymaps"
---     (e.g. copy_move.keymaps.copy, copy_file_list.keymaps.files_abs)
---A remap value of `false` disables the key; a string replaces it.
---@internal
---@param cfg FiletreeConfig
local function apply_keymap_remap(cfg)
  local remap = cfg.keymaps
  if type(remap) ~= "table" then return end

  ---@internal
  local function patch(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do
      if type(v) == "string" then
        if type(k) == "string" and k:match("^keymap") and remap[v] ~= nil then t[k] = remap[v] end
      elseif type(v) == "table" then
        if k == "keymaps" then
          -- patch all string values inside a keymaps sub-table
          for ik, iv in pairs(v) do
            if type(iv) == "string" and remap[iv] ~= nil then v[ik] = remap[iv] end
          end
        else
          patch(v)
        end
      end
    end
  end

  if type(cfg.features) == "table" then
    for _, fcfg in pairs(cfg.features) do
      patch(fcfg)
    end
  end
end

---Propagate top-level `autocmds` disables into per-feature configs.
---`autocmds = { auto_reveal = false }` sets `fcfg.autocmds_enabled = false`.
---@internal
---@param cfg FiletreeConfig
local function apply_autocmd_overrides(cfg)
  local overrides = cfg.autocmds
  if type(overrides) ~= "table" then return end
  if type(cfg.features) ~= "table" then return end
  for name, val in pairs(overrides) do
    local fcfg = cfg.features[name]
    if type(fcfg) == "table" and val == false then fcfg.autocmds_enabled = false end
  end
end

---Map of user-facing action names (what the confirmation is actually about)
---to the feature + config field that action's prompt lives on.
---@type table<string, { feature: string, field: string }>
local CONFIRMATION_ACTIONS = {
  paste = { feature = "copy_move", field = "confirm" },
  delete = { feature = "trash", field = "confirm" },
  rename_batch = { feature = "rename_batch", field = "confirm" },
}

---Translate top-level `confirmations` into the per-feature `confirm` fields
---it controls.
---  true / false → applies to every confirmable action
---  table        → applies per action name, e.g. { paste = false, delete = true }
--- Either way, a feature whose `confirm` the user already set explicitly
--- (via `features.<name>.confirm`) keeps that value -- the top-level switch
--- only fills in fields the user left unset.
---@internal
---@param cfg FiletreeConfig
local function apply_confirmations(cfg)
  local val = cfg.confirmations
  if val == nil then return end
  cfg.features = cfg.features or {}

  ---@internal
  local function set_if_unset(action, value)
    local spec = CONFIRMATION_ACTIONS[action]
    if not spec then return end
    local fcfg = cfg.features[spec.feature]
    if type(fcfg) ~= "table" then
      fcfg = {}
      cfg.features[spec.feature] = fcfg
    end
    if fcfg[spec.field] == nil then fcfg[spec.field] = value end
  end

  if type(val) == "table" then
    for action, value in pairs(val) do
      set_if_unset(action, value)
    end
  else
    for action in pairs(CONFIRMATION_ACTIONS) do
      set_if_unset(action, val)
    end
  end
end

---Translate top-level `ignore_list` into `features.ignore_list`.
---  true / nil → enabled, no override (use built-in / lib.nvim names)
---  false      → disabled
---  string[]   → enabled with those exact names
---@internal
---@param cfg FiletreeConfig
local function apply_ignore_list(cfg)
  local val = cfg.ignore_list
  cfg.features = cfg.features or {}
  local fi = cfg.features.ignore_list or {}
  if val == false then
    fi.enabled = false
  elseif type(val) == "table" then
    fi.enabled = true
    fi.names = val
  else
    -- true or nil → default on, built-in names
    fi.enabled = true
    fi.names = fi.names -- preserve user override if they set features.ignore_list.names directly
  end
  cfg.features.ignore_list = fi
end

---Per-feature reference options that predate the central `refs` block, and the
---`refs` field each one now means. `check_markdown_refs = false` on a feature
---turned that feature's reference handling off; the equivalent is switching
---the corresponding operation to "off".
---@type table<string, { op: string }>
local LEGACY_REFS_FEATURES = {
  smart_rename = { op = "on_rename" },
  rename_batch = { op = "on_rename" },
  copy_move = { op = "on_move" },
  trash = { op = "on_delete" },
}

---Translate the deprecated per-feature reference options into `cfg.refs`.
---
---Only fields the user actually set are migrated (feature defaults live in the
---feature modules, not in DEFAULTS, so anything present here is a user
---choice), and an explicit `cfg.refs` setting always wins — migration fills
---in, it never overrides.
---@internal
---@param cfg FiletreeConfig
local function apply_legacy_refs(cfg)
  if type(cfg.features) ~= "table" then return end
  cfg.refs = cfg.refs or {}
  local user_refs = cfg.refs
  local deprecated = {}

  for name, spec in pairs(LEGACY_REFS_FEATURES) do
    local fcfg = cfg.features[name]
    if type(fcfg) == "table" then
      if fcfg.check_markdown_refs == false then
        deprecated[#deprecated + 1] = name .. ".check_markdown_refs"
        if user_refs[spec.op] == nil then user_refs[spec.op] = "off" end
      end
      if type(fcfg.refs_picker_prefer) == "string" then
        deprecated[#deprecated + 1] = name .. ".refs_picker_prefer"
        if user_refs.picker == nil then user_refs.picker = fcfg.refs_picker_prefer end
      end
    end
  end

  -- smart_rename.update_references gated the textual require()/import rewrite,
  -- which is now what the code providers do.
  local sr = cfg.features.smart_rename
  if type(sr) == "table" and sr.update_references == false then
    deprecated[#deprecated + 1] = "smart_rename.update_references"
    user_refs.providers = user_refs.providers or {}
    for _, provider in ipairs({ "lua", "python", "ts_js" }) do
      if user_refs.providers[provider] == nil then user_refs.providers[provider] = false end
    end
  end

  if #deprecated > 0 then
    require("filetree.util.notify").create("[filetree]").warn(
      "deprecated option(s) migrated to the central `refs` block: "
        .. table.concat(deprecated, ", ")
        .. " — see docs/FEATURES/FILEOPS.md#references"
    )
  end
end

---Apply user config on top of defaults.
---@param user FiletreeOpts?
function M.setup(user)
  local clean, found_issues = sanitize(user or {})
  issues = found_issues

  -- Deep-copy defaults
  _active = vim.deepcopy(_defaults)
  deep_merge(_active, clean)
  apply_keymap_remap(_active)
  apply_autocmd_overrides(_active)
  apply_confirmations(_active)
  apply_ignore_list(_active)
  apply_legacy_refs(_active)
end

---Return the active configuration.
---@return FiletreeConfig
function M.get()
  return _active
end

---What the last `M.setup()` call rejected (unknown option, wrong type),
---one message per issue -- empty when everything validated. For
---`:checkhealth filetree`.
---@return string[]
function M.issues()
  return vim.deepcopy(issues)
end

---Validate the active config and return error messages. A safety net, not
---the primary guard: `sanitize()` above already drops a wrongly-typed
---`adapter`/`features` before the merge, so this should not trigger in
---practice. `filetree/init.lua`'s `M.setup()` treats a `false` here as
---non-fatal either way (ERR-22) -- it degrades the offending field to its
---default instead of aborting setup.
---@return boolean ok
---@return string? err
function M.validate()
  local cfg = _active
  if type(cfg.adapter) ~= "string" then return false, "config.adapter must be a string" end
  if type(cfg.features) ~= "table" then return false, "config.features must be a table" end
  return true, nil
end

return M
