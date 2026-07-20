---@module 'filetree.commands'
---@brief Central :Filetree command dispatcher with tab-completion.
---@description
--- Registers a single :Filetree command (built via lib.nvim.usercmd.composer)
--- that dispatches to all feature modules. TREE is the single source of
--- truth for dispatch, <Tab> completion, and M.command_paths(); composer
--- routes are derived from it, not duplicated.
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
local composer = require("lib.nvim.usercmd.composer")

local M = {}

-- ── Feature accessor (lazy, only works after setup()) ─────────────────────────

local function ft(name)
  local ok, main = pcall(require, "filetree")
  if not ok then return nil end
  return main.feature(name)
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

  -- ── mdrefs (trash's quickfix references-picker fallback) ────────────────────
  mdrefs = {
    confirm = function(_) require("filetree.util.refs_picker").qf_confirm() end,
    cancel  = function(_) require("filetree.util.refs_picker").qf_cancel()  end,
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

-- ── TREE → composer routes ───────────────────────────────────────────────────
-- TREE stays the single source of truth (also read by M.command_paths()
-- below, unchanged); routes are derived from it fresh on every M.setup()
-- rather than duplicated by hand, so the two can never drift.
--
-- Composer's tree.walk greedily consumes literal path tokens and stops at
-- the deepest node reached; if that node has its OWN route (registered from
-- a `[""]` default key here) it dispatches there with whatever tokens didn't
-- match as ctx.rest — which is exactly the original dispatch()'s "unknown
-- sub-command falls through to the default handler with all args" behavior
-- for filter/reveal/mdlink/search/info/require (all `[""]`-bearing groups),
-- reproduced for free by composer's own walk, not re-implemented here.

---@param node table
---@param path string[]
---@param routes table[]
local function walk_tree(node, path, routes)
  for key, val in pairs(node) do
    local child_path = path
    if key ~= "" then
      child_path = vim.deepcopy(path)
      child_path[#child_path + 1] = key
    end
    if type(val) == "function" then
      routes[#routes + 1] = { path = child_path, run = function(ctx) val(ctx.rest) end }
    elseif type(val) == "table" then
      walk_tree(val, child_path, routes)
    end
  end
end

---Build the composer route list from TREE. "find" is special-cased for
--- directory-typed <Tab> completion (the one spot the original completion
--- special-cased beyond generic tree-key walking); every other leaf just
--- forwards ctx.rest into the unchanged TREE function, exactly like before.
---@return table[]
local function build_routes()
  local routes = {}
  local tree_without_find = vim.tbl_extend("force", {}, TREE)
  tree_without_find.find = nil
  walk_tree(tree_without_find, {}, routes)

  routes[#routes + 1] = {
    path = { "find" },
    args = { { name = "dir", type = "DIR", optional = true } },
    desc = "Find files (optionally scoped to a directory)",
    run = function(ctx)
      local args = {}
      if ctx.args.dir ~= nil then args[1] = ctx.args.dir end
      for _, t in ipairs(ctx.rest) do args[#args + 1] = t end
      TREE.find(args)
    end,
  }
  return routes
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type string[]
local _registered_commands = {}

---@param cfg FiletreeCommandConfig?
function M.setup(cfg)
  -- Re-setup is idempotent: composer's usercmd.create overwrites an existing
  -- command of the same name safely, but cfg can change the NAME between
  -- calls (custom cfg.name/aliases) — without tearing down first, a renamed
  -- setup() would leave the old name(s) registered and stale alongside the
  -- new one. So: drop whatever this module registered last time, then
  -- recreate under (possibly different) names.
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

  -- One shared route list across every name (same pattern as replacer.nvim's
  -- :Replace/:Replacer) — composer.verb() only reads the spec to build a
  -- route tree, it doesn't mutate it, so reusing one table across multiple
  -- verb registrations is safe.
  local spec = { desc = "filetree.nvim — unified command interface", routes = build_routes() }

  local seen = {}
  for _, cmd_name in ipairs(names) do
    if not seen[cmd_name] then
      seen[cmd_name] = true
      composer.verb(cmd_name, spec)
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
