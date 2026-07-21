---@module 'filetree.features.create_from_template'
---@brief Create files from user-defined templates with variable substitution.
---@description
--- Templates are stored as plain files in a configurable directory
--- (default: stdpath("data")/filetree/templates/).
--- Each file in that directory is a template; its filename is the template
--- name shown in the picker.
---
--- Template variables (replaced on creation):
---   ${filename}   Basename of the new file (without extension)
---   ${ext}        Extension of the new file (without dot)
---   ${date}       Current date in YYYY-MM-DD format
---   ${year}       Current year
---   ${month}      Current month (01-12)
---   ${day}        Current day (01-31)
---   ${time}       Current time in HH:MM:SS
---   ${author}     Value of config.author or $USER/$USERNAME
---   ${module}     Lua-style module path from project root (for .lua files)
---
--- Workflow:
---   1. Press "t" in tree (or :FiletreeCreateFromTemplate)
---   2. Pick a template from the floating list
---   3. Enter the new filename
---   4. File is created in the current node's directory and opened
---
--- Keymap (default): "t" in tree buffer.

local notify  = require("filetree.util.notify").create("[filetree.create_from_template]")
local path_u  = require("filetree.util.path")
local bufutil = require("filetree.util.buffer")

local map    = require("filetree.util.map")
local au     = require("filetree.util.autocmd")
local window = require("filetree.util.window")
local M = {}

---@type FiletreeCreateFromTemplateConfig
local _cfg = {
  enabled      = false,
  keymap       = "t",
  template_dir = nil,  -- defaults to stdpath("data")/filetree/templates/
  author       = nil,  -- defaults to $USER/$USERNAME
  open_after   = true, -- open file in editor after creation
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Template directory ────────────────────────────────────────────────────────

local function template_dir()
  local dir = _cfg.template_dir
    or (vim.fn.stdpath("data") .. "/filetree/templates")
  if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end
  return dir
end

-- ── Variable substitution ─────────────────────────────────────────────────────

local function author()
  if _cfg.author and _cfg.author ~= "" then return _cfg.author end
  return vim.env.USER or vim.env.USERNAME or "unknown"
end

local function module_path(abs_path)
  local ok_pr, pr = require("filetree.features").load("project_root")
  local root
  if ok_pr and type(pr.find) == "function" then
    root = pr.find(abs_path)
  else
    root = vim.fn.getcwd()
  end
  local rel = path_u.relative(abs_path, root .. "/lua")
  if rel == abs_path then
    rel = path_u.relative(abs_path, root)
  end
  return rel:gsub("%.lua$", ""):gsub("[/\\]", "."):gsub("%.init$", "")
end

local function substitute(content, new_path)
  local base = vim.fn.fnamemodify(new_path, ":t:r")  -- name without ext
  local ext  = vim.fn.fnamemodify(new_path, ":e")
  local now  = os.date("*t")
  local vars = {
    filename = base,
    ext      = ext,
    date     = os.date("%Y-%m-%d"),
    year     = tostring(now.year),
    month    = string.format("%02d", now.month),
    day      = string.format("%02d", now.day),
    time     = os.date("%H:%M:%S"),
    author   = author(),
    module   = module_path(new_path),
  }
  return (content:gsub("%${(%w+)}", function(key)
    return vars[key] or ("${" .. key .. "}")
  end))
end

-- ── Template list ─────────────────────────────────────────────────────────────

local function list_templates()
  local dir = template_dir()
  local ok, entries = pcall(vim.fn.readdir, dir)
  if not ok then return {} end
  local tmpl = {}
  for _, e in ipairs(entries) do
    local full = dir .. "/" .. e
    if vim.fn.filereadable(full) == 1 then
      tmpl[#tmpl + 1] = { name = e, path = full }
    end
  end
  table.sort(tmpl, function(a, b) return a.name < b.name end)
  return tmpl
end

-- ── Creation ──────────────────────────────────────────────────────────────────

local function create_from(tmpl_path, dest_path)
  local ok, lines = pcall(vim.fn.readfile, tmpl_path)
  if not ok then
    notify.error("Cannot read template: " .. tmpl_path)
    return false
  end
  local content   = table.concat(lines, "\n")
  local rendered  = substitute(content, dest_path)
  local rendered_lines = {}
  for l in (rendered .. "\n"):gmatch("([^\n]*)\n") do
    rendered_lines[#rendered_lines + 1] = l
  end
  -- Remove trailing empty line added by the split
  if rendered_lines[#rendered_lines] == "" and #rendered_lines > 1 then
    table.remove(rendered_lines)
  end

  local rc = vim.fn.writefile(rendered_lines, dest_path)
  if rc ~= 0 then
    notify.error("Could not write: " .. dest_path)
    return false
  end
  return true
end

-- ── Picker flow ───────────────────────────────────────────────────────────────

local function pick_template(templates, on_select)
  if #templates == 0 then
    notify.warn("No templates in: " .. template_dir())
    return
  end

  local lines = {}
  for i, t in ipairs(templates) do
    lines[i] = string.format(" [%2d]  %s", i, t.name)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = " <CR> select  |  q close"

  local width  = 0
  for _, l in ipairs(lines) do width = math.max(width, #l + 2) end
  width  = math.min(width, 60)
  local height = math.min(#lines, 20)
  local row = math.floor((vim.o.lines   - height) / 2)
  local col = math.floor((vim.o.columns - width)  / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  vim.api.nvim_set_option_value("buftype",    "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden",  "wipe",   { buf = bufnr })

  local win = vim.api.nvim_open_win(bufnr, true, {
    relative  = "editor",
    row = row, col = col, width = width, height = height,
    style = "minimal", border = "rounded",
    title = " Templates ", title_pos = "center",
  })

  local close = function()
    pcall(vim.api.nvim_win_close, win, true)
  end

  local opts = { buffer = bufnr, nowait = true, silent = true }
  map("n", "<CR>", function()
    local idx  = vim.api.nvim_win_get_cursor(win)[1]
    local tmpl = templates[idx]
    if tmpl then close(); on_select(tmpl) end
  end, opts)
  window.nice_quit(win)

  -- Number shortcuts
  for i = 1, math.min(9, #templates) do
    map("n", tostring(i), function()
      close(); on_select(templates[i])
    end, opts)
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Open the template picker and create a file in `dest_dir`.
---@param dest_dir string  Absolute destination directory.
function M.open(dest_dir)
  local templates = list_templates()

  pick_template(templates, function(tmpl)
    local name = vim.fn.input("Filename (in " .. vim.fn.fnamemodify(dest_dir, ":t") .. "): ")
    if not name or name == "" then return end
    name = path_u.slashify(name)  -- accept "/" or "\" if creating into a subdir
    local dest = dest_dir .. "/" .. name

    if vim.fn.filereadable(dest) == 1 then
      local ans = vim.fn.input("File exists. Overwrite? [y/N] ")
      if ans:lower() ~= "y" then return end
    end

    if create_from(tmpl.path, dest) then
      notify.info("Created: " .. name .. " (from " .. tmpl.name .. ")")
      if _adapter and _adapter.refresh then pcall(_adapter.refresh) end
      if _cfg.open_after then
        -- Open in a real editor window, never the tree window itself (loading
        -- a buffer into the tree's own window fights its window-management
        -- autocmds and can hang Neovim — see smart_create/duplicate_node).
        local tree_win = _adapter and _adapter.get_winid and _adapter.get_winid()
        local win = bufutil.find_editor_win(tree_win)
        if win then vim.api.nvim_set_current_win(win) else vim.cmd("vsplit") end
        vim.cmd("edit " .. vim.fn.fnameescape(dest))
      end
    end
  end)
end

---Open picker at the current tree node's directory.
function M.open_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  local dir  = node
    and (node.type == "directory" and node.path or vim.fn.fnamemodify(node.path, ":h"))
    or vim.fn.getcwd()
  M.open(dir)
end

---Return all available templates.
---@return {name:string, path:string}[]
function M.list()
  return list_templates()
end

---Add a template programmatically.
---@param name    string  Template filename.
---@param content string  Template content.
function M.add_template(name, content)
  local dir  = template_dir()
  local path = dir .. "/" .. name
  local lines = {}
  for l in (content .. "\n"):gmatch("([^\n]*)\n") do lines[#lines+1] = l end
  vim.fn.writefile(lines, path)
  notify.info("Template added: " .. name)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeCreateFromTemplateConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_create_from_template", true)

  if _cfg.keymap then
    au.acmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap, M.open_current, {
            buffer = buf, silent = true, desc = "Filetree: create from template",
          })
        end)
      end,
    })
  end

end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
