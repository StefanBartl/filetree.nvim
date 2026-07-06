---@module 'filetree.features.open_variants'
---@brief Alternate ways to open the current node besides the adapter's default <CR>.
---@description
--- Covers the handful of "open elsewhere" actions that don't fit any other
--- feature: split/vsplit/new-tab, and silently adding the file to the buffer
--- list without moving focus off the tree.
---
--- Splits/tabs never touch the tree window itself -- they resolve (or open)
--- a real editor window first, the same way smart_create avoids hijacking
--- the tree window when writing a new file.
---
--- Keymaps (in tree buffer, default):
---   sg      Open in a vertical split
---   sv      Open in a horizontal split
---   st      Open in a new tab
---   gb      Add to buffer list without switching focus (badd)
---   <S-CR>  Same as gb

local notify = require("filetree.util.notify").create("[filetree.open_variants]")

local map     = require("filetree.util.map")
local au      = require("filetree.util.autocmd")
local bufutil = require("filetree.util.buffer")
local M = {}

---@type FiletreeOpenVariantsConfig
local _cfg = {
  enabled          = false,
  keymap_vsplit    = "sg",
  keymap_split     = "sv",
  keymap_tabnew    = "st",
  keymap_badd      = "gb",
  keymap_badd_alt  = "<S-CR>",
}

---@type FiletreeAdapter?
local _adapter = nil

---@return string?
local function current_file_path()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()
  if not node or node.type ~= "file" then return nil end
  return node.path
end

---Move focus to a real editor window (creating one if none exists), then run
---`cmd` there. Splitting/tabbing from the tree window itself would split the
---tree, not the editor.
---@param cmd string
local function open_in_editor(cmd)
  local path = current_file_path()
  if not path then return end

  local tree_win = _adapter and _adapter.get_winid and _adapter.get_winid()
  local win = bufutil.find_editor_win(tree_win)
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("vsplit")
  end
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(path))
end

function M.open_vsplit() open_in_editor("vsplit") end
function M.open_split()  open_in_editor("split")  end

function M.open_tabnew()
  local path = current_file_path()
  if not path then return end
  vim.cmd("tabnew " .. vim.fn.fnameescape(path))
end

---Add the current node to the buffer list without switching focus away from
---the tree (neo-tree's own "open_badd" command semantics).
function M.open_badd()
  local path = current_file_path()
  if not path then return end
  vim.fn.bufadd(path)
  notify.info("Added to buffer list: " .. vim.fn.fnamemodify(path, ":~:."))
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeOpenVariantsConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_open_variants", true)

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
        kmap(_cfg.keymap_vsplit,   M.open_vsplit, "open in vertical split")
        kmap(_cfg.keymap_split,    M.open_split,  "open in horizontal split")
        kmap(_cfg.keymap_tabnew,   M.open_tabnew, "open in new tab")
        kmap(_cfg.keymap_badd,     M.open_badd,   "add to buffer list (no focus switch)")
        kmap(_cfg.keymap_badd_alt, M.open_badd,   "add to buffer list (no focus switch)")
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
