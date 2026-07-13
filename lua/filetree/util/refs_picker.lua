---@module 'filetree.util.refs_picker'
---@brief Multi-select picker over a list of `{file, line}` references, with
--- a file preview and Tab/C-a multi-select. Telescope by default, fzf-lua if
--- preferred, a quickfix-list fallback when neither is installed.
---@description
--- Built for the trash feature's "inspect references" flow (see
--- features/fileops/trash), but adapter-agnostic and reusable anywhere a
--- caller has a list of `{file, line, display}` entries and wants the user
--- to pick a subset of them.
---
---   local refs_picker = require("filetree.util.refs_picker")
---   refs_picker.pick(refs, { prefer = "auto", title = "References" },
---     function(selected) ... end,  -- on_confirm, NOT called on cancel
---     function() ... end)          -- on_cancel
---
--- Telescope/fzf-lua: Enter confirms — the multi-selection if the user
--- toggled any entries (Tab, or C-a for all), else just the entry under the
--- cursor. Esc/q calls `on_cancel`.
---
--- Quickfix fallback: populates the quickfix list and opens it; the user
--- prunes unwanted entries themselves (normal buffer editing, e.g. `dd`) and
--- confirms via `M.qf_confirm()` / backs out via `M.qf_cancel()` — there is
--- no blocking "picker closed" event for a plain quickfix list, so those are
--- exposed as commands (wired to `:Filetree mdrefs confirm|cancel` by the
--- caller) instead of being interactive here.

local path = require("filetree.util.path")

local M = {}

-- ── Telescope ─────────────────────────────────────────────────────────────────

---@param refs table[]
---@param title string
---@param on_confirm fun(selected: table[])
---@param on_cancel fun()
---@return boolean
local function via_telescope(refs, title, on_confirm, on_cancel)
  local ok = pcall(require, "telescope")
  if not ok then return false end
  local pickers      = require("telescope.pickers")
  local finders       = require("telescope.finders")
  local conf          = require("telescope.config").values
  local actions       = require("telescope.actions")
  local action_state  = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = refs,
      entry_maker = function(r)
        return {
          value    = r,
          display  = string.format("%s:%d  %s", path.relative(r.file, vim.fn.getcwd()), r.line, r.display),
          ordinal  = r.file .. " " .. r.display,
          filename = r.file,
          lnum     = r.line,
        }
      end,
    }),
    sorter    = conf.generic_sorter({}),
    previewer = conf.grep_previewer({}),
    attach_mappings = function(prompt_bufnr, map)
      local function confirm()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local multi  = picker:get_multi_selection()
        local chosen = {}
        if #multi > 0 then
          for _, e in ipairs(multi) do chosen[#chosen + 1] = e.value end
        else
          local cur = action_state.get_selected_entry()
          if cur then chosen[1] = cur.value end
        end
        actions.close(prompt_bufnr)
        on_confirm(chosen)
      end
      local function cancel()
        actions.close(prompt_bufnr)
        on_cancel()
      end
      actions.select_default:replace(confirm)
      -- Dedicated picker-local keymaps for <Esc>/q, NOT actions.close:replace():
      -- `close` is a shared action object other telescope machinery (including
      -- our own `confirm` above) calls to actually close the window -- replacing
      -- it globally would make every future call to actions.close() re-invoke
      -- `cancel`, which itself calls actions.close(), i.e. infinite recursion
      -- (and it would leak into every other telescope picker in the session).
      map({ "i", "n" }, "<esc>", cancel)
      map("n", "q", cancel)
      map({ "i", "n" }, "<C-a>", actions.select_all)
      return true
    end,
  }):find()
  return true
end

-- ── fzf-lua ───────────────────────────────────────────────────────────────────

---@param refs table[]
---@param title string
---@param on_confirm fun(selected: table[])
---@param on_cancel fun()
---@return boolean
local function via_fzflua(refs, title, on_confirm, on_cancel)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return false end

  -- fzf-lua's builtin previewer auto-detects the ripgrep/vimgrep
  -- "file:line:col:text" line shape, so entries are plain strings.
  local lines, by_line = {}, {}
  for _, r in ipairs(refs) do
    local line = string.format("%s:%d:1:%s", r.file, r.line, r.display)
    lines[#lines + 1] = line
    by_line[line] = r
  end

  fzf.fzf_exec(lines, {
    prompt      = title .. "> ",
    fzf_opts    = { ["--multi"] = true },
    keymap      = { fzf = { ["ctrl-a"] = "select-all" } },
    actions = {
      -- A non-"default" action key makes fzf-lua add it to fzf's `--expect`
      -- list (see actions.lua's `M.expect`), so Esc is reported as a real
      -- keypress instead of silently exiting with no callback at all.
      ["esc"] = function(_selected, _o) on_cancel() end,
      ["default"] = function(selected)
        local chosen = {}
        for _, s in ipairs(selected or {}) do
          local r = by_line[s]
          if r then chosen[#chosen + 1] = r end
        end
        on_confirm(chosen)
      end,
    },
  })
  return true
end

-- ── Quickfix fallback ─────────────────────────────────────────────────────────

---@type { refs: table[], on_confirm: fun(selected: table[]) }|nil
local _qf_pending = nil

---@param refs table[]
---@param title string
---@param on_confirm fun(selected: table[])
local function via_quickfix(refs, title, on_confirm)
  local items = {}
  for _, r in ipairs(refs) do
    items[#items + 1] = { filename = r.file, lnum = r.line, text = r.display }
  end
  vim.fn.setqflist(items, "r")
  vim.fn.setqflist({}, "a", { title = title })
  vim.cmd("copen")
  _qf_pending = { refs = refs, on_confirm = on_confirm }
  vim.notify(
    "[filetree] References in the quickfix list. Delete lines (e.g. `dd`) for "
      .. "references you do NOT want cleaned up, then run `:Filetree mdrefs confirm`.\n"
      .. "To back out instead: `:Filetree mdrefs cancel`.",
    vim.log.levels.INFO
  )
end

---Confirm the quickfix-fallback flow: whatever remains in the quickfix list
---(after the user pruned unwanted lines) is treated as the selection.
---No-op when there's no pending quickfix picker.
function M.qf_confirm()
  if not _qf_pending then return end
  local pending = _qf_pending
  _qf_pending = nil

  local remaining, kept = vim.fn.getqflist(), {}
  for _, item in ipairs(remaining) do
    local ok, name = pcall(vim.api.nvim_buf_get_name, item.bufnr)
    if ok then
      local key = path.slashify(name)
      for _, r in ipairs(pending.refs) do
        if path.slashify(r.file) == key and r.line == item.lnum then
          kept[#kept + 1] = r
          break
        end
      end
    end
  end

  pcall(vim.cmd, "cclose")
  pending.on_confirm(kept)
end

---Back out of the quickfix-fallback flow without confirming anything.
function M.qf_cancel()
  if not _qf_pending then return end
  _qf_pending = nil
  pcall(vim.cmd, "cclose")
end

-- ── Public API ────────────────────────────────────────────────────────────────

---@class FiletreeRefsPickerOpts
---@field prefer? "auto"|"telescope"|"fzf-lua"|"quickfix"
---@field title?  string

---Show `refs` in a picker and let the user choose a subset.
---@param refs table[]  {file, line, target, display}[]
---@param opts FiletreeRefsPickerOpts|nil
---@param on_confirm fun(selected: table[])  Called with the chosen subset (never on cancel).
---@param on_cancel fun()  Called when the user backs out without confirming.
function M.pick(refs, opts, on_confirm, on_cancel)
  opts = opts or {}
  local title  = opts.title or "References"
  local prefer = opts.prefer or "auto"

  if prefer == "telescope" then
    if not via_telescope(refs, title, on_confirm, on_cancel) then
      vim.notify("[filetree] telescope.nvim not available", vim.log.levels.WARN)
    end
    return
  end
  if prefer == "fzf-lua" then
    if not via_fzflua(refs, title, on_confirm, on_cancel) then
      vim.notify("[filetree] fzf-lua not available", vim.log.levels.WARN)
    end
    return
  end
  if prefer == "quickfix" then
    via_quickfix(refs, title, on_confirm)
    return
  end

  -- auto: telescope -> fzf-lua -> quickfix (always available, no plugin needed)
  if via_telescope(refs, title, on_confirm, on_cancel) then return end
  if via_fzflua(refs, title, on_confirm, on_cancel) then return end
  via_quickfix(refs, title, on_confirm)
end

return M
