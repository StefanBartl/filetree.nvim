---@module 'filetree.util.notify'
---@brief Notification factory — thin wrapper around vim.notify with scoped prefix.

---@class FiletreeNotifier
---@field info  fun(msg: string): nil
---@field warn  fun(msg: string): nil
---@field error fun(msg: string): nil
---@field debug fun(msg: string): nil

local M = {}

---Create a scoped notifier with a fixed prefix string.
---@param prefix string  Shown before every message, e.g. "[filetree.adapter.neotree]".
---@return FiletreeNotifier
function M.create(prefix)
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

return M
