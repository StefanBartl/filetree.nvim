---@module 'filetree.util.case_clash'
---@brief Case-insensitive filesystem guard for the fileops features.
---@description
--- On Windows and macOS (the default APFS/HFS+ layout) `Foo` and `foo` are the
--- *same* directory entry — you cannot have both at once. Two consequences the
--- fileops features have to handle:
---
---   * A rename that only changes case (`Telemetry` → `TELEMETRY`) trips a
---     naive `isdirectory(dst) == 1` existence check, producing a bogus
---     "already exists" prompt for an operation that is in fact fine — an
---     in-place rename just re-cases the entry. `is_alias()` recognises this so
---     smart_rename / rename_batch / move can skip the prompt and rename.
---
---   * A *copy* into that same name genuinely cannot happen: the OS has no
---     second slot to put the copy in. Worse, the shared "Overwrite"
---     resolution would `delete(dst, "rf")` first — and `dst` resolves to the
---     copy's own source, so it deletes the very thing being copied.
---     `resolve()` gives the user a way out (auto-number / new name / cancel)
---     and callers must gate `conflict.remove_existing` behind `is_alias()`.
---
---   local cc = require("filetree.util.case_clash")
---   cc.is_alias(src, dst)          -- dst is just src seen through case-folding
---   cc.resolve(src, dst, function(final_dst) ... end)

local uv = vim.uv or vim.loop

local M = {}

---@return boolean
function M.case_insensitive_fs()
  return vim.fn.has("win32") == 1
    or vim.fn.has("win64") == 1
    or vim.fn.has("mac") == 1
    or vim.fn.has("macunix") == 1
end

---Human-facing name of the OS whose filesystem folds case, for the prompt.
---@return string
function M.os_label()
  if vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1 then return "macOS" end
  return "Windows"
end

---@param p string
---@return string
local function norm(p)
  return (p:gsub("\\", "/"):gsub("/+$", ""))
end

---`a` and `b` currently name the same filesystem object.
---@param a string
---@param b string
---@return boolean
function M.same_file(a, b)
  local ra, rb = uv.fs_realpath(a), uv.fs_realpath(b)
  if ra and rb then return norm(ra):lower() == norm(rb):lower() end
  local sa, sb = uv.fs_stat(a), uv.fs_stat(b)
  return sa ~= nil and sb ~= nil and sa.ino ~= 0 and sa.ino == sb.ino and sa.dev == sb.dev
end

---True when `dst` is a *different spelling* of `src` that the filesystem folds
---onto the same entry — i.e. they differ (case, usually) yet name one object.
---A rename `src` → `dst` is safe (it re-cases in place); a second entry at
---`dst` is impossible.
---@param src string
---@param dst string
---@return boolean
function M.is_alias(src, dst)
  return norm(src) ~= norm(dst) and M.same_file(src, dst)
end

---Ask the user how to handle a copy whose destination collides — only by
---case — with its own source on a case-insensitive filesystem. Calls
---`cb(final_dst)` with a usable path, or `cb(nil)` if they cancelled / the
---dialog was dismissed.
---@param src string
---@param dst string
---@param cb fun(final_dst: string|nil)
function M.resolve(src, dst, cb)
  local confirm_choice = require("filetree.util.confirm_choice")
  local conflict = require("filetree.util.conflict")
  local path = require("filetree.util.path")

  local d = path.slashify(dst)
  local dir = d:match("^(.*)/[^/]*$") or "."
  local base = d:match("([^/]*)$") or d
  local is_dir = vim.fn.isdirectory(src) == 1

  local msg = string.format(
    "%s can't hold two entries whose names differ only in case, so '%s' can't be created next to '%s' here.",
    M.os_label(),
    base,
    vim.fn.fnamemodify(src, ":t")
  )

  confirm_choice(msg, { "Append a number", "Enter a new name", "Cancel" }, function(choice)
    if choice == "Append a number" then
      cb(dir .. "/" .. conflict.unique_name(dir, base, {}, is_dir))
    elseif choice == "Enter a new name" then
      require("lib.nvim.ui.kit").input({
        title = "New name: ",
        default = base,
        on_submit = function(new_name)
          if not new_name or vim.trim(new_name) == "" then
            cb(nil)
            return
          end
          cb(dir .. "/" .. path.slashify(new_name))
        end,
      })
    else
      cb(nil)
    end
  end)
end

return M
