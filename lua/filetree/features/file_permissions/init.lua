---@module 'filetree.features.file_permissions'
---@brief Show and modify POSIX file permissions from the tree.
---@description
--- POSIX-only: no-ops gracefully on Windows (platform check at runtime).
---
--- Features:
---   • EOL virtual text showing permission string (e.g. "-rw-r--r--").
---   • toggle_exec():  add or remove the user-execute bit (chmod +x / -x).
---   • chmod(mode):    set an arbitrary octal mode string ("755", "644").
---   • show_current(): floating window with `stat` or `ls -la` details.
---   • Refreshes extmarks on CursorHold in tree buffer.
---
--- Config:
---   enabled        boolean
---   show_inline    boolean  Render permission string as EOL virt_text (default false;
---                           can be noisy on large trees — enable explicitly).
---   hl_exec        string   Highlight for executable files (default "DiagnosticOk").
---   hl_default     string   Highlight for all other files  (default "Comment").
---   keymap_exec    string?  Toggle execute bit (default "gx").
---   keymap_chmod   string?  Interactive chmod prompt       (default "gX").
---   keymap_show    string?  Show stat details              (default "gP").
---
--- Commands (via :Filetree dispatcher):
---   :Filetree chmod <mode>      set mode for current node (e.g. :Filetree chmod 755)
---   :Filetree permissions show
---   :Filetree permissions exec  toggle execute bit

local notify   = require("filetree.util.notify").create("[filetree.file_permissions]")
local platform = require("filetree.util.platform")

local M = {}

---@type FiletreeFilePermissionsConfig
local _cfg = {
  enabled      = false,
  show_inline  = false,
  hl_exec      = "DiagnosticOk",
  hl_default   = "Comment",
  keymap_exec  = "gx",
  keymap_chmod = "gX",
  keymap_show  = "gP",
}

---@type FiletreeAdapter?
local _adapter = nil

local _ns = vim.api.nvim_create_namespace("filetree_file_permissions")

-- ── Platform guard ────────────────────────────────────────────────────────────

local function is_posix()
  return not platform.is_windows()
end

-- ── Permission helpers ────────────────────────────────────────────────────────

---@param path string
---@param cb fun(perm: string?)
local function get_perms(path, cb)
  if not is_posix() then cb(nil); return end
  -- Use stat -c %A on Linux, stat -f %Sp on macOS
  vim.system({ "stat", "-c", "%A", "--", path }, { text = true }, function(r)
    if r.code == 0 and r.stdout and r.stdout ~= "" then
      cb(vim.trim(r.stdout)); return
    end
    -- macOS fallback
    vim.system({ "stat", "-f", "%Sp", "--", path }, { text = true }, function(r2)
      cb(r2.code == 0 and r2.stdout and vim.trim(r2.stdout) or nil)
    end)
  end)
end

local function is_exec(perm_str)
  -- Check if user-execute bit is set (position 4 in "-rwxr-xr-x")
  return perm_str and perm_str:sub(4, 4) == "x" or false
end

local function run_chmod(mode, path, cb)
  if not is_posix() then notify.warn("chmod: POSIX only"); return end
  vim.system({ "chmod", mode, "--", path }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        notify.error("chmod failed: " .. (result.stderr or ""))
      else
        if cb then cb() end
      end
    end)
  end)
end

-- ── Inline rendering ──────────────────────────────────────────────────────────

local function render(bufnr)
  if not _cfg.show_inline then return end
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, _ns, 0, -1)
  if not _adapter then return end

  local nodes = _adapter.get_visible_nodes and _adapter.get_visible_nodes() or {}
  for _, node in ipairs(nodes) do
    if not node.path or not node.line then goto continue end
    local line = node.line - 1
    local path = node.path

    get_perms(path, function(perm)
      if not perm then return end
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      local hl = is_exec(perm) and _cfg.hl_exec or _cfg.hl_default
      pcall(vim.api.nvim_buf_set_extmark, bufnr, _ns, line, -1, {
        virt_text     = { { " " .. perm, hl } },
        virt_text_pos = "eol",
        priority      = 70,
      })
    end)
    ::continue::
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.toggle_exec()
  if not is_posix() then notify.warn("toggle_exec: POSIX only"); return end
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end

  get_perms(node.path, function(perm)
    local mode = is_exec(perm) and "-x" or "+x"
    run_chmod(mode, node.path, function()
      local verb = mode == "+x" and "Executable" or "Non-executable"
      notify.info(verb .. ": " .. vim.fn.fnamemodify(node.path, ":t"))
      if _adapter and _adapter.refresh then _adapter.refresh() end
    end)
  end)
end

function M.chmod(mode)
  if not mode or mode == "" then
    vim.ui.input({ prompt = "chmod mode (e.g. 755): " }, function(input)
      if input and input ~= "" then M.chmod(input) end
    end)
    return
  end
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end
  run_chmod(mode, node.path, function()
    notify.info("chmod " .. mode .. ": " .. vim.fn.fnamemodify(node.path, ":t"))
    if _adapter and _adapter.refresh then _adapter.refresh() end
  end)
end

function M.show_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  if not node or not node.path then notify.warn("No node under cursor"); return end

  local cmd = is_posix()
    and { "ls", "-la", "--color=never", "--", node.path }
    or  { "cmd", "/c", "dir", "/Q", node.path }

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      local lines = vim.split(result.stdout or "(no output)", "\n", { plain = true })
      while lines[#lines] == "" do table.remove(lines) end

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false

      local width  = math.min(72, vim.o.columns - 4)
      local height = math.min(#lines, 10)
      local win    = vim.api.nvim_open_win(buf, true, {
        relative = "editor", style = "minimal", border = "rounded",
        width = width, height = height,
        row   = math.floor((vim.o.lines - height) / 2),
        col   = math.floor((vim.o.columns - width) / 2),
        title = " " .. vim.fn.fnamemodify(node.path, ":t") .. " ",
        title_pos = "center",
      })
      local opts = { buffer = buf, nowait = true, silent = true }
      vim.keymap.set("n", "q",     function() vim.api.nvim_win_close(win, true) end, opts)
      vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, opts)
    end)
  end)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeFilePermissionsConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_file_permissions", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = _augroup,
    pattern = { "neo-tree", "NvimTree" },
    callback = function(ev)
      render(ev.buf)
      local buf = ev.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local function km(key, fn, desc)
          if key then
            vim.keymap.set("n", key, fn, { buffer = buf, silent = true, desc = desc })
          end
        end
        km(_cfg.keymap_exec,  M.toggle_exec,  "Filetree: toggle execute bit")
        km(_cfg.keymap_chmod, function() M.chmod(nil) end, "Filetree: chmod prompt")
        km(_cfg.keymap_show,  M.show_current, "Filetree: show file permissions")
      end)
    end,
  })

  if _cfg.show_inline then
    vim.api.nvim_create_autocmd("CursorHold", {
      group = _augroup,
      callback = function()
        if not _adapter then return end
        local bufnr = _adapter.get_bufnr and _adapter.get_bufnr() or -1
        if bufnr > 0 then render(bufnr) end
      end,
    })
  end
end

function M.teardown()
  _adapter = nil
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
