---@module 'filetree.features.bookmarks.store'
---@brief JSON persistence layer for bookmarks.

local M = {}

---@class FiletreeBookmark
---@field path    string   Absolute file or directory path.
---@field label   string?  Optional user-defined label.
---@field added   integer  Unix timestamp.

local _path = nil ---@type string?
local _data = {} ---@type FiletreeBookmark[]

local function storage_path()
  if _path then return _path end
  _path = vim.fn.stdpath("data") .. "/filetree/bookmarks.json"
  return _path
end

local function ensure_dir()
  local dir = vim.fn.fnamemodify(storage_path(), ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

function M.load()
  local p = storage_path()
  if vim.fn.filereadable(p) == 0 then
    _data = {}
    return
  end
  local ok, content = pcall(vim.fn.readfile, p)
  if not ok or not content or #content == 0 then
    _data = {}
    return
  end
  local json_ok, decoded = pcall(vim.fn.json_decode, table.concat(content, "\n"))
  _data = (json_ok and type(decoded) == "table") and decoded or {}
end

function M.save()
  ensure_dir()
  local ok, encoded = pcall(vim.fn.json_encode, _data)
  if ok then
    pcall(vim.fn.writefile, { encoded }, storage_path())
  end
end

---@return FiletreeBookmark[]
function M.all()
  return _data
end

---@param path string
---@return FiletreeBookmark?
function M.find(path)
  for _, b in ipairs(_data) do
    if b.path == path then return b end
  end
  return nil
end

---@param path   string
---@param label? string
function M.add(path, label)
  if M.find(path) then return end
  _data[#_data + 1] = {
    path  = path,
    label = label,
    added = os.time(),
  }
  M.save()
end

---@param path string
function M.remove(path)
  for i, b in ipairs(_data) do
    if b.path == path then
      table.remove(_data, i)
      M.save()
      return
    end
  end
end

function M.clear()
  _data = {}
  M.save()
end

return M
