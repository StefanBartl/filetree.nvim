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
---   :Filetree git stage
---   :Filetree filter foo bar
---   :Filetree reveal pause 2000
---   :Filetree archive zip

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

  -- ── git (git_status + git_actions) ──────────────────────────────────────────
  git = {
    refresh     = function(_) local f = ft("git_status");  if f then f.refresh()      end end,
    stage       = function(_) local f = ft("git_actions"); if f then f.stage_current()   end end,
    unstage     = function(_) local f = ft("git_actions"); if f then f.unstage_current() end end,
    stash       = function(_) local f = ft("git_actions"); if f then f.stash()        end end,
    ["stash-pop"] = function(_) local f = ft("git_actions"); if f then f.stash_pop()  end end,
    log         = function(_) local f = ft("git_actions"); if f then f.log_current()  end end,
  },

  -- ── bookmarks ───────────────────────────────────────────────────────────────
  bookmarks = {
    show  = function(_) local f = ft("bookmarks"); if f then f.show()      end end,
    clear = function(_) local f = ft("bookmarks"); if f then f.clear_all() end end,
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

  -- ── recent ──────────────────────────────────────────────────────────────────
  recent = {
    [""] = function(_) local f = ft("recent_files"); if f then f.show()  end end,
    clear = function(_) local f = ft("recent_files"); if f then f.clear() end end,
  },

  -- ── notes ───────────────────────────────────────────────────────────────────
  notes = {
    show  = function(_) local f = ft("notes"); if f then f.toggle_current() end end,
    clear = function(_) local f = ft("notes"); if f then f.clear_all()      end end,
  },

  -- ── size ────────────────────────────────────────────────────────────────────
  size = {
    refresh = function(_) local f = ft("size_info"); if f then f.refresh() end end,
  },

  -- ── terminal ────────────────────────────────────────────────────────────────
  terminal = function(_) local f = ft("open_terminal"); if f then f.open_current() end end,

  -- ── rename ──────────────────────────────────────────────────────────────────
  rename = function(_) local f = ft("rename_batch"); if f then f.open() end end,

  -- ── template ────────────────────────────────────────────────────────────────
  template = function(_) local f = ft("create_from_template"); if f then f.open_current() end end,

  -- ── symlink ─────────────────────────────────────────────────────────────────
  symlink = {
    follow = function(_) local f = ft("symlink"); if f then f.follow()         end end,
    create = function(_) local f = ft("symlink"); if f then f.create_current() end end,
  },

  -- ── reveal ──────────────────────────────────────────────────────────────────
  -- :Filetree reveal           → reveal current buffer
  -- :Filetree reveal pause [ms]
  -- :Filetree reveal resume
  reveal = {
    [""] = function(_)   local f = ft("auto_reveal"); if f then f.reveal_current()              end end,
    pause  = function(a) local f = ft("auto_reveal"); if f then f.pause(tonumber(a[1]) or 2000) end end,
    resume = function(_) local f = ft("auto_reveal"); if f then f.resume()                      end end,
  },

  -- ── archive ─────────────────────────────────────────────────────────────────
  archive = {
    zip     = function(_) local f = ft("archive"); if f then f.zip_current()     end end,
    tar     = function(_) local f = ft("archive"); if f then f.tar_current()     end end,
    extract = function(_) local f = ft("archive"); if f then f.extract_current() end end,
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

  -- ── color_labels ─────────────────────────────────────────────────────────────
  label = {
    set   = function(a)
      local f = ft("color_labels"); if not f then return end
      local arg = a[1]
      if not arg then f.pick_current()
      elseif tonumber(arg) then f.set_current(tonumber(arg))
      else f.set_by_name(arg) end
    end,
    clear = function(_) local f = ft("color_labels"); if f then f.clear_current() end end,
    list  = function(_) local f = ft("color_labels"); if f then f.show_list()    end end,
  },

  -- ── jump_list ────────────────────────────────────────────────────────────────
  jump = {
    back    = function(_) local f = ft("jump_list"); if f then f.back()    end end,
    forward = function(_) local f = ft("jump_list"); if f then f.forward() end end,
    list    = function(_) local f = ft("jump_list"); if f then f.show()    end end,
    clear   = function(_) local f = ft("jump_list"); if f then f.clear()   end end,
  },

  -- ── outline ──────────────────────────────────────────────────────────────────
  outline = function(_) local f = ft("outline"); if f then f.show_current() end end,

  -- ── compare_dirs ─────────────────────────────────────────────────────────────
  compare = {
    marked  = function(_) local f = ft("compare_dirs"); if f then f.compare_marked()  end end,
    current = function(_) local f = ft("compare_dirs"); if f then f.compare_current() end end,
  },

  -- ── pin_node ─────────────────────────────────────────────────────────────────
  pin = {
    toggle = function(_) local f = ft("pin_node"); if f then f.toggle_current() end end,
    show   = function(_) local f = ft("pin_node"); if f then f.show()           end end,
    clear  = function(_) local f = ft("pin_node"); if f then f.clear_all()      end end,
  },

  -- ── workspace ────────────────────────────────────────────────────────────────
  workspace = {
    switch = function(_)  local f = ft("workspace"); if f then f.switch()        end end,
    add    = function(a)  local f = ft("workspace"); if f then f.add(a[1])       end end,
    remove = function(a)  local f = ft("workspace"); if f then f.remove(a[1])    end end,
    list   = function(_)
      local f = ft("workspace"); if not f then return end
      local roots = f.list()
      if #roots == 0 then vim.notify("[filetree] Workspace empty", vim.log.levels.INFO)
      else vim.notify("[filetree] Workspace:\n  " .. table.concat(roots, "\n  "), vim.log.levels.INFO) end
    end,
  },

  -- ── ignore_patterns ──────────────────────────────────────────────────────────
  ignore = {
    toggle = function(_)  local f = ft("ignore_patterns"); if f then f.toggle()      end end,
    clear  = function(_)  local f = ft("ignore_patterns"); if f then f.clear_all()   end end,
    add    = function(a)  local f = ft("ignore_patterns"); if f then f.add(table.concat(a, " ")) end end,
    list   = function(_)
      local f = ft("ignore_patterns"); if not f then return end
      local pats = f.get_patterns()
      if #pats == 0 then vim.notify("[filetree] No ignore patterns", vim.log.levels.INFO)
      else vim.notify("[filetree] Patterns:\n  " .. table.concat(pats, "\n  "), vim.log.levels.INFO) end
    end,
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

function M.setup()
  vim.api.nvim_create_user_command("Filetree", function(opts)
    dispatch(opts.args)
  end, {
    nargs    = "*",
    complete = complete,
    desc     = "filetree.nvim — unified command interface",
  })
end

function M.teardown()
  pcall(vim.api.nvim_del_user_command, "Filetree")
end

return M
