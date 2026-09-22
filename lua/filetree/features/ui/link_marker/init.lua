---@module 'filetree.features.ui.link_marker'
---@brief Decorate symlinked tree nodes with an inline sign right before their
---own icon, so a symlink reads differently from a plain file/directory at a
---glance -- and an optional eol marker naming the target.
---@description
--- Adapter-agnostic, same shape as `git_status`/`size_info`: walks the
--- rendered tree buffer line by line and asks the adapter for the node on
--- each line, then draws a small sign for any node the adapter reports as a
--- link. The sign itself is placed as an *inline* extmark right past the
--- line's leading indent/guide characters -- i.e. exactly where the node's
--- own icon starts -- found fresh per render as the first non-blank byte on
--- the line, since indent width and guide glyphs are backend/config-
--- dependent and not otherwise exposed to this adapter-agnostic feature.
--- (`show_target`'s "-> target" text, when on, stays an eol marker -- an
--- inline path in front of the name would push the name itself around.)
---
--- Costs nothing extra per render: it reads `node.is_link`/`node.link_to`/
--- `node.link_broken`, fields the neo-tree and nvim-tree adapters already
--- populate from data their own backend held (see `adapter/neotree.lua`'s
--- `to_filetree_node` comment) — no `stat`/`readlink` call happens here. On
--- an adapter without `get_node_at_line` (netrw, oil.nvim, mini.files) this
--- silently draws nothing, the same "silently skipped" contract the other
--- line-resolved decorations use (see docs/FEATURES/BACKENDS.md).
---
--- A symlink whose target the adapter could not resolve (a dangling link)
--- gets the `broken` sign instead of `symlink` when the adapter can tell the
--- difference (neo-tree only — see the adapter comment); otherwise it is
--- shown as a plain symlink.
---
--- Hard links are deliberately NOT decorated here: telling a file with
--- `nlink > 1` apart from an ordinary file needs an actual `stat`, and every
--- one of its several names is an equal hard link — there is no single
--- dirent to flag as "the" hard link. That check belongs on demand, not on
--- every rendered line; see `node_info`'s "Links" line instead.

local au = require("filetree.util.autocmd")
local bufevents = require("filetree.util.bufevents")
local tree_attach = require("filetree.util.tree_attach")
local lib_debounce = require("lib.nvim.debounce")
local M = {}

---@type FiletreeLinkMarkerConfig
local _cfg = {
  show_target = false,
  target_hl = "Comment",
  signs = {
    symlink = { text = "⇢", hl = "Special" },
    broken = { text = "⇢!", hl = "DiagnosticError" },
  },
}

---Option schema (see `filetree.config.schema`): exactly what
---`features.link_marker` accepts. Keep it in step with the keys this module reads;
---`TESTS/config_schema.lua` fails when it drifts.
---@type FiletreeSchema
M.SCHEMA = {
  show_target = "boolean",
  target_hl = "string",
  signs = {
    "table",
    fields = {
      symlink = { "table", fields = { text = "string", hl = "string" } },
      broken = { "table", fields = { text = "string", hl = "string" } },
    },
  },
}

---@type FiletreeAdapter?
local _adapter = nil

---@type integer  extmark namespace
local _ns = -1

---@type table?  debounce handle: { call, cancel }
local _render_debounce = nil

---Unsubscribe handle for `_adapter.on_render`, when the adapter supports it.
---@type fun()|nil
local _unsubscribe_render = nil

-- ── Rendering ─────────────────────────────────────────────────────────────────

function M._render()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not _adapter.get_node_at_line then return end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for linenr = 0, #lines - 1 do
    local node = _adapter.get_node_at_line(bufnr, linenr)
    if node and node.is_link then
      local sign = (node.link_broken and _cfg.signs.broken) or _cfg.signs.symlink
      if sign then
        -- First non-blank byte on the line -- past any indent/tree-guide
        -- characters, right where the node's own icon begins.
        local col = (lines[linenr + 1]:find("%S") or 1) - 1
        pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, col, {
          virt_text = { { sign.text .. " ", sign.hl } },
          virt_text_pos = "inline",
          priority = 45,
        })
        if _cfg.show_target and type(node.link_to) == "string" and node.link_to ~= "" then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, linenr, -1, {
            virt_text = { { " -> " .. node.link_to, _cfg.target_hl } },
            virt_text_pos = "eol",
            priority = 45,
          })
        end
      end
    end
  end
end

---Clear all link-marker decorations.
function M.clear()
  if not _adapter then return end
  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeLinkMarkerConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  _cfg = vim.tbl_deep_extend("force", _cfg, config or {})
  _adapter = adapter
  _ns = vim.api.nvim_create_namespace("filetree_link_marker")

  if _render_debounce then _render_debounce.cancel() end
  _render_debounce = lib_debounce.new(M._render, 50)

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_link_marker", true)

  bufevents.register("link_marker", "BufEnter:tree", {
    desc = "[filetree] Re-draw the tree's symlink markers",
    load = function()
      vim.defer_fn(M._render, 50)
    end,
  })

  -- ...and whenever the adapter re-renders the tree on ITS OWN schedule (a
  -- git-status fetch landing, a filesystem-watcher event, `follow_current_file`,
  -- or -- measured directly against a real neo-tree open -- its own filesystem
  -- source finishing its asynchronous scan just after the FIRST BufEnter-
  -- triggered render above). Without this, an extmark placed on one render
  -- gets wiped by the next such redraw (a full content replace, not an
  -- incremental edit, does not carry extmarks over) and only reappears once
  -- something else asks for a redraw -- which for a tree opened and never
  -- touched again would be never. Same mechanism, same comment, as `marks`'
  -- checkmarks. Optional: only adapters that expose `on_render` (currently
  -- neo-tree) get this; others fall back to BufEnter/CursorMoved alone.
  if type(adapter.on_render) == "function" then
    _unsubscribe_render = adapter.on_render(M._render)
  end

  -- A debounced buffer-local CursorMoved keeps up with expand/collapse and
  -- navigation in between BufEnters -- same trigger `git_status` uses for
  -- its own re-renders, so both decorations stay in step on the same redraw.
  tree_attach.on_attach(function(buf)
    au.acmd("CursorMoved", {
      group = _augroup,
      buffer = buf,
      callback = function()
        if _render_debounce then _render_debounce.call() end
      end,
    })
  end)
end

function M.teardown()
  bufevents.unregister("link_marker")
  M.clear()
  _adapter = nil
  if _unsubscribe_render then
    _unsubscribe_render()
    _unsubscribe_render = nil
  end
  if _render_debounce then
    _render_debounce.cancel()
    _render_debounce = nil
  end
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
