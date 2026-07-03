---@module 'filetree.features.picker.keymaps'
---@brief Keymap management for the picker mode — install/restore per-buffer mappings.

local map = require("filetree.util.map")
local M = {}

---@alias SavedMapping { lhs: string, rhs: string, noremap: boolean, silent: boolean }

local MODE_PREFIXES = { e = "edit", s = "split", v = "vsplit", t = "tab", p = "preview" }

---@return string[]
function M.mode_prefix_keys()
  local keys = {}
  for k in pairs(MODE_PREFIXES) do keys[#keys + 1] = k end
  return keys
end

---Translate a mode-prefix key to its open mode string.
---@param key string
---@return string?
function M.mode_from_prefix(key)
  return MODE_PREFIXES[key]
end

---Return true when `key` is one of the mode prefix keys.
---@param key string
---@return boolean
function M.is_mode_prefix(key)
  return MODE_PREFIXES[key] ~= nil
end

---Save all normal-mode mappings that will be overridden by picker mode.
---@param bufnr integer
---@return SavedMapping[]
function M.save(bufnr)
  local saved = {}
  local keys_to_save = { "<Esc>" }
  for k in pairs(MODE_PREFIXES) do keys_to_save[#keys_to_save + 1] = k end
  for i = 0, 9 do keys_to_save[#keys_to_save + 1] = tostring(i) end

  for _, lhs in ipairs(keys_to_save) do
    local ok, mapping = pcall(vim.fn.maparg, lhs, "n", false, true)
    if ok and type(mapping) == "table" and mapping.lhs then
      saved[#saved + 1] = {
        lhs    = mapping.lhs,
        rhs    = mapping.rhs or "",
        noremap = mapping.noremap == 1,
        silent  = mapping.silent == 1,
      }
    end
  end
  return saved
end

---Install picker keymaps on a buffer.
---@param bufnr integer
---@param callbacks table<string, fun(...)>   Keys: on_digit, on_mode_prefix, on_escape, on_cycle_filter, on_scroll_up, on_scroll_down
function M.install(bufnr, callbacks)
  local opts = { noremap = true, silent = true, buffer = bufnr }

  -- digit keys 0-9
  for i = 0, 9 do
    local digit = tostring(i)
    map("n", digit, function() callbacks.on_digit(digit) end, opts)
  end

  -- mode prefix keys
  for key in pairs(MODE_PREFIXES) do
    map("n", key, function() callbacks.on_mode_prefix(key) end, opts)
  end

  map("n", "<Esc>",    callbacks.on_escape,       opts)
  map("n", "<Tab>",    callbacks.on_cycle_filter,  opts)
  map("n", "<C-k>",    callbacks.on_scroll_up,     opts)
  map("n", "<C-j>",    callbacks.on_scroll_down,   opts)
end

---Remove picker keymaps and restore saved ones.
---@param bufnr integer
---@param saved  SavedMapping[]
function M.restore(bufnr, saved)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  -- Remove picker keys
  local keys_to_remove = { "<Esc>", "<Tab>", "<C-k>", "<C-j>" }
  for k in pairs(MODE_PREFIXES) do keys_to_remove[#keys_to_remove + 1] = k end
  for i = 0, 9 do keys_to_remove[#keys_to_remove + 1] = tostring(i) end

  for _, lhs in ipairs(keys_to_remove) do
    pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
  end

  -- Restore saved mappings
  for _, m in ipairs(saved) do
    pcall(vim.keymap.set, "n", m.lhs, m.rhs, {
      noremap = m.noremap,
      silent  = m.silent,
      buffer  = bufnr,
    })
  end
end

return M
