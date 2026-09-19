---@module 'filetree.util.platform'
--- Cross-platform detection utilities.
---
--- Base OS detectors (`is_windows`/`is_wsl`/`is_mac`/`is_linux`) delegate to
--- `lib.nvim.cross.platform.*` (a hard dependency — see `filetree/commands.lua`,
--- required unconditionally from `filetree/init.lua`, so there is no reduced
--- mode without it to fall back to). `has_executable()`/`get_cwd()` have no
--- lib.nvim equivalent and stay local; `current()` delegates to
--- `lib.nvim.cross.platform.is()`, its unified selector.

local cross_is_windows = require("lib.nvim.cross.platform.is_windows")
local cross_is_wsl = require("lib.nvim.cross.platform.is_wsl")
local cross_is_macos = require("lib.nvim.cross.platform.is_macos")
local cross_is_linux = require("lib.nvim.cross.platform.is_linux")
local cross_is = require("lib.nvim.cross.platform.is")

local M = {}

---@return boolean
function M.is_windows()
  return cross_is_windows()
end

---@return boolean
function M.is_wsl()
  return cross_is_wsl()
end

---@return boolean
function M.is_mac()
  return cross_is_macos()
end

---@return boolean
function M.is_linux()
  return cross_is_linux()
end

---@return "windows"|"wsl"|"mac"|"linux"
function M.current()
  -- lib.nvim.cross.platform.is() always resolves to one of these four
  -- (falling back to "linux" itself when nothing else matched), so there is
  -- no fifth case to compose locally.
  local platform = cross_is() ---@type "windows"|"wsl"|"macos"|"linux"
  if platform == "macos" then return "mac" end
  return platform
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
