---@module 'filetree.features.smart_create'
---@brief Enhanced file/directory creation with clipboard paste and LuaLS templates.

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
}
---@type FiletreeAdapter?
local _adapter = nil

local notify = require("filetree.util.notify").create("[filetree.smart_create]")

---Find the lua/ root above a path.
---@param path string
---@return string?
local function find_lua_root(path)
  local cur = path
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
---@param path string
---@return string
local function path_to_module(path)
  local lua_root = find_lua_root(path)
  if not lua_root then return path end
  local root_norm = lua_root:gsub("\\", "/"):gsub("/?$", "/")
  local rel = path:gsub("\\", "/"):gsub("^" .. vim.pesc(root_norm), "")
  return rel:gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")
end

---Write initial content to a new buffer and save.
---@param filepath string
---@param lines string[]
local function create_with_content(filepath, lines)
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
  if not _adapter then return vim.fn.getcwd() end
  local node = _adapter.get_current_node()
  if not node then return vim.fn.getcwd() end
  if node.type == "directory" then return node.path end
  return vim.fn.fnamemodify(node.path, ":h")
end

---Create a file or directory interactively.
function M.create()
  local parent = resolve_parent_dir()

  -- Show the parent directory in the prompt (relative to cwd) rather than
  -- pre-filling the absolute path — the user only types the new name.
  local display = vim.fn.fnamemodify(parent, ":~:.")
  if display == "" or display == "." then display = "./" else display = display .. "/" end

  vim.ui.input(
    { prompt = "Create in " .. display .. "  (append / for a directory): " },
    function(input)
      if not input or input == "" then return end

      local is_dir = input:sub(-1) == "/"
      local name   = input:gsub("/?$", "")  -- strip trailing slash for ops

      -- Relative names are created inside the parent dir; an absolute path (or
      -- Windows drive path) is honoured as-is.
      local target
      if name:match("^/") or name:match("^%a:[/\\]") then
        target = name
      else
        target = parent .. "/" .. name
      end
      target = (target:gsub("\\", "/"))

      if is_dir then
        -- Create directory
        local ok = vim.fn.mkdir(target, "p")
        if ok == 0 then
          notify.error("Failed to create directory: " .. target)
          return
        end
        notify.info("Created directory: " .. vim.fn.fnamemodify(target, ":~:."))

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
            vim.ui.select(
              { "Empty", "Paste clipboard" },
              { prompt = "Create " .. vim.fn.fnamemodify(target, ":t") .. " with:" },
              function(choice)
                if not choice then return end
                paste = choice == "Paste clipboard"
                local lines = build_template(target, paste)
                create_with_content(target, lines)
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
      vim.keymap.set("n", _cfg.keymap, function() M.create() end,
        { buffer = buf, desc = "filetree: smart create", silent = true })
    end

    local winid = adapter.get_winid and adapter.get_winid()
    if winid then
      set_km(vim.api.nvim_win_get_buf(winid))
    else
      vim.api.nvim_create_autocmd("FileType", {
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
