---@module 'filetree.util.pdf'
---@brief Shared PDF opener: bridges to pdfport.nvim (optional dep) with a
---dependency-free system-viewer fallback.
---@description
--- The single place where filetree talks to pdfport.nvim. Both the `preview`
--- feature (<Tab>/<CR> image/PDF dispatch) and the dedicated `pdf_open` feature
--- route through here, so the pdfport require + call signature live in exactly
--- one spot.
---
--- pdfport.nvim is a SOFT dependency: when it is absent, when a pdfport open
--- fails, or when `mode == "system"`, the file is handed to the OS default
--- viewer instead (no external CLIs beyond the platform handler). filetree never
--- names a pdfport backend or its fallback chain — `mode`/`backend` are passed
--- straight through and pdfport's own setup() decides what actually runs.
---
--- Note: pdfport's Lua module is `pdfport_nvim` (dir `lua/pdfport_nvim/`), and
--- its `open()` takes a *table* (`{ path = …, mode = … }`), not a bare path.

local platform = require("filetree.util.platform")
local notify   = require("filetree.util.notify").create("[filetree.pdf]")

local M = {}

---@param path string?
---@return boolean
function M.is_pdf(path)
  return type(path) == "string" and path ~= "" and path:lower():match("%.pdf$") ~= nil
end

---Open `path` in the OS default PDF viewer. Works with pdfport absent.
---@param path string
---@return boolean ok
function M.system_open(path)
  local args
  if platform.is_windows() then
    args = { "cmd", "/c", "start", "", (path:gsub("/", "\\")) }
  elseif platform.is_mac() then
    args = { "open", path }
  elseif platform.is_wsl() or platform.has_executable("wslview") then
    args = { "wslview", path }
  else
    args = { "xdg-open", path }
  end
  local job = vim.fn.jobstart(args, { detach = true })
  if not job or job <= 0 then
    notify.warn("Could not open in system viewer: " .. path)
    return false
  end
  return true
end

---True when pdfport.nvim is installed and exposes open().
---@return boolean
function M.has_pdfport()
  local ok, pp = pcall(require, "pdfport_nvim")
  return ok and type(pp.open) == "function"
end

---Open a PDF. `mode == "system"` (or pdfport unavailable / failing) uses the OS
---viewer; every other mode is dispatched to pdfport.nvim's core `open{}` API.
---@param path string
---@param opts? { mode?: FiletreePdfOpenMode, backend?: string, split?: string, focus?: boolean }
---@return boolean handled
function M.open(path, opts)
  opts = opts or {}
  if not M.is_pdf(path) then
    notify.warn("Not a PDF: " .. tostring(path))
    return false
  end

  local mode = opts.mode or "buffer"

  -- "system" is intentionally dependency-free: never touch pdfport for it.
  if mode == "system" then
    return M.system_open(path)
  end

  local ok, pp = pcall(require, "pdfport_nvim")
  if ok and type(pp.open) == "function" then
    local ok2, err = pcall(pp.open, {
      path       = path,
      mode       = mode,
      backend_id = opts.backend,
      split      = opts.split,
      focus      = opts.focus,
    })
    if ok2 then return true end
    notify.warn("pdfport open failed (" .. tostring(err) .. ") — falling back to system viewer")
  else
    notify.warn("pdfport.nvim not installed — opening PDF in system viewer")
  end

  return M.system_open(path)
end

return M
