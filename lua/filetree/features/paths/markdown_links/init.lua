---@module 'filetree.features.markdown_links'
---@brief Copy the current node (or a whole tree, or marked nodes) as Markdown links.
---@description
--- Every generated line is `[name](relative/path)`, joined with newlines and
--- written to both the "+" (system) and unnamed '"' registers, matching the
--- copy-to-clipboard convention used by path_copy/copy_file_list.
---
--- Keymaps (in tree buffer, default):
---   ML   Markdown link for the current node
---   MR   Markdown links for every file under the current node, recursively
---   MM   Markdown links for all marked nodes

local notify = require("filetree.util.notify").create("[filetree.markdown_links]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local fs  = require("filetree.util.fs")
local M = {}

---@type FiletreeMarkdownLinksConfig
local _cfg = {
  enabled            = false,
  keymap             = "ML",
  keymap_recursive   = "MR",
  keymap_from_marked = "MM",
}

---@type FiletreeAdapter?
local _adapter = nil

---@param path string
---@return string  markdown link "[name](relative/path)"
local function to_link(path)
  local rel  = vim.fn.fnamemodify(path, ":."):gsub("\\", "/")
  local name = vim.fn.fnamemodify(path, ":t")
  return string.format("[%s](%s)", name, rel)
end

---@param lines string[]
local function copy_to_reg(lines)
  if #lines == 0 then
    notify.warn("No entries to copy")
    return
  end
  local text = table.concat(lines, "\n")
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  notify.info(string.format("Copied %d markdown link(s)", #lines))
end

local function current_node()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()
  if not node or not node.path then
    notify.warn("No current node")
    return nil
  end
  return node
end

---Markdown link for the current node.
function M.link_current()
  local node = current_node()
  if not node then return end
  copy_to_reg({ to_link(node.path) })
end

---Markdown links for every file under the current node, recursively. If the
---current node is a file, falls back to a single link for that file.
function M.link_recursive()
  local node = current_node()
  if not node then return end

  if node.type ~= "directory" then
    copy_to_reg({ to_link(node.path) })
    return
  end

  local files = fs.collect_files((node.path:gsub("\\", "/")))
  local lines = {}
  for _, f in ipairs(files) do
    lines[#lines + 1] = to_link(f)
  end
  copy_to_reg(lines)
end

---Markdown links for all marked nodes.
function M.link_from_marked()
  local ok, marks = require("filetree.features").load("marks")
  if not ok or not marks or marks.count() == 0 then
    notify.warn("No marked nodes")
    return
  end
  local lines = {}
  for _, path in ipairs(marks.get_marked()) do
    lines[#lines + 1] = to_link(path)
  end
  copy_to_reg(lines)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeMarkdownLinksConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_markdown_links", true)

  au.acmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local function kmap(key, fn, desc)
          if key and key ~= "" then
            map("n", key, fn, { buffer = buf, silent = true, desc = "Filetree: " .. desc })
          end
        end
        kmap(_cfg.keymap,             M.link_current,     "markdown link for current node")
        kmap(_cfg.keymap_recursive,   M.link_recursive,    "markdown links recursively")
        kmap(_cfg.keymap_from_marked, M.link_from_marked,  "markdown links from marked nodes")
      end)
    end,
  })
end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
