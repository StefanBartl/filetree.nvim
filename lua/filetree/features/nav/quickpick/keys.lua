---@module 'filetree.features.nav.quickpick.keys'
---@brief Temporary buffer-local keys for the quick-pick mode, with exact restore.
---@description
--- While the mode runs, the digits, the mode keys, cancel, cycle and scroll are
--- mapped on the tree buffer -- and, when `silence_nvim_mappings` is on, every
--- other key there is mapped to `<Nop>` so a stray press cannot trigger the
--- tree plugin's own action (neo-tree maps `s`, `t`, `<CR>`, `a`, `d`, ... on
--- the very keys this mode wants) or a global one.
---
--- Both kinds overwrite whatever buffer-local mapping the tree plugin put on
--- that key, so each is read back with `maparg()` BEFORE it is replaced and put
--- back exactly -- rhs or Lua callback, `silent`, `nowait`, `expr`, `desc` -- by
--- `restore()`. A key that had only a global mapping needs no saving: deleting
--- ours uncovers it again.
---
--- The module touches one buffer and nothing else; it holds no state beyond
--- the handle it returns, so the mode owns the lifecycle.

local M = {}

---@class FiletreeQuickpickKeyHandle
---@field buf integer
---@field installed table<string, boolean>  lhs -> true, every key we set.
---@field saved table<string, table>        lhs -> `maparg()` dict of a buffer-local map we replaced.
---@field restore fun()                     Delete ours, put the saved ones back. Idempotent.

---@class FiletreeQuickpickKeyBinding
---@field lhs string
---@field fn fun()
---@field desc? string

local SPECIAL = {
  "<Space>",
  "<CR>",
  "<Tab>",
  "<S-Tab>",
  "<Del>",
  "<Up>",
  "<Down>",
  "<Left>",
  "<Right>",
  "<Home>",
  "<End>",
  "<PageUp>",
  "<PageDown>",
  "<Insert>",
}

---Raw bytes of a key as Neovim resolves it, so `<C-D>`, `<c-d>` and the
---literal control character compare equal.
---@param lhs string
---@return string
local function canon(lhs)
  return vim.api.nvim_replace_termcodes(lhs, true, true, true)
end

---`lhs` spelling of a printable ASCII character: the three that `:map` treats
---as syntax are spelled with their key names.
---@param char string
---@return string
local function printable_lhs(char)
  if char == "<" then return "<lt>" end
  if char == "|" then return "<Bar>" end
  if char == "\\" then return "<Bslash>" end
  return char
end

---Every key the "silence" pass would map to `<Nop>`, except those whose bytes
---are in `taken`: printable ASCII, the named specials and Ctrl+letter.
---
--- `<C-i>`, `<C-m>` and `<C-[>` are the same bytes as `<Tab>`, `<CR>` and
--- `<Esc>` -- they are not separate keys, and a duplicate would map the same
--- byte twice. They fall out through the byte comparison, so `<Esc>` is never
--- silenced as a side effect of silencing Ctrl+[.
---@param taken string[]  Keys already bound to something (any spelling).
---@return string[] lhs
function M.silence_candidates(taken)
  local seen = {}
  for _, lhs in ipairs(taken or {}) do
    seen[canon(lhs)] = true
  end
  -- `<Esc>` is never silenced, whatever the cancel key is configured to be:
  -- with a cancel key moved elsewhere, Esc doing nothing is still safer than
  -- Esc doing something in a mode that has no way out but a timeout.
  seen[canon("<Esc>")] = true

  local out = {}
  ---@param lhs string
  local function add(lhs)
    local key = canon(lhs)
    if seen[key] then return end
    seen[key] = true
    out[#out + 1] = lhs
  end

  for code = 33, 126 do
    add(printable_lhs(string.char(code)))
  end
  for _, lhs in ipairs(SPECIAL) do
    add(lhs)
  end
  for code = string.byte("a"), string.byte("z") do
    add("<C-" .. string.char(code) .. ">")
  end
  return out
end

---The buffer-local normal-mode mapping on `lhs`, as a `maparg()` dict, or nil
---when the key has none (or only a global one).
---@param buf integer
---@param lhs string
---@return table|nil
local function buffer_local_map(buf, lhs)
  local dict
  vim.api.nvim_buf_call(buf, function()
    dict = vim.fn.maparg(lhs, "n", false, true)
  end)
  if type(dict) == "table" and next(dict) ~= nil and dict.buffer == 1 then return dict end
  return nil
end

---Put one saved mapping back.
---@param buf integer
---@param lhs string
---@param dict table
local function reinstate(buf, lhs, dict)
  local opts = {
    noremap = dict.noremap == 1,
    silent = dict.silent == 1,
    expr = dict.expr == 1,
    nowait = dict.nowait == 1,
    desc = dict.desc,
    callback = dict.callback,
  }
  -- `rhs` is "" for a Lua mapping; the callback carries the action.
  pcall(vim.api.nvim_buf_set_keymap, buf, "n", lhs, dict.callback and "" or dict.rhs or "", opts)
end

---Map `bindings` (and, when `silence`, every other candidate key) on `buf`,
---remembering what they replaced.
---@param buf integer
---@param bindings FiletreeQuickpickKeyBinding[]
---@param silence boolean
---@return FiletreeQuickpickKeyHandle
function M.install(buf, bindings, silence)
  ---@type FiletreeQuickpickKeyHandle
  local handle = { buf = buf, installed = {}, saved = {}, restore = function() end }
  local restored = false

  ---@param lhs string
  ---@param rhs string
  ---@param opts table
  local function set(lhs, rhs, opts)
    if handle.installed[lhs] then return end
    local prior = buffer_local_map(buf, lhs)
    if prior then handle.saved[lhs] = prior end
    opts.nowait = true
    opts.noremap = true
    opts.silent = true
    if pcall(vim.api.nvim_buf_set_keymap, buf, "n", lhs, rhs, opts) then
      handle.installed[lhs] = true
    else
      handle.saved[lhs] = nil
    end
  end

  local taken = {}
  for _, b in ipairs(bindings) do
    taken[#taken + 1] = b.lhs
  end
  for _, b in ipairs(bindings) do
    set(b.lhs, "", { callback = b.fn, desc = b.desc or "[filetree.quickpick]" })
  end
  if silence then
    for _, lhs in ipairs(M.silence_candidates(taken)) do
      set(lhs, "<Nop>", { desc = "[filetree.quickpick] silenced" })
    end
  end

  handle.restore = function()
    if restored then return end
    restored = true
    if not vim.api.nvim_buf_is_valid(buf) then return end
    for lhs in pairs(handle.installed) do
      pcall(vim.api.nvim_buf_del_keymap, buf, "n", lhs)
    end
    for lhs, dict in pairs(handle.saved) do
      reinstate(buf, lhs, dict)
    end
  end
  return handle
end

return M
