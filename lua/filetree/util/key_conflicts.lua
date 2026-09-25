---@module 'filetree.util.key_conflicts'
---@brief Keys that two filetree actions both claim: find them, recommend free
---alternatives, move one of them.
---@description
--- Two features binding the same lhs on the same buffer is not an error in Vim:
--- the second `:map` silently wins, and which one is second depends on
--- attach order. So the loser is simply unreachable, and nothing says so.
---
--- This reads the same registry the cheatsheet reads (`lib.nvim` keymap
--- registry, fed by `util.bind`) and answers three questions:
---
---   * `find(buf)`     which lhs are claimed by more than one action, and which
---                     claim is the live one (read off the buffer's actual map)
---   * `suggest(...)`  free keys to move a claim to, best first
---   * `apply(...)` /  move it: on every open tree buffer now, for later ones
---     `resolve(buf)`  through `bind.override`, and print the `setup()` fragment
---                     that makes it permanent. `resolve` is the interactive
---                     version: pick the conflict, the claim, the alternative.
---
--- A move lasts for the session. Whatever the user does in `setup()` is theirs
--- to write; the fragment is copied to the clipboard for that.

local bind = require("filetree.util.bind")
local notify = require("filetree.util.notify").create("[filetree.keys]")

local M = {}

---@class FiletreeKeyClaim
---@field feature string
---@field action  string
---@field desc    string                 # As registered ("filetree: ..."); also the live map's desc.
---@field rhs     string|function|nil
---@field mode    string|string[]
---@field lhs     string
---@field global  boolean                # Bound everywhere, not on the tree buffer.

---@class FiletreeKeyConflict
---@field mode    string                 # First mode of the claims, "n" in practice.
---@field lhs     string
---@field claims  FiletreeKeyClaim[]
---@field active  FiletreeKeyClaim|nil   # The claim the buffer's live map belongs to.
---@field buf     integer|nil            # The tree buffer that map was found on: what to ask for free keys.

-- ── Reading the registry ─────────────────────────────────────────────────────

---@class FiletreeKeyEntry
---@field key   string                   # Registry surface, "filetree/<feature>[/global]".
---@field entry Lib.Keymap.Registered

---filetree's registry entries that apply to tree buffer `buf`: the ones bound in
---it, and the global ones.
---
---The registry keeps the last registration per surface, so with several tree
---buffers open it can hold another buffer's records; when nothing at all is
---recorded for `buf` the filter is dropped rather than answering with an empty
---list. Ordered by surface so the winner among two features claiming the same
---key does not depend on `pairs` order.
---@param buf integer
---@return FiletreeKeyEntry[]
function M.entries(buf)
  local all = require("lib.nvim.bindings.keymap").registered()
  local surfaces = {}
  for key in pairs(all) do
    if key:match("^filetree/") then surfaces[#surfaces + 1] = key end
  end
  table.sort(surfaces)

  ---@type FiletreeKeyEntry[]
  local list = {}
  local scoped = false
  for _, key in ipairs(surfaces) do
    for _, e in ipairs(all[key]) do
      list[#list + 1] = { key = key, entry = e }
      if e.buffer == buf then scoped = true end
    end
  end
  if not scoped then return list end

  local out = {}
  for _, item in ipairs(list) do
    local b = item.entry.buffer
    if b == nil or b == buf then out[#out + 1] = item end
  end
  return out
end

---@internal
---A stable string for an entry's mode (a string, or a list for a multi-mode action).
---@param mode string|string[]
---@return string
local function mode_id(mode)
  return type(mode) == "table" and table.concat(mode, ",") or tostring(mode)
end

---@internal
---The single-letter mode a lookup should use.
---@param mode string|string[]
---@return string
local function first_mode(mode)
  return type(mode) == "table" and mode[1] or tostring(mode)
end

---@internal
---The raw form of a key written in notation (`<C-c>`, `<leader>x`).
---@param lhs string
---@return string
local function raw(lhs)
  return vim.api.nvim_replace_termcodes(lhs, true, true, true)
end

---A key in one canonical raw form, whichever way it was spelled.
---
---`nvim_buf_get_keymap` reports `<C-c>` as `<80><fc>\4C` (a modifier-tagged
---key) while `nvim_replace_termcodes` turns the same notation into `\3`, so a
---plain comparison of the two silently misses every key Vim tags that way.
---Going through `keytrans` and back lands both on the same bytes.
---@param key string  # Notation or raw.
---@return string
function M.canon(key)
  return raw(vim.fn.keytrans(raw(key)))
end

---@internal
---The canonical form of a live map's lhs, from `nvim_buf_get_keymap`.
---@param m table
---@return string
local function canon_live(m)
  return raw(vim.fn.keytrans(m.lhsraw or m.lhs))
end

M.canon_live = canon_live

---@internal
---Which claim of `conflict` the live keymap belongs to, looked up on the buffers
---that are open (the current one first). The registry's `desc` is what the
---binder put on the map, so it identifies the owner exactly.
---@param conflict FiletreeKeyConflict
---@param buf integer
---@return FiletreeKeyClaim|nil claim, integer|nil found_in
local function live_owner(conflict, buf)
  local want = M.canon(conflict.lhs)
  local bufs = { buf }
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= buf and vim.api.nvim_buf_is_loaded(b) then bufs[#bufs + 1] = b end
  end
  for _, b in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(b) then
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(b, conflict.mode)) do
        if canon_live(m) == want then
          for _, claim in ipairs(conflict.claims) do
            if m.desc == claim.desc then return claim, b end
          end
        end
      end
    end
  end
  return nil, nil
end

---Every key claimed by more than one action, in key order.
---@param buf integer  # A tree buffer (the current one is the usual answer).
---@return FiletreeKeyConflict[]
function M.find(buf)
  ---@type table<string, FiletreeKeyConflict>
  local by = {}
  ---@type string[]
  local order = {}
  ---@type table<string, boolean>
  local seen = {}

  for _, item in ipairs(M.entries(buf)) do
    local e = item.entry
    local feature = item.key:match("^filetree/([^/]+)")
    if feature and e.bound and e.lhs then
      local id = mode_id(e.mode) .. " " .. e.lhs
      local claim_id = id .. " " .. feature .. ":" .. e.name
      if not seen[claim_id] then
        seen[claim_id] = true
        if not by[id] then
          by[id] = { mode = first_mode(e.mode), lhs = e.lhs, claims = {} }
          order[#order + 1] = id
        end
        table.insert(by[id].claims, {
          feature = feature,
          action = e.name,
          desc = e.desc or e.name,
          rhs = e.rhs,
          mode = e.mode,
          lhs = e.lhs,
          global = item.key:match("/global$") ~= nil,
        })
      end
    end
  end

  table.sort(order)
  local out = {}
  for _, id in ipairs(order) do
    local c = by[id]
    if #c.claims > 1 then
      c.active, c.buf = live_owner(c, buf)
      out[#out + 1] = c
    end
  end
  return out
end

-- ── Recommending alternatives ────────────────────────────────────────────────

local LOWER = "abcdefghijklmnopqrstuvwxyz"
local UPPER = LOWER:upper()

---@internal
---Candidate keys for a claim, family of the original first: a `<C-x>` stays a
---ctrl key, a `<leader>xy` stays under the leader, a `gx` stays a g-key. The
---g-family and the leader are the fallbacks for everything else.
---@param lhs string
---@return string[]
local function pool(lhs)
  local out = {}
  local function add(k)
    out[#out + 1] = k
  end
  if lhs:match("^<[Cc]%-.>$") then
    for c in LOWER:gmatch(".") do
      add("<C-" .. c .. ">")
    end
  elseif lhs:match("^<[Mm]%-.>$") then
    for c in LOWER:gmatch(".") do
      add("<M-" .. c .. ">")
    end
  end
  for c in (LOWER .. UPPER):gmatch(".") do
    add("g" .. c)
  end
  for a in LOWER:gmatch(".") do
    for b in LOWER:gmatch(".") do
      add("<leader>" .. a .. b)
    end
  end
  return out
end

---@internal
---How much each letter says about a claim: the first word of what it does
---("clear" in "clear clipboard") counts most, its feature's initial next, any
---other word's initial least. `<leader>po` for "open PDF" in pdf_open: p and o.
---@param claim FiletreeKeyClaim
---@return table<string, integer>
local function letter_weights(claim)
  local weights = {}
  local function bump(letter, by)
    letter = letter:lower()
    if (weights[letter] or 0) < by then weights[letter] = by end
  end
  local first = true
  for word in (claim.desc:gsub("^filetree: ", "")):gmatch("%a+") do
    bump(word:sub(1, 1), first and 4 or 1)
    first = false
  end
  bump(claim.feature:sub(1, 1), 2)
  return weights
end

---@internal
---The letters a candidate is spelled with (`<C-r>` -> r, `<leader>po` -> p, o).
---@param cand string
---@return string[]
local function letters_of(cand)
  local body = cand:gsub("^<leader>", ""):gsub("^<[CcMm]%-(.)>$", "%1")
  local out = {}
  for c in body:gmatch("%a") do
    out[#out + 1] = c
  end
  return out
end

---@internal
---Every lhs already taken on `buf`: its live maps, the registry's claims, and
---the global maps -- raw, so `<C-r>` and its spelling in a map agree.
---@param buf integer
---@param mode string
---@return string[]
local function taken(buf, mode)
  local set, list = {}, {}
  local function add(l)
    if l and l ~= "" and not set[l] then
      set[l] = true
      list[#list + 1] = l
    end
  end
  if vim.api.nvim_buf_is_valid(buf) then
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      add(canon_live(m))
    end
  end
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    add(canon_live(m))
  end
  for _, item in ipairs(M.entries(buf)) do
    if item.entry.bound and item.entry.lhs then add(M.canon(item.entry.lhs)) end
  end
  return list
end

---Free keys to move `claim` to, best first.
---
---Free means: not mapped on the buffer or globally, not claimed in the registry,
---and not a prefix of -- or prefixed by -- something that is (`o` would make
---neo-tree's `oc` wait for a second key, `oc` would be swallowed by an `o`).
---Ranked by family (the original's own kind of key first), then by how many of
---its letters are initials of what the action does.
---@param buf integer
---@param claim FiletreeKeyClaim
---@param limit? integer  # Default 8.
---@return string[]
function M.suggest(buf, claim, limit)
  limit = limit or 8
  local used = taken(buf, first_mode(claim.mode))
  local want = letter_weights(claim)
  local family_c = claim.lhs:match("^<[Cc]%-.>$") ~= nil
  local family_m = claim.lhs:match("^<[Mm]%-.>$") ~= nil
  local family_l = claim.lhs:match("^<leader>") ~= nil

  ---@type { key: string, score: integer }[]
  local ranked = {}
  for _, cand in ipairs(pool(claim.lhs)) do
    local r = M.canon(cand)
    local ok = true
    for _, u in ipairs(used) do
      if u == r or u:sub(1, #r) == r or r:sub(1, #u) == u then
        ok = false
        break
      end
    end
    if ok then
      local score = 0
      if (family_c and cand:match("^<C%-")) or (family_m and cand:match("^<M%-")) then
        score = score + 4
      end
      if family_l and cand:match("^<leader>") then score = score + 4 end
      if cand:match("^g") and claim.lhs:match("^g") then score = score + 4 end
      for _, c in ipairs(letters_of(cand)) do
        score = score + (want[c:lower()] or 0)
      end
      ranked[#ranked + 1] = { key = cand, score = score }
    end
  end
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if #a.key ~= #b.key then return #a.key < #b.key end
    return a.key < b.key
  end)

  local out = {}
  for i = 1, math.min(limit, #ranked) do
    out[i] = ranked[i].key
  end
  return out
end

-- ── Moving a claim ───────────────────────────────────────────────────────────

---The config path of an action's key, from its feature's schema
---("keymaps.clear", "keymap_open"), or nil when the schema does not declare it.
---@param feature string
---@param field string
---@return string|nil
function M.config_path(feature, field)
  local function walk(schema, prefix)
    for k, v in pairs(schema) do
      if type(k) == "string" then
        if k == field and (v == "keymap" or (type(v) == "table" and v[1] == "keymap")) then
          return prefix .. k
        end
        if type(v) == "table" and type(v.fields) == "table" then
          local found = walk(v.fields, prefix .. k .. ".")
          if found then return found end
        end
      end
    end
    return nil
  end
  local ok, schema = pcall(require, "filetree.config.schema")
  local fields = ok and schema.for_feature(feature) or nil
  return fields and walk(fields, "") or nil
end

---The `setup()` fragment that makes a moved key permanent.
---@param claim FiletreeKeyClaim
---@param key string
---@return string
function M.snippet(claim, key)
  local field = bind.field_of(claim.feature, claim.action) or claim.action
  local path = vim.split(M.config_path(claim.feature, field) or field, ".", { plain = true })
  local inner = string.format("%s = %q", path[#path], key)
  for i = #path - 1, 1, -1 do
    inner = string.format("%s = { %s }", path[i], inner)
  end
  return string.format(
    'require("filetree").setup({ features = { %s = { %s } } })',
    claim.feature,
    inner
  )
end

---Whether `key` is mapped nowhere the buffer can see it: not on the buffer, not
---globally, not claimed by another action. Exact matches only -- a key that merely
---shares a prefix with one is allowed here (`suggest` steers clear of those, but a
---key typed in by hand is the user's call).
---@param buf integer
---@param mode string
---@param key string
---@return boolean
function M.is_free(buf, mode, key)
  local want = M.canon(key)
  for _, used in ipairs(taken(buf, mode)) do
    if used == want then return false end
  end
  return true
end

---Move `moved` off the key of `conflict` and onto `key`.
---
---Every open buffer whose live map at that key is one of the claims' gets the
---claimants' features rebound: the mover at its new key, the rest back at the old
---one (deleting the map takes the winner's binding with it). Later tree buffers
---bind the new key through `bind.override`.
---
---Refused, before anything is touched, when `key` is already in use, or when a
---claimant is bound per buffer (`preview`: its handlers close over one buffer, so
---it cannot be rebound on another) -- set those keys in `setup()`.
---@param conflict FiletreeKeyConflict
---@param moved FiletreeKeyClaim
---@param key string
---@param buf? integer  # The tree buffer to check `key` against (default: where the conflict was found).
---@return boolean ok, string|nil err
function M.apply(conflict, moved, key, buf)
  if type(key) ~= "string" or key == "" then return false, "no key given" end
  if key == conflict.lhs then return false, "that is the key it already has" end

  local features = { [moved.feature] = true }
  for _, c in ipairs(conflict.claims) do
    features[c.feature] = true
  end
  for feature in pairs(features) do
    if not bind.can_rebind(feature) then
      return false,
        ("%s is bound per buffer and cannot be moved while the session runs; set its key in setup()"):format(
          feature
        )
    end
  end

  buf = buf or conflict.buf or vim.api.nvim_get_current_buf()
  if not M.is_free(buf, conflict.mode, key) then
    return false, ("%s is already in use"):format(key)
  end
  if not bind.override(moved.feature, moved.action, key) then
    return false, ("unknown action %s.%s"):format(moved.feature, moved.action)
  end

  local mode = conflict.mode
  local want = M.canon(conflict.lhs)
  local touched = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      local owned = false
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(b, mode)) do
        if canon_live(m) == want then
          for _, c in ipairs(conflict.claims) do
            if m.desc == c.desc then owned = true end
          end
        end
      end
      if owned then
        pcall(vim.keymap.del, mode, conflict.lhs, { buffer = b })
        for feature in pairs(features) do
          bind.rebind(feature, b)
        end
        touched = touched + 1
      end
    end
  end
  return true, touched == 0 and "no open tree buffer had it; it applies to the next one" or nil
end

---@internal
---One line for a claim in a chooser.
---@param claim FiletreeKeyClaim
---@param active FiletreeKeyClaim|nil
---@return string
local function label(claim, active)
  local mark = (active and active.feature == claim.feature and active.action == claim.action)
      and "  (active)"
    or ""
  -- A per-buffer feature cannot be moved at runtime (see `apply`); say so up front.
  if not bind.can_rebind(claim.feature) then mark = mark .. "  (set in setup())" end
  return ("%s: %s%s"):format(claim.feature, (claim.desc:gsub("^filetree: ", "")), mark)
end

M.label = label

---Interactive: choose a conflict, the action to move, and where to.
---@param buf? integer  # Default: the current buffer.
function M.resolve(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local select = require("filetree.util.select")
  local conflicts = M.find(buf)
  if #conflicts == 0 then
    notify.info("No key is claimed twice.")
    return
  end

  local function pick_alternative(conflict, moved)
    local options = M.suggest(conflict.buf or buf, moved, 8)
    options[#options + 1] = "other key..."
    select(options, {
      prompt = ("Move %s to:"):format(label(moved, nil)),
    }, function(choice)
      if not choice then return end
      local function finish(key)
        local ok, err = M.apply(conflict, moved, key)
        if not ok then
          notify.warn(err or "could not move the key")
          return
        end
        local snippet = M.snippet(moved, key)
        pcall(vim.fn.setreg, "+", snippet)
        notify.info(
          ("%s moved to %s for this session%s\nTo keep it, put this in your config (copied):\n%s"):format(
            label(moved, nil),
            key,
            err and (" (" .. err .. ")") or "",
            snippet
          )
        )
      end
      if choice ~= "other key..." then
        finish(choice)
        return
      end
      require("ui.kit").input({
        title = "New key > ",
        on_submit = function(text)
          if text and text ~= "" then finish(text) end
        end,
      })
    end)
  end

  local function pick_claim(conflict)
    select(conflict.claims, {
      prompt = ("%s is claimed by several actions -- move which?"):format(conflict.lhs),
      format_item = function(claim)
        return label(claim, conflict.active)
      end,
    }, function(claim)
      if claim then pick_alternative(conflict, claim) end
    end)
  end

  if #conflicts == 1 then
    pick_claim(conflicts[1])
    return
  end
  select(conflicts, {
    prompt = "Keys claimed by more than one action:",
    format_item = function(c)
      local names = {}
      for _, claim in ipairs(c.claims) do
        names[#names + 1] = claim.feature
      end
      return ("%s  <-  %s"):format(c.lhs, table.concat(names, ", "))
    end,
  }, function(conflict)
    if conflict then pick_claim(conflict) end
  end)
end

return M
