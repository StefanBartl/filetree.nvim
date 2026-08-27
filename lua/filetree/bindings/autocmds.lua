---@module 'filetree.bindings.autocmds'
--- What filetree.nvim actually registers, by event — read back, not listed.
---
--- This file used to hold a hand-written table of fourteen entries. The real
--- number is forty-six, spread over twenty-three feature modules, so the list
--- was wrong about two thirds of what fires and nothing anywhere said so. A
--- mirror of the code is only as good as the last time somebody remembered to
--- update it, and for "which autocmds does this plugin have" that is exactly
--- the question you cannot afford a stale answer to.
---
--- So it is derived now. Every autocmd goes through `filetree.util.autocmd`,
--- which delegates to `lib.nvim.bindings.autocmd`, which records what it
--- created — event, group, pattern, desc, and the `file:line` it was created
--- from. Clearing a group drops its records with it, so a re-`setup()` does
--- not inflate the list.
---
--- Behavioural autocmds only, as before: the FileType autocmd that binds each
--- feature's tree-buffer keymaps is catalogued in `bindings.keymaps`.
---
--- One wrinkle since the buffer-lifecycle events moved to a dispatcher
--- (`filetree.util.bufevents`): ten features now share ONE autocmd, so the
--- record list has one row where ten things listen. Reading that as "filetree
--- does one thing on BufEnter" would be the same stale-mirror problem in a new
--- shape, so `dispatchers()` reads the handler list back too and `lines()`
--- prints it underneath its autocmd.

local M = {}

---@internal
--- filetree's own records: everything whose group is named `filetree*`, plus
--- the tree-attach dispatcher.
---@return Lib.Autocmd.Record[]
local function own_records()
  local ok, au = pcall(require, "lib.nvim.bindings.autocmd")
  if not ok or type(au.registered) ~= "function" then return {} end
  local out = {}
  for _, r in ipairs(au.registered()) do
    if type(r.group) == "string" and r.group:match("^filetree") then out[#out + 1] = r end
  end
  return out
end

--- Every autocmd filetree currently has registered, in creation order.
---@return Lib.Autocmd.Record[]
function M.list()
  return own_records()
end

--- The same, grouped by event — how the question is usually asked: "what
--- happens on BufWritePost?"
---@return table<string, Lib.Autocmd.Record[]>
function M.by_event()
  local out = {}
  for _, r in ipairs(own_records()) do
    for _, e in ipairs(r.events) do
      out[e] = out[e] or {}
      out[e][#out[e] + 1] = r
    end
  end
  return out
end

--- Every dispatcher filetree owns, with its handler list — read back from
--- `lib.nvim.bindings.autocmd.dispatcher`, same as the records above.
---@return Lib.Autocmd.Dispatcher.Entry[]
function M.dispatchers()
  local ok, dispatcher = pcall(require, "lib.nvim.bindings.autocmd.dispatcher")
  if not ok or type(dispatcher.registry) ~= "function" then return {} end
  local out = {}
  for _, entry in ipairs(dispatcher.registry()) do
    if entry.name:match("^filetree") then out[#out + 1] = entry end
  end
  return out
end

--- One line per autocmd, sorted by event then group, with a dispatcher's
--- handlers indented underneath it. For `:checkhealth` and for a human asking
--- what this plugin does to their editor.
---@return string[]
function M.lines()
  local records = own_records()
  table.sort(records, function(a, b)
    local ae, be = a.events[1] or "", b.events[1] or ""
    if ae ~= be then return ae < be end
    return (a.group or "") < (b.group or "")
  end)

  -- Which record IS the dispatch autocmd, keyed by "group|event,event".
  --
  -- Group alone is not enough: a dispatcher also creates a BufWipeout autocmd
  -- in the same group to clean up its per-buffer `once` bookkeeping, and
  -- hanging the handler list off that one too would claim ten features listen
  -- on BufWipeout. The event list tells them apart.
  local handlers_by_key = {}
  for _, entry in ipairs(M.dispatchers()) do
    if entry.group then
      handlers_by_key[entry.group .. "|" .. table.concat(entry.events, ",")] = entry.handlers
    end
  end

  local out = {}
  for _, r in ipairs(records) do
    out[#out + 1] = ("%-16s %-28s %s"):format(
      table.concat(r.events, ","),
      r.group or "-",
      r.desc or r.src
    )
    local dispatched = handlers_by_key[(r.group or "") .. "|" .. table.concat(r.events, ",")]
    for _, h in ipairs(dispatched or {}) do
      out[#out + 1] = ("%-16s %-28s %s"):format(
        "",
        "  -> " .. table.concat(h.keys, ","),
        h.desc or h.src
      )
    end
  end
  return out
end

return M
