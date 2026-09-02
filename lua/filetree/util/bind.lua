---@module 'filetree.util.bind'
---@brief Declare a feature's keymaps through lib.nvim's keymap registry.
---@description
--- Every feature here binds the same way: read one or more `keymap*` fields
--- out of its own config, and set them on each tree buffer as it attaches (or
--- globally, for the handful that are not tree-local). That block was written
--- out once per feature -- 36 times, in four or five slightly different
--- shapes, with the `desc` prefix spelled two different ways -- and this is
--- that block, once.
---
--- What it adds over the old `map(...)` calls:
---
---  * a config value may now be a **list** of keys, not only one;
---  * `desc` reads the same everywhere, because the registry writes it;
---  * every action is **recorded**, whether or not it ended up bound, so the
---    cheatsheet and `:checkhealth` can read what exists instead of a
---    hand-maintained catalog beside it that drifts.
---
--- What it deliberately does not add: the registry's typo reporting. That
--- works off a table of action names, and filetree's keys live in named
--- config fields next to `enabled`, `debounce_ms` and the rest -- there is no
--- set of keys here that "should all be action names".

local tree_attach = require("filetree.util.tree_attach")
local keymap = require("lib.nvim.bindings.keymap")

-- `vim.validate(name, value, validator)` is the 0.11 signature. Before that only
-- the table form exists, and from 0.11 on that form is deprecated -- so neither
-- spelling is correct across the range the README promises. Pick per version.
-- Runtime facts do not change mid-session, so this is read once.
local has_flat_validate = vim.fn.has("nvim-0.11") == 1

---@param name string   # Argument name, for the error message.
---@param value any
---@param typ string     # Expected `type()`.
local function validate(name, value, typ)
  if has_flat_validate then
    vim.validate(name, value, typ)
  else
    ---@diagnostic disable-next-line: deprecated, param-type-mismatch
    vim.validate({ [name] = { value, typ } })
  end
end

---@class FiletreeBindSpec
---@field name string          # Action name, e.g. "copy_absolute".
---@field field string         # Config field holding the lhs, e.g. "keymap_abs".
---@field default? string      # Plugin default lhs, when the config may not carry one.
---@field rhs? string|function # Omitted when `binds` carries the per-mode variants instead.
---@field desc string          # Without a prefix; the registry adds "filetree: ".
---@field mode? string|string[] # Default "n".
---@field opts? table          # Extra keymap options (expr, nowait, ...).
---@field cfg? table           # Read `field` out of this table instead of the feature's config.
---@field binds? table[]       # Per-mode variants of one action; see marks' `toggle`.

local M = {}

---@internal
--- The user's effective lhs for one spec, normalized for the registry.
---
--- `""` means "unset" in several of these config tables -- it predates
--- `false` being accepted -- and both have to arrive as `false`, or the
--- registry falls back to the declared default and binds the very key the
--- config just switched off.
---@param cfg table
---@param spec FiletreeBindSpec
---@return string|string[]|false|nil
local function lhs_of(cfg, spec)
  -- `spec.cfg` for the keys that do not live in a `keymap_*` field of the
  -- feature config: open_with keeps one per configured application, inside
  -- that application's own entry.
  local v = (spec.cfg or cfg)[spec.field]
  if v == nil then return nil end
  if v == false or v == "" then return false end
  return v
end

---@internal
---The registry spec for a list of bind specs, plus the user's overrides.
---@param specs FiletreeBindSpec[]
---@param cfg table
---@return table spec, table<string, string|string[]|false> user
local function build(specs, cfg)
  ---@type table<string, Lib.Keymap.Action>
  local actions = {}
  ---@type string[]
  local order = {}
  ---@type table<string, string|string[]|false>
  local user = {}

  for _, spec in ipairs(specs) do
    -- `binds` is one action that does related things in two modes -- marks'
    -- `toggle` marks the node under the cursor in normal mode and every node
    -- the selection spans in visual mode. That is one key and one override to
    -- a user, so it stays one action here.
    local decl_binds = nil
    if spec.binds then
      decl_binds = {}
      for i, b in ipairs(spec.binds) do
        decl_binds[i] = {
          mode = b.mode,
          rhs = b.rhs,
          desc = b.desc,
          opts = vim.tbl_extend("force", { silent = true }, b.opts or {}),
        }
      end
    end

    actions[spec.name] = {
      default = spec.default,
      mode = spec.mode,
      rhs = spec.rhs,
      desc = spec.desc,
      binds = decl_binds,
      opts = vim.tbl_extend("force", { silent = true }, spec.opts or {}),
    }
    order[#order + 1] = spec.name
    user[spec.name] = lhs_of(cfg, spec)
  end

  return { order = order, actions = actions }, user
end

---Declare and bind one feature's keymaps.
---
---`scope` decides when: "tree" binds buffer-locally as each tree buffer
---attaches (the common case), "global" binds once, now.
---@param feature string  # Registry surface: the feature's own name.
---@param cfg table       # The feature's resolved config.
---@param specs FiletreeBindSpec[]
---@param scope? "tree"|"global"  # Default "tree".
---@return Lib.Keymap.Registered[]|nil
function M.bind(feature, cfg, specs, scope)
  validate("feature", feature, "string")
  validate("cfg", cfg, "table")
  validate("specs", specs, "table")

  local spec_table, user = build(specs, cfg)

  if scope == "global" then
    return keymap.register("filetree", spec_table, user, { surface = feature })
  end

  -- The dispatcher fires for every tree buffer, and neo-tree renders five
  -- different sources through one `neo-tree` filetype -- so a feature that only
  -- makes sense over a filesystem node has to say so, or it binds its keys in
  -- a symbol outline too. `filetree.sources` is the same list `attach.lua`
  -- reads for the `?` cheatsheet, so a key cannot be bound somewhere it is not
  -- listed, or the other way round.
  tree_attach.on_attach(function(buf)
    keymap.register("filetree", spec_table, user, { buffer = buf, surface = feature })
  end, feature)
end

---Declare and bind for ONE buffer, now.
---
---For the keys whose behavior depends on the buffer they are bound in:
---preview's `<CR>` wraps whatever the adapter had mapped there, which can
---only be read off that buffer.
---@param feature string
---@param cfg table
---@param specs FiletreeBindSpec[]
---@param buf integer
---@return Lib.Keymap.Registered[]
function M.bind_buffer(feature, cfg, specs, buf)
  validate("feature", feature, "string")
  validate("cfg", cfg, "table")
  validate("specs", specs, "table")
  validate("buf", buf, "number")

  local spec_table, user = build(specs, cfg)
  return keymap.register("filetree", spec_table, user, { buffer = buf, surface = feature })
end

return M
