---@module 'filetree.util.notify'
--- Notification factory — scoped notifier with a fixed prefix.
---
--- Delegates to `lib.nvim.notify` (a hard dependency; same `create(prefix)`
--- API), so notifications share the user's lib.nvim configuration.

---@class FiletreeNotifier
---@field info  fun(msg: string): nil
---@field warn  fun(msg: string): nil
---@field error fun(msg: string): nil
---@field debug fun(msg: string): nil

local lib = require("lib.nvim.notify")

local M = {}

---Global debug switch. Off by default; `setup({ debug = true })` flips it on so
---`notifier.debug(...)` becomes visible. See M.set_debug.
local _debug = false

---Enable/disable visible debug notifications globally.
---@param on boolean
function M.set_debug(on)
  _debug = on == true
end

---@internal
---Wrap a base notifier so `debug` only emits (visibly, as INFO) when the global
---debug switch is on — a no-op otherwise. info/warn/error pass straight through.
---@param base FiletreeNotifier
---@return FiletreeNotifier
local function with_debug_gate(base)
  return {
    info = base.info,
    warn = base.warn,
    error = base.error,
    debug = function(msg)
      if _debug then base.info("[debug] " .. msg) end
    end,
  }
end

---Create a scoped notifier with a fixed prefix string.
---@param prefix string  Shown before every message, e.g. "[filetree.adapter.neotree]".
---@return FiletreeNotifier
function M.create(prefix)
  return with_debug_gate(lib.create(prefix))
end

return M
