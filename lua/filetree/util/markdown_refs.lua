---@module 'filetree.util.markdown_refs'
---@brief Shared soft-dependency bridge to markdown.nvim's `find_references`,
--- plus a reference-rewriting helper. Used by `trash` (flag broken refs with
--- "REF!") and `smart_rename`/`rename_batch`/`copy_move` (rewrite refs to the
--- new path after a move).
---@description
---   local refs_util = require("filetree.util.markdown_refs")
---   local refs = refs_util.find(old_path)          -- {} if markdown.nvim absent
---   for _, r in ipairs(refs) do r.new_target = "REF!" end
---   refs_util.update(refs)                          -- rewrites ](target) -> ](new_target)
---
--- `new_target` is looked up per-ref (not passed once for the whole list) so a
--- single `update()` call can cover a batch of renames where different refs
--- point at different old paths that moved to different new paths.

local M = {}

---Find markdown files referencing `path` (soft-dep on markdown.nvim). Returns
---{} when markdown.nvim isn't installed, or the search itself errors.
---@param path string
---@param opts? { root?: string }  `root` defaults to the nearest project root.
---@return table[]  MarkdownFileRef[] — { file, line, target, display }
function M.find(path, opts)
  local ok_md, md = pcall(require, "markdown_nvim")
  if not ok_md or type(md.find_references) ~= "function" then return {} end

  local root = opts and opts.root
  if not root then
    local ok_pr, project_root = require("filetree.features").load("project_root")
    if ok_pr and project_root and type(project_root.find) == "function" then
      local ok_find, found = pcall(project_root.find, vim.fn.fnamemodify(path, ":h"))
      if ok_find and type(found) == "string" then root = found end
    end
  end

  local ok_refs, refs = pcall(md.find_references, path, { root = root })
  if not ok_refs or type(refs) ~= "table" then return {} end
  return refs
end

---The cwd-relative link target a moved/renamed file should be written as —
---matches the convention `markdown_links` already uses for generated links
---(`fnamemodify(path, ":.")`), so an auto-updated reference reads the same
---way a freshly-authored one would.
---@param new_path string
---@return string
function M.relative_target(new_path)
  return (vim.fn.fnamemodify(new_path, ":."):gsub("\\", "/"))
end

---Rewrite each ref's link target to its own `r.new_target` (must be set on
---every ref before calling — e.g. `"REF!"` for a delete, or `relative_target
---(new_path)` per-file for a rename/move batch). Grouped by file so each is
---read/written at most once even with multiple matches.
---@param refs table[]  MarkdownFileRef[], each with `.new_target` set.
---@return integer files_changed
function M.update(refs)
  local by_file = {}
  for _, r in ipairs(refs) do
    by_file[r.file] = by_file[r.file] or {}
    table.insert(by_file[r.file], r)
  end

  local files_changed = 0
  for file, file_refs in pairs(by_file) do
    local ok, lines = pcall(vim.fn.readfile, file)
    if ok and lines then
      local changed = false
      for _, r in ipairs(file_refs) do
        local line = lines[r.line]
        if line and r.new_target then
          local pattern = "%]%(" .. vim.pesc(r.target) .. "%)"
          local repl     = "](" .. r.new_target:gsub("%%", "%%%%") .. ")"
          local new_line, n = line:gsub(pattern, repl)
          if n > 0 then
            lines[r.line] = new_line
            changed = true
          end
        end
      end
      if changed then
        vim.fn.writefile(lines, file)
        files_changed = files_changed + 1
      end
    end
  end
  return files_changed
end

return M
