---@module 'filetree.features.tag_system'
---@brief Assign arbitrary text tags to nodes for grouping and filtering.
---@description
--- Tags are free-form strings (e.g. "todo", "review", "wip").
--- Each node can carry multiple tags. Tags are stored globally per node path
--- in a JSON store.
---
--- EOL virtual text: #tag1 #tag2 appended to matching lines in the tree buffer.
--- Filter mode: dim or hide non-matching nodes (uses ignore_patterns namespace).
---
--- Config:
---   enabled       boolean
---   keymap        string?   Key to edit tags for current node (default "gt").
---   hl_group      string    Highlight for tag virtual text (default "Special").
---   filter_hl     string    Highlight for dimmed non-matching nodes (default "Comment").
---
--- Commands (via :Filetree dispatcher):
---   :Filetree tag add <tag>
---   :Filetree tag remove <tag>
---   :Filetree tag filter <tag>
---   :Filetree tag clear
---   :Filetree tag list
---   :Filetree tag edit       (interactive edit, same as keymap)

local notify = require("filetree.util.notify").create("[filetree.tag_system]")

local M = {}

---@type FiletreeTagSystemConfig
local _cfg = {
  enabled    = false,
  keymap     = "gt",
  hl_group   = "Special",
  filter_hl  = "Comment",
}

---@type FiletreeAdapter?
local _adapter = nil

local _ns = vim.api.nvim_create_namespace("filetree_tag_system")

-- ── Persistence ───────────────────────────────────────────────────────────────

local function store_path()
  return vim.fn.stdpath("data") .. "/filetree/tags.json"
end

local function load_store()
  local path = store_path()
  if vim.fn.filereadable(path) == 0 then return {} end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or #lines == 0 then return {} end
  local decoded = vim.fn.json_decode(table.concat(lines, ""))
  return type(decoded) == "table" and decoded or {}
end

local function save_store(data)
  local dir = vim.fn.stdpath("data") .. "/filetree"
  if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end
  vim.fn.writefile({ vim.fn.json_encode(data) }, store_path())
end

-- ── In-memory state ──────────────────────────────────────────────────────────

---@type table<string, string[]>  path → tags list
local _store = {}
---@type string?  Currently active filter tag (nil = no filter)
local _filter_tag = nil

local function tags_for(path)
  return _store[path] or {}
end

local function has_tag(path, tag)
  for _, t in ipairs(tags_for(path)) do
    if t == tag then return true end
  end
  return false
end

-- ── Extmark rendering ────────────────────────────────────────────────────────

local function render(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not _adapter then return end

  local nodes = _adapter.get_visible_nodes and _adapter.get_visible_nodes() or {}
  for _, node in ipairs(nodes) do
    if not node.path or not node.line then goto continue end
    local tags = tags_for(node.path)
    if #tags > 0 then
      local text = " " .. table.concat(vim.tbl_map(function(t) return "#" .. t end, tags), " ")
      pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, node.line - 1, -1, {
        virt_text     = { { text, _cfg.hl_group } },
        virt_text_pos = "eol",
        priority      = 120,
      })
    end
    -- Dim non-matching nodes when a filter is active
    if _filter_tag and not has_tag(node.path, _filter_tag) then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, node.line - 1, 0, {
        line_hl_group = _cfg.filter_hl,
      })
    end
    ::continue::
  end
end

local function refresh_render()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
    render(bufnr)
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Add a tag to the current node.
---@param tag string
function M.add(tag)
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end
  tag = tag:lower():gsub("%s+", "_")
  if not has_tag(node.path, tag) then
    _store[node.path] = _store[node.path] or {}
    table.insert(_store[node.path], tag)
    save_store(_store)
    refresh_render()
    notify.info("Tag added: #" .. tag)
  else
    notify.info("Tag already present: #" .. tag)
  end
end

---Remove a tag from the current node.
---@param tag string
function M.remove(tag)
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end
  local list = _store[node.path] or {}
  local new_list = vim.tbl_filter(function(t) return t ~= tag end, list)
  if #new_list == 0 then _store[node.path] = nil
  else _store[node.path] = new_list end
  save_store(_store)
  refresh_render()
  notify.info("Tag removed: #" .. tag)
end

---Clear all tags from the current node.
function M.clear_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end
  _store[node.path] = nil
  save_store(_store)
  refresh_render()
  notify.info("Tags cleared")
end

---Interactive tag editor for the current node.
function M.edit_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end

  local current = table.concat(tags_for(node.path), " ")
  vim.ui.input({
    prompt  = "Tags (space-separated): ",
    default = current,
  }, function(input)
    if input == nil then return end
    _store[node.path] = nil
    if input ~= "" then
      local tags = {}
      for tag in input:gmatch("%S+") do
        tags[#tags + 1] = tag:lower():gsub("[^%w_%-]", "")
      end
      if #tags > 0 then _store[node.path] = tags end
    end
    save_store(_store)
    refresh_render()
    notify.info("Tags updated for " .. vim.fn.fnamemodify(node.path, ":t"))
  end)
end

---Set or clear a filter tag. Only nodes with this tag will be normal; others dim.
---@param tag string?  nil to clear filter
function M.filter(tag)
  _filter_tag = (tag and tag ~= "") and tag or nil
  refresh_render()
  if _filter_tag then
    notify.info("Filtering by #" .. _filter_tag)
  else
    notify.info("Tag filter cleared")
  end
end

---Show all tagged paths in a floating window.
function M.list()
  local entries = {}
  for path, tags in pairs(_store) do
    entries[#entries + 1] = string.format("%-50s %s",
      vim.fn.fnamemodify(path, ":~:."),
      table.concat(vim.tbl_map(function(t) return "#" .. t end, tags), " "))
  end
  table.sort(entries)

  if #entries == 0 then notify.info("No tags defined"); return end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, entries)
  vim.bo[buf].modifiable = false

  local width  = math.min(80, vim.o.columns - 4)
  local height = math.min(#entries, 20)
  local win    = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    width = width, height = height,
    row   = math.floor((vim.o.lines - height) / 2),
    col   = math.floor((vim.o.columns - width) / 2),
    title = " Tags (" .. #entries .. ") ", title_pos = "center",
  })

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q",     function() vim.api.nvim_win_close(win, true) end, opts)
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, opts)
end

---Return all tags for a given path.
---@param path string
---@return string[]
function M.get_tags(path) return tags_for(path) end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeTagSystemConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter
  _store   = load_store()

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_tag_system", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      render(ev.buf)
      if _cfg.keymap then
        vim.keymap.set("n", _cfg.keymap, M.edit_current, {
          buffer = ev.buf, silent = true, desc = "Filetree: edit tags",
        })
      end
    end,
  })
end

function M.teardown()
  _adapter    = nil
  _filter_tag = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
