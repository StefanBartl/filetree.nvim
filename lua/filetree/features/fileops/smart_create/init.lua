---@module 'filetree.features.smart_create'
---@brief Enhanced file/directory creation with clipboard paste and LuaLS templates.

local map     = require("filetree.util.map")
local au      = require("filetree.util.autocmd")
local ui_select = require("filetree.util.select")
local path    = require("filetree.util.path")
local bufutil = require("filetree.util.buffer")
local M = {}

---@type FiletreeSmartCreateConfig
local _cfg = {
  enabled = false,
  keymap  = "a",
  -- LuaLS scaffolding for new files — all OFF by default (opt in per key):
  auto_module_annot   = false,  -- new .lua files get a `---@module '<derived>'` header
  auto_types_template = false,  -- files under an `@types` path get `---@meta` + `---@module`
  auto_init_lua       = false,  -- creating a directory also creates init.lua (with the header)
  ask_clipboard       = false,  -- if the clipboard is non-empty, offer to paste it into the file
  notify_level        = "verbose",  -- "verbose" | "short" | "off" — success message verbosity
}
---@type FiletreeAdapter?
local _adapter = nil

local notify = require("filetree.util.notify").create("[filetree.smart_create]")

---Find the lua/ root above a path.
---@param filepath string
---@return string?
local function find_lua_root(filepath)
  local cur = filepath
  while true do
    local parent = vim.fn.fnamemodify(cur, ":h")
    if parent == cur then break end
    local candidate = parent .. "/lua"
    local stat = vim.uv.fs_stat(candidate)
    if stat and stat.type == "directory" then
      return candidate
    end
    cur = parent
  end
  return vim.fn.stdpath("config") .. "/lua"
end

---Derive module path from an absolute file path.
---@param filepath string
---@return string
local function path_to_module(filepath)
  local lua_root = find_lua_root(filepath)
  if not lua_root then return filepath end
  local root_norm = path.slashify(lua_root):gsub("/?$", "/")
  local rel = path.slashify(filepath):gsub("^" .. vim.pesc(root_norm), "")
  return rel:gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")
end

---Show a success notification for a created file/directory, at the
---configured verbosity: "verbose" (default) names what was created, "short"
---is little more than the path, "off" is silent.
---@param kind "file"|"directory"
---@param target string  Absolute path of what was created.
local function notify_created(kind, target)
  local level = _cfg.notify_level or "verbose"
  if level == "off" then return end
  local rel = path.relative(target)
  if level == "short" then
    notify.info("Path: " .. rel)
  else
    notify.info("Created " .. kind .. ": " .. rel)
  end
end

-- ── "?" cheatsheet ────────────────────────────────────────────────────────────
-- vim.ui.input only ever hands back the *final* submitted string (no mid-typing
-- keystroke hooks — this must work with any vim.ui.input backend, not just the
-- builtin one), so "?" is a full input, not a live keypress: type "?" and press
-- <CR>. The cheatsheet closes on any key and re-opens the create prompt so the
-- user can immediately act on what they just read.

local CHEATSHEET_LINES = {
  " Smart create — type a name relative to the shown directory ",
  "",
  "  name.lua        create a file",
  "  name.lua/       create a directory (trailing / or \\)",
  "  sub/dir/name    missing subdirectories are created automatically",
  "  /abs/path       an absolute path (or C:\\... / C:/...) is used as-is",
  "  ?  <CR>         show this cheatsheet",
  "  <Esc> / empty   cancel",
}

---@param on_close fun()  Called after the cheatsheet window closes.
local function show_cheatsheet(on_close)
  local width = 0
  for _, l in ipairs(CHEATSHEET_LINES) do width = math.max(width, #l) end
  width = math.min(width + 2, math.floor(vim.o.columns * 0.9))
  local height = #CHEATSHEET_LINES

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, CHEATSHEET_LINES)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    style     = "minimal",
    border    = "rounded",
    width     = width,
    height    = height,
    row       = math.floor((vim.o.lines - height) / 2) - 2,
    col       = math.floor((vim.o.columns - width) / 2),
    title     = " smart_create help ",
    title_pos = "center",
  })

  local closed = false
  local function close()
    if closed then return end
    closed = true
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    if on_close then on_close() end
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  map("n", "q",     close, opts)
  map("n", "<Esc>", close, opts)
  map("n", "<CR>",  close, opts)
end

---Open `filepath` for editing in a real editor window — never in the tree
---window itself. Loading a new buffer into the tree's own window fights neo-
---tree's window-management autocmds (and this plugin's own layout_guard),
---which can spiral into an autocmd storm that looks like Neovim hanging.
---@return integer winid  The editor window now showing filepath.
local function open_editor_window()
  local tree_win = _adapter and _adapter.get_winid and _adapter.get_winid()
  local win = bufutil.find_editor_win(tree_win)
  if not win then
    -- No editor window yet: open one next to the tree instead of editing here.
    vim.cmd("vsplit")
    win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(win)
  return win
end

---Write initial content to a new buffer and save.
---@param filepath string
---@param lines string[]
local function create_with_content(filepath, lines)
  open_editor_window()
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  if #lines > 0 then
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.cmd("write")
  end
end

---Build template lines for a new file.
---@param filepath string
---@param paste_clipboard boolean
---@return string[]
local function build_template(filepath, paste_clipboard)
  if paste_clipboard then
    local clip = vim.fn.getreg("+")
    if clip and clip ~= "" then
      return vim.split(clip, "\n", { plain = true })
    end
  end

  local lines = {}

  -- LuaLS @types template
  if _cfg.auto_types_template and filepath:find("@types") then
    lines[#lines + 1] = "---@meta"
    local mod = path_to_module(filepath)
    lines[#lines + 1] = "---@module '" .. mod .. "'"
    lines[#lines + 1] = ""
    return lines
  end

  -- Module annotation for .lua files
  if _cfg.auto_module_annot and filepath:match("%.lua$") then
    local mod = path_to_module(filepath)
    lines[#lines + 1] = "---@module '" .. mod .. "'"
    lines[#lines + 1] = ""
  end

  return lines
end

---Get the directory to create in (current node's dir or cwd).
---@return string
local function resolve_parent_dir()
  if not _adapter then return path.slashify(vim.fn.getcwd()) end
  local node = _adapter.get_current_node()
  if not node then return path.slashify(vim.fn.getcwd()) end
  if node.type == "directory" then return path.slashify(node.path) end
  return path.parent(node.path)
end

---Create a file or directory interactively.
function M.create()
  local parent = resolve_parent_dir()

  -- Show the parent directory in the prompt (relative to cwd) rather than
  -- pre-filling the absolute path — the user only types the new name. Always
  -- displayed with "/" regardless of OS (see path.slashify).
  local display = path.relative(parent)
  if display == "" or display == "." then display = "./" else display = display .. "/" end

  vim.ui.input(
    { prompt = "Create in " .. display .. "  (/ = dir, ? = help): " },
    function(input)
      if not input or input == "" then return end

      if input == "?" then
        show_cheatsheet(M.create)
        return
      end

      -- Sanitize immediately: the user may type "/" or "\" — both are accepted,
      -- and everything from here on uses "/" (see path.slashify).
      input = path.slashify(input)

      local is_dir = input:sub(-1) == "/"
      local name   = input:gsub("/?$", "")  -- strip trailing slash for ops

      -- Relative names are created inside the parent dir; an absolute path (or
      -- Windows drive path) is honoured as-is.
      local target
      if name:match("^/") or name:match("^%a:/") then
        target = name
      else
        target = parent .. "/" .. name
      end

      if is_dir then
        -- Create directory
        local ok = vim.fn.mkdir(target, "p")
        if ok == 0 then
          notify.error("Failed to create directory: " .. target)
          return
        end
        notify_created("directory", target)

        -- Auto init.lua
        if _cfg.auto_init_lua then
          local init_path = target .. "/init.lua"
          local lines = build_template(init_path, false)
          create_with_content(init_path, lines)
        end
      else
        -- Create file — ensure parent directory exists
        local dir = vim.fn.fnamemodify(target, ":h")
        vim.fn.mkdir(dir, "p")

        local paste = false
        if _cfg.ask_clipboard then
          local clip = vim.fn.getreg("+")
          if clip and clip ~= "" then
            ui_select(
              { "Empty", "Paste clipboard" },
              { prompt = "Create " .. vim.fn.fnamemodify(target, ":t") .. " with:" },
              function(choice)
                if not choice then return end
                paste = choice == "Paste clipboard"
                local lines = build_template(target, paste)
                create_with_content(target, lines)
                notify_created("file", target)
                if _adapter and _adapter.refresh then
                  pcall(_adapter.refresh)
                end
              end
            )
            return
          end
        end

        local lines = build_template(target, false)
        create_with_content(target, lines)
        notify_created("file", target)
      end

      if _adapter and _adapter.refresh then
        pcall(_adapter.refresh)
      end
    end
  )
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param cfg FiletreeSmartCreateConfig
---@param adapter FiletreeAdapter
function M.setup(cfg, adapter)
  _cfg     = vim.tbl_deep_extend("force", _cfg, cfg or {})
  _adapter = adapter

  if _cfg.keymap then
    local function set_km(buf)
      map("n", _cfg.keymap, function() M.create() end,
        { buffer = buf, desc = "filetree: smart create", silent = true })
    end

    local winid = adapter.get_winid and adapter.get_winid()
    if winid then
      set_km(vim.api.nvim_win_get_buf(winid))
    else
      au.acmd("FileType", {
        pattern  = { "neo-tree", "NvimTree" },
        callback = function(ev)
          local buf = ev.buf
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then return end
            set_km(buf)
          end)
        end,
      })
    end
  end
end

function M.teardown()
  _adapter = nil
end

return M
