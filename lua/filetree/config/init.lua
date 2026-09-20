---@module 'filetree.config'
--- Configuration management — defaults, merging, validation.
---
--- Plugin-side defaults live in `filetree.config.DEFAULTS`; this module deep-merges
--- the user's `setup({})` config on top and exposes the active config.

local M = {}

local schema = require("filetree.config.schema")

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

---Sub-key sets for the `features.<name>` bodies that `DEFAULTS.lua` itself
---declares centrally (i.e. every feature listed under `DEFAULTS.features`).
---Checked one level deep, by full dotted path (`features.cwd_sync.debounce_ms`,
---not just `debounce_ms`), so a typo inside one of these does not silently
---vanish into the default the way a top-level-only check would miss it.
---
---Every *other* feature (the ~50 not listed in `DEFAULTS.features`) still
---only gets its NAME checked against the registry, same as before: its body
---shape belongs to that feature module, which this file has no way to know
---without duplicating (and inevitably drifting from) that module's own
---`@types` annotation. Extend this table when a feature's defaults move into
---`DEFAULTS.features` (see that file's header comment on which features are
---"worth surfacing centrally").
---@type table<string, table<string, boolean>>
local KNOWN_FEATURE_BODY = {
  layout_guard = { enabled = true, delay_ms = true },
  no_name_guard = { enabled = true },
  sidebar_guard = { enabled = true, winfixbuf = true },
  cwd_sync = {
    enabled = true,
    debounce_ms = true,
    parent_levels = true,
    keep_focus = true,
    change_dir = true,
    reveal = true,
    use_project_root = true,
    root_markers = true,
  },
  -- cwd_mode deliberately excluded: its own DEFAULTS (cwd_mode/DEFAULTS.lua)
  -- is a large, deeply-nested surface (indicator.labels/icons/hl, …) that the
  -- feature module owns outright -- see that file's header. Only its NAME is
  -- checked here, like the other feature-owned bodies.
  current_hl = { enabled = true, file_hl = true, parent_hl = true, debounce_ms = true },
  safety = { enabled = true, backup_dir = true, max_backups = true, dry_run = true },
}

---Known sub-keys of the top-level `menu` table (see `DEFAULTS.lua`).
---@type table<string, boolean>
local KNOWN_MENU = {
  enable = true,
  fileops = true,
  clipboard = true,
  delete = true,
  open = true,
  paths = true,
  search = true,
  info = true,
  marks = true,
  window = true,
}

local describe_unknown = schema.describe_unknown

---Validate `opts` before the merge (ERR-50): an unknown top-level key or
---feature name is dropped with a did-you-mean hint instead of silently
---vanishing into the default forever, and a wrongly-typed `adapter`/`features`
---is dropped so the built-in default applies instead of taking the whole
---plugin down (ERR-22 — see `filetree/init.lua`'s `M.setup`, which is the
---other half of that fix: it never aborts on a validation issue). Does not
---mutate `opts`. Recurses one level into `menu` and into the handful of
---`features.<name>` bodies `DEFAULTS.lua` declares centrally (see
---KNOWN_FEATURE_BODY above); every other feature's body is validated against
---the `SCHEMA` that feature module exports (see `filetree.config.schema`), and
---passed through untouched when it exports none. A body that is not a table at
---all is dropped for every feature.
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
          if not feature_registry[fname] then
            found_issues[#found_issues + 1] = describe_unknown(fname, feature_registry, "features.")
          elseif type(fval) ~= "table" then
            -- A boolean/string/number body would take the setup loop down at
            -- `fcfg.enabled = true`; drop it so the feature's default applies.
            schema.check_feature(fname, fval, found_issues)
          else
            local body_known = KNOWN_FEATURE_BODY[fname]
            if body_known then
              -- One level deep, by full dotted path -- see KNOWN_FEATURE_BODY's
              -- doc comment for why only these features get this treatment.
              local clean_body = {}
              for bkey, bval in pairs(fval) do
                if body_known[bkey] then
                  clean_body[bkey] = bval
                else
                  found_issues[#found_issues + 1] =
                    describe_unknown(bkey, body_known, "features." .. fname .. ".")
                end
              end
              clean_features[fname] = clean_body
            else
              -- Feature-owned body: validated against the feature's own SCHEMA
              -- (or passed through when it has none).
              clean_features[fname] = schema.check_feature(fname, fval, found_issues)
            end
          end
        end
        clean[key] = clean_features
      end
    elseif key == "menu" then
      if type(value) ~= "table" then
        found_issues[#found_issues + 1] = ("option 'menu' must be a table, got %s -- using the default"):format(
          type(value)
        )
      else
        local clean_menu = {}
        for mkey, mval in pairs(value) do
          if KNOWN_MENU[mkey] then
            clean_menu[mkey] = mval
          else
            found_issues[#found_issues + 1] = describe_unknown(mkey, KNOWN_MENU, "menu.")
          end
        end
        clean[key] = clean_menu
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
---Only fields the user actually set are migrated, and an explicit `refs`
---setting always wins — migration fills in, it never overrides. "Explicit"
---means what the user's own `refs` table says (`explicit`), NOT what is in
---`cfg.refs`: that block is already merged over `refs/DEFAULTS.lua`, so every
---field is non-nil there and testing it would never let a migration through.
---@internal
---@param cfg FiletreeConfig
---@param explicit table?  the user's own `refs` table (after sanitize), if any
local function apply_legacy_refs(cfg, explicit)
  if type(cfg.features) ~= "table" then return end
  cfg.refs = cfg.refs or {}
  local refs = cfg.refs
  explicit = type(explicit) == "table" and explicit or {}
  local deprecated = {}

  for name, spec in pairs(LEGACY_REFS_FEATURES) do
    local fcfg = cfg.features[name]
    if type(fcfg) == "table" then
      if fcfg.check_markdown_refs == false then
        deprecated[#deprecated + 1] = name .. ".check_markdown_refs"
        if explicit[spec.op] == nil then refs[spec.op] = "off" end
      end
      if type(fcfg.refs_picker_prefer) == "string" then
        deprecated[#deprecated + 1] = name .. ".refs_picker_prefer"
        if explicit.picker == nil then refs.picker = fcfg.refs_picker_prefer end
      end
    end
  end

  -- smart_rename.update_references gated the textual require()/import rewrite,
  -- which is now what the code providers do.
  local sr = cfg.features.smart_rename
  if type(sr) == "table" and sr.update_references == false then
    deprecated[#deprecated + 1] = "smart_rename.update_references"
    local explicit_providers = type(explicit.providers) == "table" and explicit.providers or {}
    refs.providers = refs.providers or {}
    for _, provider in ipairs({ "lua", "python", "ts_js" }) do
      if explicit_providers[provider] == nil then refs.providers[provider] = false end
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

-- ── Value normalization (ERR-22) ─────────────────────────────────────────────
-- Runs AFTER the merge, on the active config: `sanitize()` above only rejects
-- keys the *shape* is wrong for (unknown key, non-table where a table is
-- required). It says nothing about a value that has the right shape but is
-- out of range for what its consumer actually does with it -- several of
-- these reach `vim.defer_fn`, a libuv timer, a numeric `for` limit or a bare
-- length comparison downstream, each guarded only by `x or default` at the
-- point of use (catches `nil`, nothing else). A string, boolean or table
-- there throws instead of falling back; degrading it here, once, means every
-- one of those call sites can go on trusting the value it reads.

---Degrade `tbl[field]` to `default` (recording why in `issues`) unless it is
---a number `>= min`. A `nil` field is left alone -- that is the merge having
---produced exactly the default, not a user-supplied bad value, so there is
---nothing to report.
---@internal
---@param tbl table
---@param field string
---@param label string  dotted path for the message, e.g. "features.cwd_sync.debounce_ms"
---@param default number
---@param min number
---@param out_issues string[]
local function degrade_number(tbl, field, label, default, min, out_issues)
  local v = tbl[field]
  if v == nil then return end
  if type(v) ~= "number" or v < min or v ~= v then -- v ~= v: reject NaN
    out_issues[#out_issues + 1] = ("option '%s' must be a number >= %d, got %s -- using the default"):format(
      label,
      min,
      type(v) == "number" and tostring(v) or type(v)
    )
    tbl[field] = default
  end
end

---Degrade `cfg` fields whose consumer only guards against `nil`, one field at
---a time, by dotted path. See the section comment above for why this lives
---here rather than in each consumer.
---@internal
---@param cfg FiletreeConfig
---@param out_issues string[]
local function normalize_values(cfg, out_issues)
  local feat = cfg.features
  if type(feat) == "table" then
    if type(feat.layout_guard) == "table" then
      degrade_number(
        feat.layout_guard,
        "delay_ms",
        "features.layout_guard.delay_ms",
        50,
        0,
        out_issues
      )
    end
    if type(feat.cwd_sync) == "table" then
      degrade_number(
        feat.cwd_sync,
        "debounce_ms",
        "features.cwd_sync.debounce_ms",
        150,
        0,
        out_issues
      )
      degrade_number(
        feat.cwd_sync,
        "parent_levels",
        "features.cwd_sync.parent_levels",
        0,
        0,
        out_issues
      )
    end
    if type(feat.current_hl) == "table" then
      degrade_number(
        feat.current_hl,
        "debounce_ms",
        "features.current_hl.debounce_ms",
        100,
        0,
        out_issues
      )
    end
    if type(feat.safety) == "table" then
      degrade_number(feat.safety, "max_backups", "features.safety.max_backups", 5, 0, out_issues)

      -- backup_dir: nil (documented default -- stdpath("data")/filetree/backups)
      -- or a non-empty string. A table crashes vim.fn.fnamemodify() outright
      -- (E730); a number/boolean silently resolves to a nonsense path under
      -- the cwd; an empty string resolves to the cwd itself -- backups of
      -- deleted/moved files landing inside whatever project happens to be
      -- open, silently, instead of the intended backup directory.
      local bd = feat.safety.backup_dir
      if bd ~= nil and (type(bd) ~= "string" or bd == "") then
        out_issues[#out_issues + 1] = ("option 'features.safety.backup_dir' must be a non-empty string or nil, got %s -- using the default"):format(
          type(bd) == "string" and "empty string" or type(bd)
        )
        feat.safety.backup_dir = nil
      end
    end
  end

  local refs = cfg.refs
  if type(refs) == "table" and type(refs.scan) == "table" then
    degrade_number(refs.scan, "max_files", "refs.scan.max_files", 5000, 1, out_issues)
    degrade_number(refs.scan, "timeout_ms", "refs.scan.timeout_ms", 3000, 1, out_issues)
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
  normalize_values(_active, issues)
  table.sort(issues)
  apply_keymap_remap(_active)
  apply_autocmd_overrides(_active)
  apply_confirmations(_active)
  apply_ignore_list(_active)
  apply_legacy_refs(_active, clean.refs)
end

---Return the active configuration.
---@return FiletreeConfig
function M.get()
  return _active
end

---What the last `M.setup()` call rejected or degraded (unknown option, wrong
---type, an out-of-range value normalize_values() fell back on), one message
---per issue -- empty when everything validated. For `:checkhealth filetree`.
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
