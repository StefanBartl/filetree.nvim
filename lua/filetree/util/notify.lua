---@module 'filetree.util.notify'
---@brief Notification factory — scoped notifier with a fixed prefix.
---@description
--- Delegates to `lib.nvim.notify` (a declared dependency; same `create(prefix)`
--- API) when available, so notifications share the user's lib.nvim configuration.
--- Falls back to a local vim.notify wrapper so filetree still works standalone.

---@class FiletreeNotifier
---@field info  fun(msg: string): nil
---@field warn  fun(msg: string): nil
---@field error fun(msg: string): nil
---@field debug fun(msg: string): nil

local M = {}

---Global debug switch. Off by default; `setup({ debug = true })` flips it on so
---`notifier.debug(...)` becomes visible. See M.set_debug.
local _debug = false

---Enable/disable visible debug notifications globally.
---@param on boolean
function M.set_debug(on)
  _debug = on == true
end

---Local fallback notifier (used when lib.nvim is not installed).
---@param prefix string
---@return FiletreeNotifier
local function local_notifier(prefix)
  local function emit(level, msg)
    vim.notify(prefix .. " " .. msg, level)
  end
  return {
    info  = function(msg) emit(vim.log.levels.INFO,  msg) end,
    warn  = function(msg) emit(vim.log.levels.WARN,  msg) end,
    error = function(msg) emit(vim.log.levels.ERROR, msg) end,
    debug = function(msg) emit(vim.log.levels.DEBUG, msg) end,
  }
end

---Wrap a base notifier so `debug` only emits (visibly, as INFO) when the global
---debug switch is on — a no-op otherwise. info/warn/error pass straight through.
---@param base FiletreeNotifier
---@return FiletreeNotifier
local function with_debug_gate(base)
  return {
    info  = base.info,
    warn  = base.warn,
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
  local ok, lib = pcall(require, "lib.nvim.notify")
  if ok and type(lib) == "table" and type(lib.create) == "function" then
    local n = lib.create(prefix)
    if type(n) == "table" and type(n.info) == "function" then
      return with_debug_gate(n)
    end
  end
  return with_debug_gate(local_notifier(prefix))
end

return M
