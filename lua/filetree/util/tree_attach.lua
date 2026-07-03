---@module 'filetree.util.tree_attach'
---@brief Central "on tree buffer" dispatcher for per-buffer setup (keymaps).
---@description
--- Instead of every feature registering its own `FileType` autocmd to bind
--- tree-buffer keymaps, features register a callback here and a single FileType
--- autocmd runs them all (scheduled, past the adapter's own keymap setup, with a
--- buffer-validity guard done once, centrally).
---
--- Lifecycle (driven by filetree.setup):
---   1. reset()            — clear callbacks (start of setup)
---   2. on_attach(fn)      — each enabled feature registers in its setup()
---   3. install(adapter)   — create the single FileType autocmd (end of setup)
---
--- `fn` receives the tree buffer number: `fn(buf)`.

local au = require("filetree.util.autocmd")

local M = {}

---@type fun(buf: integer)[]
local _callbacks = {}
---@type integer?
local _augroup = nil

---Clear all registered callbacks. Called at the start of setup so a re-setup
---does not accumulate stale bindings.
function M.reset()
  _callbacks = {}
end

---Register a callback to run once for each tree buffer when it attaches.
---@param fn fun(buf: integer)
function M.on_attach(fn)
  if type(fn) == "function" then
    _callbacks[#_callbacks + 1] = fn
  end
end

---Install the single FileType autocmd that dispatches to all callbacks.
---Idempotent: clears and recreates its augroup. Call after all features'
---setup() have registered.
---@param adapter FiletreeAdapter
function M.install(adapter)
  au.del_group(_augroup)
  _augroup = au.group("filetree_tree_attach", true)

  local pattern = (adapter and type(adapter.filetypes) == "table" and #adapter.filetypes > 0)
    and adapter.filetypes
    or { "neo-tree", "NvimTree" }

  au.acmd("FileType", {
    group   = _augroup,
    pattern = pattern,
    callback = function(ev)
      local buf = ev.buf
      -- Defer past the adapter's own buffer-local keymap setup, then run every
      -- registered feature callback once for this buffer.
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        for _, fn in ipairs(_callbacks) do
          pcall(fn, buf)
        end
      end)
    end,
  })
end

---Tear down the dispatcher (full teardown; re-setup uses reset()+install()).
function M.teardown()
  au.del_group(_augroup)
  _augroup = nil
  _callbacks = {}
end

return M
