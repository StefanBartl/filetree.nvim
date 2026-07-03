---@module 'filetree.features.git_blame'
---@brief Show last-commit info for the tree node under the cursor.
---@description
--- Two modes:
---   inline — virtual text appended at the end of the cursor line in the
---             tree buffer. Updates on CursorMoved (debounced).
---   float  — floating window with full `git log -1 --stat` output.
---
--- Always uses `git log -1` for the node's path so it works for both files
--- and directories (shows last commit touching anything inside the dir).
---
--- Config:
---   enabled       boolean
---   mode          "inline"|"float"|"both"  Default "inline".
---   debounce_ms   integer    CursorMoved debounce (default 300ms).
---   keymap        string?    Key to toggle float (default "gb").
---   hl_group      string     Highlight for inline text (default "Comment").
---   format        string     strftime-compatible age format string.
---                            Tokens: {hash} {author} {date} {subject}
---                            Default: " {hash} {author} · {date}"
---
--- Commands (via :Filetree dispatcher):
---   :Filetree blame

local notify = require("filetree.util.notify").create("[filetree.git_blame]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeGitBlameConfig
local _cfg = {
  enabled     = false,
  mode        = "inline",
  debounce_ms = 300,
  keymap      = "gB",
  hl_group    = "Comment",
  format      = " {hash} {author} · {date}",
}

---@type FiletreeAdapter?
local _adapter = nil

local _ns    = vim.api.nvim_create_namespace("filetree_git_blame")
local _timer = nil
local _last_path = nil

-- ── Git helpers ───────────────────────────────────────────────────────────────

local function uv() return vim.uv or vim.loop end

local function git_last_commit(path, cb)
  vim.system(
    { "git", "log", "-1",
      "--pretty=format:%h\x1f%an\x1f%ar\x1f%s",
      "--", path },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 or not result.stdout or result.stdout == "" then
          cb(nil); return
        end
        local parts = vim.split(vim.trim(result.stdout), "\x1f", { plain = true })
        cb({
          hash    = parts[1] or "",
          author  = parts[2] or "",
          date    = parts[3] or "",
          subject = parts[4] or "",
        })
      end)
    end
  )
end

local function format_inline(info)
  return _cfg.format
    :gsub("{hash}",    info.hash)
    :gsub("{author}",  info.author)
    :gsub("{date}",    info.date)
    :gsub("{subject}", info.subject)
end

-- ── Inline extmark ────────────────────────────────────────────────────────────

local function clear_inline(bufnr)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, _ns, 0, -1)
end

local function set_inline(bufnr, line0, text)
  clear_inline(bufnr)
  pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, line0, -1, {
    virt_text     = { { text, _cfg.hl_group } },
    virt_text_pos = "eol",
    priority      = 80,
  })
end

-- ── Float window ─────────────────────────────────────────────────────────────

local function show_float(path)
  vim.system(
    { "git", "log", "-1", "--stat", "--", path },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then notify.warn("git log failed"); return end
        local lines = vim.split(result.stdout or "", "\n", { plain = true })
        while lines[#lines] == "" do table.remove(lines) end
        if #lines == 0 then notify.info("No commits for " .. vim.fn.fnamemodify(path, ":t")); return end

        local width  = math.min(80, vim.o.columns - 4)
        local height = math.min(#lines, 20)
        local buf    = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modifiable = false
        vim.bo[buf].filetype   = "git"

        local win = vim.api.nvim_open_win(buf, true, {
          relative = "editor", style = "minimal", border = "rounded",
          width = width, height = height,
          row   = math.floor((vim.o.lines - height) / 2),
          col   = math.floor((vim.o.columns - width) / 2),
          title = " git log: " .. vim.fn.fnamemodify(path, ":t") .. " ",
          title_pos = "center",
        })
        local opts = { buffer = buf, nowait = true, silent = true }
        map("n", "q",     function() vim.api.nvim_win_close(win, true) end, opts)
        map("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, opts)
      end)
    end
  )
end

-- ── Inline update (debounced) ─────────────────────────────────────────────────

local function update_inline()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then return end
  local path = node.path
  if path == _last_path then return end
  _last_path = path

  local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
  local winid = _adapter.get_winid and _adapter.get_winid() or -1
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  local cursor_line = 0
  if winid > 0 and vim.api.nvim_win_is_valid(winid) then
    cursor_line = vim.api.nvim_win_get_cursor(winid)[1] - 1
  end

  git_last_commit(path, function(info)
    if not info then clear_inline(bufnr); return end
    set_inline(bufnr, cursor_line, format_inline(info))
  end)
end

local function schedule_update()
  if _timer then pcall(function() _timer:stop() end) end
  _timer = uv().new_timer()
  _timer:start(_cfg.debounce_ms, 0, vim.schedule_wrap(function()
    _timer = nil
    update_inline()
  end))
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.show_float_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end
  show_float(node.path)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeGitBlameConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_git_blame", true)

  local do_inline = _cfg.mode == "inline" or _cfg.mode == "both"

  if do_inline then
    au.acmd("CursorMoved", {
      group    = _augroup,
      callback = function()
        if not _adapter then return end
        local winid = _adapter.get_winid and _adapter.get_winid() or -1
        if winid > 0 and vim.api.nvim_get_current_win() == winid then
          schedule_update()
        end
      end,
    })
  end

  if _cfg.keymap then
    au.acmd("FileType", {
      group   = _augroup,
      pattern = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap, M.show_float_current, {
            buffer = buf, silent = true, desc = "Filetree: git blame / last commit",
          })
        end)
      end,
    })
  end
end

function M.teardown()
  _adapter  = nil
  _last_path = nil
  if _timer then pcall(function() _timer:stop(); _timer:close() end); _timer = nil end
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
