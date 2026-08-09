---@module 'filetree.util.pdf'
--- Shared PDF opener: bridges to pdfport.nvim (optional dep) with a
--- dependency-free system-viewer fallback.
---
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
--- Note: pdfport's Lua module is `pdfport` (dir `lua/pdfport/`), and
--- its `open()` takes a *table* (`{ path = …, mode = … }`), not a bare path.

local platform = require("filetree.util.platform")
local notify   = require("filetree.util.notify").create("[filetree.pdf]")

local M = {}

---True when `path` has a `.pdf` extension (case-insensitive).
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
    -- explorer.exe hands the target straight to the registered file handler
    -- with no cmd.exe re-tokenizing in between; `cmd /c start` silently
    -- truncates a path containing an unescaped `&` (cmd.exe treats a bare
    -- `&` outside quotes as a command separator).
    args = { "explorer.exe", (path:gsub("/", "\\")) }
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
  local ok, pp = pcall(require, "pdfport")
  return ok and type(pp.open) == "function"
end

---True when pdfport.nvim is installed and exposes create().
---@return boolean
function M.has_pdfport_create()
  local ok, pp = pcall(require, "pdfport")
  return ok and type(pp.create) == "function" and type(pp.can_create) == "function"
end

---@internal Mirrors pdfport's own extension -> input-kind guess
---(pdfport.core.composer's EXT_KIND) closely enough for a pre-check: used
---only to decide which paths are worth handing to pdfport at all, never to
---second-guess what pdfport itself resolves once a path is actually sent.
---@type table<string, string>
local EXT_KIND = {
  png = "image", jpg = "image", jpeg = "image", gif = "image", bmp = "image",
  webp = "image", tiff = "image", tif = "image",
  md = "markdown", markdown = "markdown",
  html = "html", htm = "html",
  txt = "text",
  docx = "office", odt = "office", xlsx = "office", pptx = "office",
}

---Guess pdfport's input kind for `path` from its extension, or nil when
---unknown (directories, extensionless files, or a kind pdfport has no
---concept of).
---@param path string
---@return string?
function M.guess_kind(path)
  local ext = type(path) == "string" and path:match("%.([%w]+)$")
  return ext and EXT_KIND[ext:lower()] or nil
end

---True when `path`'s guessed kind has an available pdfport producer right now.
---@param path string
---@return boolean
function M.can_create(path)
  if not M.has_pdfport_create() then return false end
  local kind = M.guess_kind(path)
  if not kind then return false end
  local ok, pp = pcall(require, "pdfport")
  return ok and pp.can_create(kind) == true
end

---Create one PDF per input path via pdfport.nvim's create() API (soft
---dependency). Runs sequentially — pdfport.create() is async per call, each
---result callback advances to the next path — so a huge folder does not
---spawn dozens of producer processes at once.
---@param paths string[]
---@param opts? { on_conflict?: "overwrite"|"suffix"|"error", on_done?: fun(results: FiletreePdfCreateResult[]) }
---@return nil
function M.create(paths, opts)
  opts = opts or {}
  local on_done = opts.on_done or function() end

  if not M.has_pdfport_create() then
    notify.warn("pdfport.nvim not installed — cannot create PDFs")
    on_done({})
    return
  end

  local pp = require("pdfport")
  ---@type FiletreePdfCreateResult[]
  local results = {}

  local i = 0
  local function step()
    i = i + 1
    local path = paths[i]
    if not path then
      on_done(results)
      return
    end

    local kind = M.guess_kind(path)
    if not kind or not pp.can_create(kind) then
      results[#results + 1] = { path = path, status = "skipped" }
      step()
      return
    end

    pp.create({
      inputs = { path },
      on_conflict = opts.on_conflict or "suffix",
      __callback = function(result)
        results[#results + 1] = {
          path = path,
          status = result.status,
          output = result.path,
          error = result.error,
        }
        step()
      end,
    })
  end

  step()
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

  local ok, pp = pcall(require, "pdfport")
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
