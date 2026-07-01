---@module 'filetree.features.notes'
---@brief Attach text notes to files and directories, persisted as JSON.
---@description
--- Notes are stored in stdpath("data")/filetree/notes.json, keyed by the
--- absolute path of the file or directory. A note can be any text.
---
--- In the tree buffer, nodes that have notes get a "📝" (configurable)
--- extmark indicator at eol. Hovering over a noted node and pressing the
--- keymap opens a floating window to view or edit the note.
---
--- API:
---   M.add(path, text)     Add or replace a note.
---   M.remove(path)        Remove the note for a path.
---   M.toggle_current()    Add/edit/remove note for the node under cursor.
---   M.show(path)          Show a floating viewer/editor for path's note.
---   M.get(path)           Return the note text or nil.
---   M.get_all()           Return the full {path→text} table.
---
--- Keymap (default): "gn" inside tree buffer.
--- User commands: :FiletreeNotesShow, :FiletreeNotesClear

local notify = require("filetree.util.notify").create("[filetree.notes]")

local M = {}

---@type FiletreeNotesConfig
local _cfg = {
  enabled   = false,
  keymap    = "gn",
  indicator = "📝",
  hl_group  = "DiagnosticHint",
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace
local _ns = -1

-- ── Storage ───────────────────────────────────────────────────────────────────

local _store_path = ""

---@type table<string, string>  abs_path → note text
local _notes = {}

local function ensure_dir()
  local dir = vim.fn.fnamemodify(_store_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end
end

local function load()
  if vim.fn.filereadable(_store_path) == 0 then return end
  local ok, content = pcall(vim.fn.readfile, _store_path)
  if not ok or not content or #content == 0 then return end
  local jok, data = pcall(vim.fn.json_decode, table.concat(content, "\n"))
  if jok and type(data) == "table" then _notes = data end
end

local function save()
  ensure_dir()
  local ok, enc = pcall(vim.fn.json_encode, _notes)
  if ok then pcall(vim.fn.writefile, { enc }, _store_path) end
end

-- ── Extmark rendering ─────────────────────────────────────────────────────────

local function render()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not _adapter.get_node_at_line then return end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for linenr = 0, line_count - 1 do
    local node = _adapter.get_node_at_line(bufnr, linenr)
    if node and _notes[node.path] then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, -1, {
        virt_text     = { { " " .. _cfg.indicator, _cfg.hl_group } },
        virt_text_pos = "eol",
        priority      = 70,
      })
    end
  end
end

-- ── Floating viewer / editor ──────────────────────────────────────────────────

---@param path string  Absolute path of the noted file.
local function open_note_window(path)
  local existing = _notes[path] or ""
  local lines = {}
  for l in (existing .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = l
  end
  if #lines == 0 then lines = { "" } end

  local max_w = math.min(70, math.floor(vim.o.columns * 0.6))
  local width = max_w
  local height = math.min(math.max(#lines + 2, 4), 20)
  local row = math.floor((vim.o.lines   - height) / 2)
  local col = math.floor((vim.o.columns - width)  / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("buftype",  "acwrite", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden","wipe",    { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })

  local win = vim.api.nvim_open_win(bufnr, true, {
    relative  = "editor",
    row = row, col = col, width = width, height = height,
    style = "minimal", border = "rounded",
    title = " Note: " .. vim.fn.fnamemodify(path, ":t") .. " ",
    title_pos = "center",
  })
  vim.api.nvim_set_option_value("wrap",    true,  { win = win })
  vim.api.nvim_set_option_value("linebreak", true, { win = win })

  local close = function()
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end

  local save_note = function()
    local note_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local text = table.concat(note_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
      _notes[path] = nil
      notify.info("Note removed")
    else
      _notes[path] = text
      notify.info("Note saved")
    end
    save()
    vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
    render()
  end

  local aug = vim.api.nvim_create_augroup("filetree_notes_win_" .. bufnr, { clear = true })

  -- :w saves the note
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group  = aug,
    buffer = bufnr,
    callback = function()
      save_note()
      close()
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group  = aug,
    buffer = bufnr,
    once   = true,
    callback = function()
      pcall(vim.api.nvim_del_augroup_by_id, aug)
    end,
  })

  local opts = { buffer = bufnr, nowait = true }
  vim.keymap.set("n", "<C-s>", function() save_note(); close() end, opts)
  vim.keymap.set("n", "q",     function()
    -- If modified, ask
    if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
      local ans = vim.fn.input("Save note? [y/n/c] ")
      if ans:lower() == "y" then save_note() end
      if ans:lower() == "c" then return end
    end
    close()
  end, opts)
  vim.keymap.set("n", "<Esc>", function() close() end, opts)

  -- Hint
  vim.api.nvim_echo({{ " <C-s>/:w save  q quit  <Esc> discard ", "Comment" }}, false, {})
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Add or replace a note for `path`.
---@param path string
---@param text string
function M.add(path, text)
  _notes[path] = text
  save()
  render()
end

---Remove the note for `path`.
---@param path string
function M.remove(path)
  _notes[path] = nil
  save()
  render()
  notify.info("Note removed: " .. vim.fn.fnamemodify(path, ":t"))
end

---Return the note text for `path`, or nil.
---@param path string
---@return string?
function M.get(path)
  return _notes[path]
end

---Return the full notes table.
---@return table<string, string>
function M.get_all()
  return _notes
end

---Open note viewer/editor for the current tree node.
---If no note exists, opens an empty editor.
function M.toggle_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node then
    notify.warn("no node under cursor")
    return
  end
  open_note_window(node.path)
end

---Show the note for `path` in a floating window.
---@param path string
function M.show(path)
  open_note_window(path)
end

---Clear all notes.
function M.clear_all()
  _notes = {}
  save()
  render()
  notify.info("All notes cleared")
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeNotesConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg        = vim.tbl_deep_extend("force", _cfg, config)
  _adapter    = adapter
  _ns         = vim.api.nvim_create_namespace("filetree_notes")
  _store_path = vim.fn.stdpath("data") .. "/filetree/notes.json"

  load()

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_notes", { clear = true })

  if _cfg.keymap then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = "neo-tree,NvimTree",
      callback = function(ev)
        render()
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.keymap.set("n", _cfg.keymap, M.toggle_current, {
            buffer = buf, silent = true, desc = "Filetree: open note for current node",
          })
        end)
      end,
    })
  end

  vim.api.nvim_create_autocmd("BufEnter", {
    group   = _augroup,
    pattern = "*",
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft == "neo-tree" or ft == "NvimTree" then render() end
    end,
  })

end

function M.teardown()
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
