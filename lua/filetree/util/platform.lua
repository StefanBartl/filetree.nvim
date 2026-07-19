---@module 'filetree.util.platform'
---@brief Cross-platform detection utilities.
---@description
--- Base OS detectors (`is_windows`/`is_wsl`/`is_mac`/`is_linux`) delegate to
--- `lib.nvim.cross.platform.*` when available, matching this repo's existing
--- soft-dependency pattern (see `util/notify.lua`, `util/map.lua`). Falls
--- back to the native `vim.fn.has`/`uv.os_uname` checks when lib.nvim is
--- missing. `has_executable()`/`get_cwd()` have no lib.nvim equivalent and
--- stay local; `current()` delegates to `lib.nvim.cross.platform.is()` (its
--- unified selector) when available, falling back to composing the booleans
--- above otherwise.

local M = {}

---@param name string
---@return function|nil
local function try_lib(name)
  local ok, fn = pcall(require, "lib.nvim.cross.platform." .. name)
  if ok and type(fn) == "function" then
    return fn
  end
  return nil
end

---@return boolean
function M.is_windows()
  local lib_fn = try_lib("is_windows")
  if lib_fn then
    return lib_fn()
  end
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

---@return boolean
function M.is_wsl()
  local lib_fn = try_lib("is_wsl")
  if lib_fn then
    return lib_fn()
  end
  local uv = vim.uv or vim.loop
  local version = (uv and uv.os_uname and uv.os_uname().version) or ""
  if version:match("[Mm]icrosoft") then return true end
  return vim.env ~= nil and vim.env.WSL_DISTRO_NAME ~= nil and vim.env.WSL_DISTRO_NAME ~= ""
end

---@return boolean
function M.is_mac()
  local lib_fn = try_lib("is_macos")
  if lib_fn then
    return lib_fn()
  end
  return vim.fn.has("macunix") == 1
end

---@return boolean
function M.is_linux()
  local lib_fn = try_lib("is_linux")
  if lib_fn then
    return lib_fn()
  end
  return vim.fn.has("unix") == 1 and not M.is_mac() and not M.is_wsl()
end

---@return "windows"|"wsl"|"mac"|"linux"
function M.current()
  local lib_is = try_lib("is")
  if lib_is then
    local platform = lib_is() ---@type string
    if platform == "macos" then return "mac" end
    if platform == "windows" or platform == "wsl" or platform == "linux" then
      return platform
    end
  end

  if M.is_windows() then return "windows" end
  if M.is_wsl()     then return "wsl"     end
  if M.is_mac()     then return "mac"     end
  return "linux"
end

---Return true when `name` is found in PATH.
---@param name string
---@return boolean
function M.has_executable(name)
  return vim.fn.executable(name) == 1
end

---Return the current working directory (never nil).
---@return string
function M.get_cwd()
  local uv = vim.uv or vim.loop
  return (uv and uv.cwd and uv.cwd()) or vim.fn.getcwd()
end

return M
