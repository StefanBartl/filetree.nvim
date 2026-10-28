---@module 'filetree.features.system.compress.archiver'
---@brief The pure half of `compress`: which tool writes the zip, its argv, a free name.
---@description
--- Nothing here spawns a process, so the argv each tool gets is asserted on every OS
--- (TESTS/compress.lua). Two tools write a `.zip`:
---   * Info-ZIP `zip`, if on PATH -- it stores paths as given, so it runs inside the
---     sources' common folder and can only take sources from ONE folder;
---   * a bsdtar (`-a` picks the format from the `.zip` suffix) -- Windows 10+ ships
---     one as `System32/tar.exe`, macOS as `tar`, elsewhere it is `bsdtar`. Git for
---     Windows' `tar` on PATH is GNU tar, which cannot write zip, so on Windows the
---     System32 one is named by its full path. bsdtar takes one `-C <dir>` per
---     source and so can archive sources from several folders.

local platform = require("filetree.util.platform")
local path = require("filetree.util.path")

local M = {}

---@class FiletreeCompressTool
---@field kind "zip"|"bsdtar"
---@field exe  string  Executable name or absolute path.

---The first available tool, or nil when neither zip nor a bsdtar is found.
---@return FiletreeCompressTool?
function M.detect()
  if vim.fn.executable("zip") == 1 then return { kind = "zip", exe = "zip" } end
  if platform.is_windows() then
    local root = (vim.env.SystemRoot or vim.env.WINDIR or "C:/Windows"):gsub("\\", "/")
    local tar = root .. "/System32/tar.exe"
    if vim.fn.executable(tar) == 1 then return { kind = "bsdtar", exe = tar } end
  end
  if vim.fn.executable("bsdtar") == 1 then return { kind = "bsdtar", exe = "bsdtar" } end
  if vim.fn.has("mac") == 1 and vim.fn.executable("tar") == 1 then
    return { kind = "bsdtar", exe = "tar" }
  end
  return nil
end

---A name as an argument: one starting with `-` would be read as an option.
---@param name string
---@return string
local function as_arg(name)
  return name:sub(1, 1) == "-" and ("./" .. name) or name
end

---The command that writes `out` from `sources` (absolute, `/`-separated, no trailing
---slash). Each source is stored under its own name, a folder with its contents.
---@param tool FiletreeCompressTool
---@param out string        Absolute path of the zip to write.
---@param sources string[]
---@return string[]? cmd
---@return string|string?  cwd, or the reason there is no command
function M.build(tool, out, sources)
  if #sources == 0 then return nil, "nothing to compress" end
  if tool.kind == "zip" then
    local dir = path.parent(sources[1])
    local names = {}
    for _, src in ipairs(sources) do
      if path.parent(src) ~= dir then
        return nil, "zip can only take nodes from one folder (install a bsdtar for more)"
      end
      names[#names + 1] = as_arg(path.basename(src))
    end
    local cmd = { tool.exe, "-r", "-q", "-9", out }
    vim.list_extend(cmd, names)
    return cmd, dir
  end
  local cmd = { tool.exe, "-a", "-c", "-f", out }
  for _, src in ipairs(sources) do
    vim.list_extend(cmd, { "-C", path.parent(src), as_arg(path.basename(src)) })
  end
  return cmd, nil
end

---`want`, or the first `<stem>_<n>.zip` beside it that does not exist yet.
---@param want string
---@return string
function M.free_path(want)
  if not vim.uv.fs_stat(want) then return want end
  local stem = want:gsub("%.zip$", "")
  for n = 2, 999 do
    local candidate = string.format("%s_%d.zip", stem, n)
    if not vim.uv.fs_stat(candidate) then return candidate end
  end
  return want
end

---True when `out` would be written inside one of the `sources` folders -- the
---archive would then try to contain itself.
---@param out string
---@param sources string[]
---@return boolean
function M.inside_source(out, sources)
  for _, src in ipairs(sources) do
    if out:sub(1, #src + 1) == src .. "/" then return true end
  end
  return false
end

return M
