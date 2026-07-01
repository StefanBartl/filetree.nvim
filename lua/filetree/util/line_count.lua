---@module 'filetree.util.line_count'
---@brief Count lines in text/source files; nil for binary/oversized files.

local M = {}

local uv = vim.uv or vim.loop

---@type table<string, true>
local TEXT_EXTS = {
  lua=true, py=true, js=true, ts=true, jsx=true, tsx=true, mjs=true, cjs=true,
  go=true, rs=true, c=true, cpp=true, h=true, hpp=true, cc=true, hh=true,
  cs=true, java=true, kt=true, kts=true, swift=true, dart=true, zig=true,
  sh=true, bash=true, zsh=true, fish=true, ksh=true,
  html=true, astro=true, vue=true, svelte=true, css=true, scss=true, sass=true, less=true,
  json=true, toml=true, yaml=true, yml=true, xml=true, ini=true, cfg=true, conf=true,
  env=true, editorconfig=true,
  md=true, mdx=true, txt=true, rst=true, org=true, tex=true, adoc=true,
  vim=true, vimrc=true, make=true, makefile=true, cmake=true, dockerfile=true, nix=true,
  csv=true, tsv=true, log=true, diff=true, patch=true,
}

---@type table<string, true>
local BINARY_EXTS = {
  png=true, jpg=true, jpeg=true, gif=true, ico=true, bmp=true, tiff=true,
  webp=true, avif=true, pdf=true,
  zip=true, tar=true, gz=true, bz2=true, xz=true, ["7z"]=true, rar=true, zst=true,
  exe=true, dll=true, so=true, dylib=true, bin=true, obj=true, lib=true, a=true, o=true,
  mp4=true, mp3=true, avi=true, mkv=true, mov=true, wav=true, flac=true, ogg=true,
  db=true, sqlite=true, sqlite3=true,
  ttf=true, otf=true, woff=true, woff2=true,
}

local MAX_BYTES = 5 * 1024 * 1024

---Return true when the extension is a known text/source type.
---@param ext string|nil  Without leading dot, any case.
---@return boolean
function M.is_countable(ext)
  if not ext or ext == "" then return false end
  local lower = ext:lower()
  if BINARY_EXTS[lower] then return false end
  return TEXT_EXTS[lower] == true
end

---Return true when the extension is a known binary type.
---@param ext string|nil
---@return boolean
function M.is_binary_ext(ext)
  if not ext or ext == "" then return false end
  return BINARY_EXTS[ext:lower()] == true
end

---Count newline-terminated lines in a file.
---Returns nil for binary, oversized, or unreadable files.
---@param path string  Absolute path.
---@param ext  string|nil  File extension without dot.
---@return integer|nil
function M.count(path, ext)
  if not M.is_countable(ext) then return nil end
  if type(path) ~= "string" or path == "" then return nil end

  local stat = uv.fs_stat(path)
  if not stat or stat.type ~= "file" then return nil end
  if stat.size > MAX_BYTES then return nil end
  if stat.size == 0 then return 0 end

  local f = io.open(path, "r")
  if not f then return nil end

  local count = 0
  for _ in f:lines() do count = count + 1 end
  f:close()

  return count
end

---Format a line count for display.
---@param count integer|nil
---@return string  e.g. "142 lines", "1 line", or "".
function M.format(count)
  if not count then return "" end
  return count == 1 and "1 line" or tostring(count) .. " lines"
end

return M
