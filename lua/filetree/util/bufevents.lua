---@module 'filetree.util.bufevents'
--- Central buffer-lifecycle dispatcher: one autocmd set, many feature handlers.
---
--- Ten features used to register their own `BufEnter` (often plus `WinEnter`,
--- `BufWritePost` or `TextChanged`) autocmd, each in its own augroup. Three
--- problems came with that, and only the third is about speed:
---
--- 1. **Order was arbitrary.** Native autocmds fire in registration order, and
---    features are set up by iterating a table with `pairs()` — so which of
---    `cwd_sync` (chdirs), `auto_reveal` (reveals) and the renderers went
---    first was not decided anywhere, and could differ between runs. Here it
---    is a number: see `PRIORITY`.
--- 2. **"What happens when I switch buffers?" had no single answer.** It was
---    ten files. Now it is one registry, and the generated
---    `bindings/autocmd/*.md` prints the handler list under the dispatcher.
--- 3. **`is_tree_buffer()` ran once per feature.** Four of the handlers open
---    with it, and it is not free — a `require("filetree")`, an adapter call
---    and a filetype comparison. The dispatch key computes it once per event
---    and hands the answer to everyone.
---
--- ### Keys
---
--- `"<event>:<scope>"`, scope being `tree` or `editor`:
---
---   bufevents.register("size_info", "BufEnter:tree", { … })
---   bufevents.register("marks", { "BufEnter:*", "BufWritePost:*" }, { … })
---
--- `*` is a glob, so `"BufEnter:*"` is "either scope". A handler that needs to
--- tell the two apart anyway gets `ctx.key`.
---
--- ### Lifecycle
---
--- Mirrors `filetree.util.tree_attach`, and is driven by `filetree.setup()`:
---
---   1. features call `register(owner, keys, spec)` in their own `setup()`
---   2. features call `unregister(owner)` in their own `teardown()`
---   3. `install()` at the end of `filetree.setup()` creates the autocmds
---
--- Step 2 is not optional. `filetree.setup()` is idempotent by tearing every
--- feature down and setting it up again; without the unregister, a re-setup
--- would leave the previous cycle's handler in place and run each one twice
--- per event. A plain autocmd got this for free from `augroup(clear = true)`.
---
--- ### The cost, which was weighed and dismissed
---
--- A native autocmd whose `pattern` does not match is filtered in C and never
--- enters Lua (~1 µs); this one always enters Lua (~30 µs). `TextChanged` is
--- in the set despite that, and it is the event where the difference is most
--- visible: `ignore_list` had it pattern-filtered to `neo-tree://*`.
---
--- The arithmetic is why. 30 µs is a number you would have to reach a hundred
--- times to lose three milliseconds, and there is no editing behaviour that
--- gets there — you would have to hold a key down, and even then it is under
--- one percent of a second. The dispatcher's README works this through with
--- measurements and lands on the same conclusion: choose the module for
--- deterministic ordering and one registry, and do not choose against it for
--- a number nobody perceives.

local bufutil = require("filetree.util.buffer")
local dispatcher = require("lib.nvim.bindings.autocmd.dispatcher")

local M = {}

--- Events the dispatcher covers.
---
--- Every event any feature in this set listens to, so that no feature has to
--- split itself across the dispatcher and a plain autocmd. See the module
--- header for what the shared dispatch costs and why that did not decide it.
---@type string[]
local EVENTS = { "BufEnter", "WinEnter", "BufWritePost", "TextChanged" }

--- Handler order, lowest first.
---
--- A judgement, not a measurement: the working directory should be settled
--- before anything reveals a path in the tree, and the tree should be revealed
--- before anything renders decorations onto it. Everything in `RENDER` is
--- independent of everything else there, and ties fall back to registration
--- order.
M.PRIORITY = {
  CWD = 10,
  REVEAL = 20,
  RENDER = 30,
}

---@type Lib.Autocmd.Dispatcher.Handle|nil
local _handle = nil

---@internal
---@return Lib.Autocmd.Dispatcher.Handle
local function handle()
  if not _handle then
    _handle = dispatcher.new({
      event = EVENTS,
      name = "filetree_bufevents",
      group = "filetree_bufevents",
      desc = "[filetree] Dispatch buffer-lifecycle events to the feature handlers",
      key = function(ev)
        return ("%s:%s"):format(ev.event, bufutil.is_tree_buffer(ev.buf) and "tree" or "editor")
      end,
    })
  end
  return _handle
end

---Register one feature's handler.
---
---`owner` is the feature name, and it is what `unregister` takes back out —
---the feature's `teardown()` must pass the same string.
---@param owner string
---@param keys string|string[]  # `"<event>:<scope>"`, scope `tree`/`editor`/`*`
---@param spec { load: fun(ctx: Lib.Autocmd.Dispatcher.Ctx), desc: string, priority?: integer, once?: boolean }
---@return nil
function M.register(owner, keys, spec)
  handle().register(keys, {
    load = spec.load,
    desc = spec.desc,
    priority = spec.priority or M.PRIORITY.RENDER,
    once = spec.once,
    owner = owner,
  })
end

---Drop every handler `owner` registered. Safe to call for an owner that never
---registered anything.
---@param owner string
---@return integer removed
function M.unregister(owner)
  if not _handle then return 0 end
  return _handle.unregister(owner)
end

---Create the underlying autocmds. Idempotent; called from `filetree.setup()`
---once every feature has registered.
---@return nil
function M.install()
  handle().attach()
end

---Every handler currently registered, in dispatch order. For `:checkhealth`
---and for answering "what runs on BufEnter" without opening nine files.
---@return Lib.Autocmd.Dispatcher.HandlerInfo[]
function M.handlers()
  if not _handle then return {} end
  return _handle.handlers()
end

return M
