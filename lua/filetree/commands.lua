---@module 'filetree.commands'
---@brief Central :Filetree command dispatcher with tab-completion.
---@description
--- Registers a single :Filetree command that dispatches to all feature
--- modules. Tab-completion is context-aware (depth-aware sub-command list).
---
--- Usage:
---   :Filetree <subcommand> [sub-subcommand] [args...]
---
--- Examples:
---   :Filetree trash undo
---   :Filetree git refresh
---   :Filetree filter foo bar
---   :Filetree reveal pause 2000

local usercmd = require("filetree.util.usercmd")

local M = {}

-- ── Feature accessor (lazy, only works after setup()) ─────────────────────────

local function ft(name)
  local ok, main = pcall(require, "filetree")
  if not ok then return nil end
  return main.feature(name)
end

local function warn(msg)
  vim.notify("[filetree] " .. msg, vim.log.levels.WARN)
end

-- ── Command tree ──────────────────────────────────────────────────────────────
-- Leaf values: function(rest_args: string[])
-- Interior values: table of sub-commands
-- Special key "": default action when no sub-command is given/matched

---@type table<string, any>
local TREE = {

  -- ── trash ───────────────────────────────────────────────────────────────────
  trash = {
    undo      = function(_) local f = ft("trash"); if f then f.undo_last()      end end,
    history   = function(_) local f = ft("trash"); if f then f.show_history()   end end,
    ["dry-run"] = function(_) local f = ft("trash"); if f then f.toggle_dry_run() end end,
  },

  -- ── marks ───────────────────────────────────────────────────────────────────
  marks = {
    clear = function(_) local f = ft("marks"); if f then f.clear_all()        end end,
    show  = function(_) local f = ft("marks"); if f then f.show()             end end,
    all   = function(_) local f = ft("marks"); if f then f.mark_all_visible() end end,
  },

  -- ── diff ────────────────────────────────────────────────────────────────────
  diff = {
    marked = function(_) local f = ft("diff"); if f then f.diff_marked() end end,
    close  = function(_) local f = ft("diff"); if f then f.close()       end end,
  },

  -- ── git (git_status) ─────────────────────────────────────────────────────────
  git = {
    refresh = function(_) local f = ft("git_status"); if f then f.refresh() end end,
  },

  -- ── safety ──────────────────────────────────────────────────────────────────
  safety = {
    list      = function(_) local f = ft("safety"); if f then f.list_backups()   end end,
    ["dry-run"] = function(_) local f = ft("safety"); if f then f.toggle_dry_run() end end,
  },

  -- ── session ─────────────────────────────────────────────────────────────────
  session = {
    save    = function(_) local f = ft("session"); if f then f.save()    end end,
    restore = function(_) local f = ft("session"); if f then f.restore() end end,
    clear   = function(_) local f = ft("session"); if f then f.clear()   end end,
  },

  -- ── find ────────────────────────────────────────────────────────────────────
  -- :Filetree find [dir]
  find = function(args)
    local f = ft("find_files")
    if f then f.find(args[1]) end
  end,

  -- ── grep ────────────────────────────────────────────────────────────────────
  -- :Filetree grep [pattern]
  grep = function(args)
    local f = ft("grep_in_dir")
    if f then f.grep(nil, #args > 0 and table.concat(args, " ") or nil) end
  end,

  -- ── filter ──────────────────────────────────────────────────────────────────
  -- :Filetree filter           → open floating input
  -- :Filetree filter <query>   → apply query directly
  -- :Filetree filter clear     → clear current filter
  filter = {
    [""] = function(args)
      local f = ft("filter"); if not f then return end
      if #args > 0 then f.apply(table.concat(args, " "))
      else f.enter() end
    end,
    clear = function(_) local f = ft("filter"); if f then f.clear() end end,
  },

  -- ── size ────────────────────────────────────────────────────────────────────
  size = {
    refresh = function(_) local f = ft("size_info"); if f then f.refresh() end end,
  },

  -- ── rename ──────────────────────────────────────────────────────────────────
  rename = function(_) local f = ft("rename_batch"); if f then f.open() end end,

  -- ── template ────────────────────────────────────────────────────────────────
  template = function(_) local f = ft("create_from_template"); if f then f.open_current() end end,

  -- ── reveal ──────────────────────────────────────────────────────────────────
  -- :Filetree reveal           → reveal current buffer
  -- :Filetree reveal pause [ms]
  -- :Filetree reveal resume
  reveal = {
    [""] = function(_)   local f = ft("auto_reveal"); if f then f.reveal_current()              end end,
    pause  = function(a) local f = ft("auto_reveal"); if f then f.pause(tonumber(a[1]) or 2000) end end,
    resume = function(_) local f = ft("auto_reveal"); if f then f.resume()                      end end,
  },

  -- ── resize ──────────────────────────────────────────────────────────────────
  -- :Filetree resize [width]
  resize = function(args)
    local f = ft("auto_resize")
    if f then f.set_width(tonumber(args[1])) end
  end,

  -- ── watcher ─────────────────────────────────────────────────────────────────
  watcher = {
    enter = function(a) local f = ft("watcher_quarantine"); if f then f.enter(tonumber(a[1])) end end,
    exit  = function(_) local f = ft("watcher_quarantine"); if f then f.exit()               end end,
  },

  -- ── copy-move ───────────────────────────────────────────────────────────────
  clipboard = {
    show  = function(_) local f = ft("copy_move"); if f then f.show()       end end,
    clear = function(_) local f = ft("copy_move"); if f then f.clear()      end end,
    copy  = function(_) local f = ft("copy_move"); if f then f.stage_copy() end end,
    cut   = function(_) local f = ft("copy_move"); if f then f.stage_cut()  end end,
    paste = function(_) local f = ft("copy_move"); if f then f.paste()      end end,
  },

  -- ── breadcrumbs ──────────────────────────────────────────────────────────────
  breadcrumbs = {
    update = function(_) local f = ft("breadcrumbs"); if f then
      local path = vim.api.nvim_buf_get_name(0)
      if path ~= "" then f.update(path) end
    end end,
  },

  -- ── open_with ────────────────────────────────────────────────────────────────
  open = {
    system = function(_)   local f = ft("open_with"); if f then f.open_system()  end end,
    pick   = function(_)   local f = ft("open_with"); if f then f.pick()         end end,
    app    = function(a)   local f = ft("open_with"); if f then f.open_app(a[1] or "") end end,
  },

  -- ── open_variants ─────────────────────────────────────────────────────────────
  openas = {
    vsplit = function(_) local f = ft("open_variants"); if f then f.open_vsplit() end end,
    split  = function(_) local f = ft("open_variants"); if f then f.open_split()  end end,
    tabnew = function(_) local f = ft("open_variants"); if f then f.open_tabnew() end end,
    badd   = function(_) local f = ft("open_variants"); if f then f.open_badd()   end end,
  },

  -- ── markdown_links ─────────────────────────────────────────────────────────────
  mdlink = {
    [""]      = function(_) local f = ft("markdown_links"); if f then f.link_current()    end end,
    recursive = function(_) local f = ft("markdown_links"); if f then f.link_recursive()  end end,
    marked    = function(_) local f = ft("markdown_links"); if f then f.link_from_marked() end end,
  },

  -- ── hooks_api ─────────────────────────────────────────────────────────────
  hooks = {
    events = function(_)
      local f = ft("hooks_api"); if not f then return end
      local evs = f.events()
      if #evs == 0 then vim.notify("[filetree] No hooks registered", vim.log.levels.INFO)
      else
        local lines = {}
        for _, ev in ipairs(evs) do lines[#lines+1] = string.format("  %s (%d)", ev, f.count(ev)) end
        vim.notify("[filetree] Hooks:\n" .. table.concat(lines, "\n"), vim.log.levels.INFO)
      end
    end,
    clear = function(a)
      local f = ft("hooks_api"); if not f then return end
      f.clear(a[1])
      vim.notify("[filetree] Hooks cleared" .. (a[1] and (" for: " .. a[1]) or ""), vim.log.levels.INFO)
    end,
  },

  -- ── smart_rename ─────────────────────────────────────────────────────────────
  smartrename = function(_) local f = ft("smart_rename"); if f then f.rename_current() end end,

  -- ── path_copy ─────────────────────────────────────────────────────────────────
  copy = {
    absolute = function(_) local f = ft("path_copy"); if f then f.copy_absolute() end end,
    relative = function(_) local f = ft("path_copy"); if f then f.copy_relative() end end,
    name     = function(_) local f = ft("path_copy"); if f then f.copy_name()     end end,
    dirname  = function(_) local f = ft("path_copy"); if f then f.copy_dirname()  end end,
    uri      = function(_) local f = ft("path_copy"); if f then f.copy_uri()      end end,
    line     = function(_) local f = ft("path_copy"); if f then f.copy_line()     end end,
    stem     = function(_) local f = ft("path_copy"); if f then f.copy_stem()     end end,
    pick     = function(_) local f = ft("path_copy"); if f then f.pick()          end end,
  },

  -- ── live_search ──────────────────────────────────────────────────────────────
  search = {
    [""]    = function(_) local f = ft("live_search"); if f then f.open()  end end,
    clear   = function(_) local f = ft("live_search"); if f then f.clear() end end,
  },

  -- ── smart_create ──────────────────────────────────────────────────────────────
  create = function(_) local f = ft("smart_create"); if f then f.create() end end,

  -- ── copy_file_list ────────────────────────────────────────────────────────────
  filelist = {
    files = {
      abs = function(_) local f = ft("copy_file_list"); if f then f.copy_files_abs() end end,
      rel = function(_) local f = ft("copy_file_list"); if f then f.copy_files_rel() end end,
    },
    dirs = {
      abs = function(_) local f = ft("copy_file_list"); if f then f.copy_dirs_abs() end end,
      rel = function(_) local f = ft("copy_file_list"); if f then f.copy_dirs_rel() end end,
    },
  },

  -- ── lua_require_copy ─────────────────────────────────────────────────────────
  require = {
    [""] = function(_)
      local f = ft("lua_require_copy"); if f then f.copy_require() end
    end,
    relative = function(_)
      local f = ft("lua_require_copy"); if f then f.copy_require_relative() end
    end,
  },

  -- ── tree_traverse ─────────────────────────────────────────────────────────────
  traverse = {
    up   = function(_) local f = ft("tree_traverse"); if f then f.up()   end end,
    down = function(_) local f = ft("tree_traverse"); if f then f.down() end end,
  },

  -- ── node_info ────────────────────────────────────────────────────────────────
  info = {
    [""] = function(_) local f = ft("node_info"); if f then f.show_current() end end,
    close = function(_) local f = ft("node_info"); if f then f.close() end end,
  },

  -- ── health ───────────────────────────────────────────────────────────────────
  health = function(_) vim.cmd("checkhealth filetree") end,
}

-- ── Dispatch ──────────────────────────────────────────────────────────────────

local function dispatch(args_str)
  local parts = {}
  for w in (args_str or ""):gmatch("%S+") do parts[#parts + 1] = w end

  if #parts == 0 then
    warn(":Filetree <subcommand> — try :Filetree<Tab>")
    return
  end

  local node = TREE[parts[1]]
  if node == nil then
    warn("Unknown command: " .. parts[1])
    return
  end

  -- Leaf: call directly with rest args
  if type(node) == "function" then
    local rest = {}
    for i = 2, #parts do rest[#rest + 1] = parts[i] end
    node(rest)
    return
  end

  -- Interior: look up sub-command
  local sub_key = parts[2]
  if sub_key == nil then
    -- No sub-command: invoke default "" if present
    if node[""] then
      node[""]({})
    else
      local keys = {}
      for k in pairs(node) do if k ~= "" then keys[#keys + 1] = k end end
      table.sort(keys)
      warn(string.format(":Filetree %s <%s>", parts[1], table.concat(keys, " | ")))
    end
    return
  end

  local sub = node[sub_key]
  if sub == nil then
    -- Unknown sub-command: fall through to default with all as args
    if node[""] then
      local rest = {}
      for i = 2, #parts do rest[#rest + 1] = parts[i] end
      node[""](rest)
    else
      warn(string.format("Unknown sub-command: %s %s", parts[1], sub_key))
    end
    return
  end

  local rest = {}
  for i = 3, #parts do rest[#rest + 1] = parts[i] end
  sub(rest)
end

-- ── Completion ────────────────────────────────────────────────────────────────

local function complete(arglead, cmdline, _cursorpos)
  -- Extract everything after ":Filetree " (or "Filetree ")
  local after = cmdline:match("^%S*Filetree%s+(.*)$") or ""
  local parts = {}
  for w in after:gmatch("%S+") do parts[#parts + 1] = w end

  -- Number of confirmed tokens (not counting arglead)
  local confirmed = arglead == "" and #parts or (#parts - 1)

  local function keys_of(tbl, prefix)
    local out = {}
    for k in pairs(tbl) do
      if k ~= "" and k:sub(1, #prefix) == prefix then
        out[#out + 1] = k
      end
    end
    table.sort(out)
    return out
  end

  if confirmed == 0 then
    return keys_of(TREE, arglead)
  end

  -- Navigate the tree with confirmed tokens
  local node = TREE[parts[1]]
  for i = 2, confirmed do
    if type(node) ~= "table" then return {} end
    node = node[parts[i]]
  end

  if type(node) == "table" then
    return keys_of(node, arglead)
  end

  -- For "find" and "resize", suggest directory/number
  if parts[1] == "find" and confirmed == 1 then
    return vim.fn.getcompletion(arglead, "dir")
  end

  return {}
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type string[]
local _registered_commands = {}

---@param cfg FiletreeCommandConfig?
function M.setup(cfg)
  -- Re-setup is idempotent: nvim_create_user_command errors (E174) if the
  -- command already exists, which a second require("filetree").setup() call
  -- in the same session would otherwise hit — so drop any commands this
  -- module registered before, then recreate.
  M.teardown()

  -- Determine name(s) to register.
  -- cfg.command = "Ft"                  → just :Ft
  -- cfg.command = { name="Ft", aliases={"Filetree"} } → :Ft and :Filetree
  local names = {}
  if type(cfg) == "string" then
    names[1] = cfg
  elseif type(cfg) == "table" then
    names[1] = cfg.name or "Filetree"
    for _, a in ipairs(cfg.aliases or { "Ft" }) do
      names[#names + 1] = a
    end
  else
    -- Out of the box: both :Filetree and the short :Ft alias work.
    names[1] = "Filetree"
    names[2] = "Ft"
  end

  local seen = {}
  for _, cmd_name in ipairs(names) do
    if not seen[cmd_name] then
      seen[cmd_name] = true
      usercmd.create(cmd_name, function(opts)
        dispatch(opts.args)
      end, {
        nargs    = "*",
        complete = complete,
        desc     = "filetree.nvim — unified command interface",
      })
      _registered_commands[#_registered_commands + 1] = cmd_name
    end
  end
end

function M.teardown()
  for _, cmd_name in ipairs(_registered_commands) do
    usercmd.del(cmd_name)
  end
  _registered_commands = {}
end

---Walk the command TREE and return every sub-command path as a string, sorted.
---The dispatcher's TREE is the single source of truth, so this never drifts from
---what is actually registered. Default-action (`""`) keys are skipped.
---@return string[]  e.g. { "trash undo", "git refresh", "marks show", … }
function M.command_paths()
  local out = {}
  local function walk(node, prefix)
    for key, val in pairs(node) do
      if key ~= "" then
        local path = prefix == "" and key or (prefix .. " " .. key)
        if type(val) == "table" then
          walk(val, path)
        else
          out[#out + 1] = path
        end
      end
    end
  end
  walk(TREE, "")
  table.sort(out)
  return out
end

return M
