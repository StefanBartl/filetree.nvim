---@module 'filetree.util.platform'
---@brief Cross-platform detection utilities.

local M = {}

---@return boolean
function M.is_windows()
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

---@return boolean
function M.is_wsl()
  local uv = vim.uv or vim.loop
  local version = (uv and uv.os_uname and uv.os_uname().version) or ""
  if version:match("[Mm]icrosoft") then return true end
  return vim.env ~= nil and vim.env.WSL_DISTRO_NAME ~= nil and vim.env.WSL_DISTRO_NAME ~= ""
end

---@return boolean
function M.is_mac()
  return vim.fn.has("macunix") == 1
end

---@return boolean
function M.is_linux()
  return vim.fn.has("unix") == 1 and not M.is_mac() and not M.is_wsl()
end

---@return "windows"|"wsl"|"mac"|"linux"
function M.current()
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
