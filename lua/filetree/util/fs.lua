---@module 'filetree.util.fs'
---@brief Recursive filesystem traversal using libuv.

local M = {}

---Collect files or folders recursively under root_path.
---@param root_path    string
---@param collect_type "files"|"folders"
---@param ignore_fn?   fun(name:string):boolean  Return true to skip an entry.
---@return string[]  Absolute paths.
function M.collect_recursive(root_path, collect_type, ignore_fn)
  local results = {}
  local uv      = vim.uv or vim.loop
  local stack   = { root_path }

  if collect_type == "folders" and vim.fn.isdirectory(root_path) == 1 then
    table.insert(results, root_path)
  end

  while #stack > 0 do
    local path = table.remove(stack)
    local stat = uv.fs_stat(path)
    if stat then
      if stat.type == "file" and collect_type == "files" then
        table.insert(results, path)
      elseif stat.type == "directory" then
        local req = uv.fs_scandir(path)
        if req then
          while true do
            local name, typ = uv.fs_scandir_next(req)
            if not name then break end
            if not (ignore_fn and ignore_fn(name)) then
              local sep   = path:sub(-1) == "/" and "" or "/"
              local child = path .. sep .. name
              if collect_type == "folders" and typ == "directory" then
                table.insert(results, child)
              end
              table.insert(stack, child)
            end
          end
        end
      end
    end
  end

  return results
end

---Convenience wrapper: collect files only.
---@param root_path string
---@param ignore_fn? fun(name:string):boolean
---@return string[]
function M.collect_files(root_path, ignore_fn)
  return M.collect_recursive(root_path, "files", ignore_fn)
end

---Convenience wrapper: collect directories only (includes root_path itself).
---@param root_path string
---@param ignore_fn? fun(name:string):boolean
---@return string[]
function M.collect_folders(root_path, ignore_fn)
  return M.collect_recursive(root_path, "folders", ignore_fn)
end

return M
