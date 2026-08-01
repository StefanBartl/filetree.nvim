---@module 'filetree.features.create_from_template'
---@brief Create files from user-defined templates with variable substitution.
---@description
--- Templates are stored as plain files in a configurable directory
--- (default: stdpath("data")/filetree/templates/).
--- Each file in that directory is a template; its filename is the template
--- name shown in the picker.
---
--- Template variables (replaced on creation):
---   ${filename}   Basename of the new file (without extension)
---   ${ext}        Extension of the new file (without dot)
---   ${date}       Current date in YYYY-MM-DD format
---   ${year}       Current year
---   ${month}      Current month (01-12)
---   ${day}        Current day (01-31)
---   ${time}       Current time in HH:MM:SS
---   ${author}     Value of config.author or $USER/$USERNAME
---   ${module}     For a destination under a real lua/ directory: the canonical
---                 Lua module path via lib.nvim.lua_ls.get_module_path (the
---                 same resolver filetree's own lua_require_copy is built on
---                 — not reimplemented here), e.g. lua/plugins/test.lua ->
---                 "plugins.test". Otherwise a generic dotted path from the
---                 project root (any language) — e.g. src/foo/Bar.cs ->
---                 "src.foo.Bar".
---
--- Workflow:
---   1. Press "A" in tree (the smart_create "a" counterpart) — or :Filetree template
---   2. Enter the new filename FIRST
---   3. The template picker is filtered to templates matching that filename's
---      extension (e.g. "foo.lua" only offers .lua templates); if none match,
---      the full list is shown instead
---   4. Pick a template — the destination path is already known at this
---      point, so ${module} (and every other variable) resolves against it
---   5. File is created in the current node's directory and opened
---
--- Adding your own templates: drop a file into the template directory (default
--- stdpath("data")/filetree/templates/) — its filename becomes the template
--- name — or call M.add_template(name, content) programmatically.
---
--- Reordering: while the picker is open (query empty, i.e. not mid-filter),
--- <M-j>/<M-k> move the highlighted template down/up. The order is persisted
--- to a `.order.json` sidecar in the template directory, so it survives
--- restarts; a never-reordered or newly-added template is appended
--- alphabetically after the ones with an explicit position.
---
--- Keymap (default): "A" in tree buffer.

local notify  = require("filetree.util.notify").create("[filetree.create_from_template]")
local path_u  = require("filetree.util.path")
local bufutil = require("filetree.util.buffer")
local json    = require("lib.nvim.fs.json")

local map    = require("filetree.util.map")
local tree_attach = require("filetree.util.tree_attach")
local ui_select = require("filetree.util.select")
local ui_confirm = require("filetree.util.confirm")

-- Reorderable picker: only available when lib.nvim's ui kit's lower-level
-- `picker` component is present (it exposes the results window/cursor the
-- move keymaps need — the simple `filetree.util.select` shim does not).
-- Falls back to the plain ui_select flow (no reordering) otherwise.
local _ok_kit, kit = pcall(require, "lib.nvim.ui.kit")
local has_kit_picker = _ok_kit and type(kit) == "table" and type(kit.picker) == "function"

local M = {}

---@type FiletreeCreateFromTemplateConfig
local _cfg = {
  enabled      = false,
  keymap       = "A",
  template_dir = nil,  -- defaults to stdpath("data")/filetree/templates/
  author       = nil,  -- defaults to $USER/$USERNAME
  open_after   = true, -- open file in editor after creation
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Template directory ────────────────────────────────────────────────────────

local function template_dir()
  local dir = _cfg.template_dir
    or (vim.fn.stdpath("data") .. "/filetree/templates")
  if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end
  return dir
end

---Directory of templates shipped WITH filetree.nvim itself (one per common
---language), found via 'runtimepath' rather than a path computed relative to
---this file — works regardless of how the plugin was installed (git clone,
---local dir checkout, symlink, …), same mechanism ftplugin/syntax/doc rely
---on. Namespaced under lua/filetree/… (not a generic top-level "templates/")
---so an unrelated plugin can never collide with it. Cached: 'rtp' doesn't
---change mid-session in normal use, and this is the picker's hot path.
---@return string?
local _builtin_dir
local function builtin_dir()
  if _builtin_dir ~= nil then
    return _builtin_dir ~= false and _builtin_dir or nil
  end
  local found = vim.api.nvim_get_runtime_file("lua/filetree/assets/templates/", true)
  _builtin_dir = found[1] or false
  return found[1]
end

-- ── Variable substitution ─────────────────────────────────────────────────────

local function author()
  if _cfg.author and _cfg.author ~= "" then return _cfg.author end
  return vim.env.USER or vim.env.USERNAME or "unknown"
end

-- The canonical, already-implemented path -> Lua module resolver (also what
-- filetree's own lua_require_copy feature is conceptually doing by hand) —
-- reuse it rather than re-deriving the same "/lua/…/init.lua -> foo.bar"
-- logic a third time.
local get_lua_module_path = require("lib.nvim.lua_ls.get_module_path")

---Dotted module/namespace path for `${module}`.
---
---For a destination genuinely under a `lua/` directory, defers entirely to
---`lib.nvim.lua_ls.get_module_path` — the shared resolver, not reimplemented
---here. That function returns nil for anything not under `lua/` (by design:
---it is Lua-specific), in which case this falls back to a generic path
---relative to the project root (any language) — e.g. src/foo/Bar.cs ->
---"src.foo.Bar" — stripping whatever extension the destination actually has.
---@param abs_path string
---@return string
local function module_path(abs_path)
  local canonical = get_lua_module_path(abs_path)
  if canonical then return canonical end

  local ok_pr, pr = require("filetree.features").load("project_root")
  local root
  if ok_pr and type(pr.find) == "function" then
    root = pr.find(abs_path)
  end
  root = root or vim.fn.getcwd()  -- project_root.find() may return nil (no marker found)
  local rel = path_u.relative(abs_path, root)
  rel = rel:gsub("%.[^./\\]+$", "")  -- strip whatever extension is actually there
  return (rel:gsub("[/\\]", "."):gsub("%.init$", ""))  -- parens: gsub returns (str, count)
end

local function substitute(content, new_path)
  local base = vim.fn.fnamemodify(new_path, ":t:r")  -- name without ext
  local ext  = vim.fn.fnamemodify(new_path, ":e")
  local now  = os.date("*t")
  local vars = {
    filename = base,
    ext      = ext,
    date     = os.date("%Y-%m-%d"),
    year     = tostring(now.year),
    month    = string.format("%02d", now.month),
    day      = string.format("%02d", now.day),
    time     = os.date("%H:%M:%S"),
    author   = author(),
    module   = module_path(new_path),
  }
  return (content:gsub("%${(%w+)}", function(key)
    return vars[key] or ("${" .. key .. "}")
  end))
end

-- ── Display order (persisted, user-reorderable) ─────────────────────────────────
-- A sidecar file rather than encoding order in filenames, so reordering never
-- touches the template files themselves. `.`-prefixed so it never lists as a
-- template itself (vim.fn.readdir has no dotfile-hiding on Windows, hence the
-- explicit skip in raw_templates() below rather than relying on that).

local function order_file()
  return template_dir() .. "/.order.json"
end

---@return string[]
local function load_order()
  local ok, decoded = pcall(json.read, order_file())
  if not ok or type(decoded) ~= "table" or type(decoded.order) ~= "table" then
    return {}
  end
  return decoded.order
end

---@param order string[]
---@return boolean ok
local function save_order(order)
  local ok = pcall(json.write, order_file(), { order = order })
  return ok == true
end

-- ── Template list ─────────────────────────────────────────────────────────────

---List template files (name + path) directly in `dir`, alphabetical.
---@param dir string
---@param builtin boolean
---@return {name:string, path:string, builtin:boolean}[]
local function scan_dir(dir, builtin)
  local ok, entries = pcall(vim.fn.readdir, dir)
  if not ok then return {} end
  local tmpl = {}
  for _, e in ipairs(entries) do
    if not e:match("^%.") then  -- skip .order.json and any other dotfile
      local full = dir .. "/" .. e
      if vim.fn.filereadable(full) == 1 then
        tmpl[#tmpl + 1] = { name = e, path = full, builtin = builtin }
      end
    end
  end
  table.sort(tmpl, function(a, b) return a.name < b.name end)
  return tmpl
end

---Templates on disk, alphabetical — the order-agnostic source of truth for
---"what templates exist". `list_templates()` below layers the persisted
---display order on top of this.
---
---Merges the built-in templates shipped with filetree.nvim (one per common
---language, read-only — never written to by add_template/M.move) with the
---user's own template_dir(). A user template with the SAME NAME as a
---built-in shadows it entirely (name and content), the usual override-layer
---pattern — so customizing a shipped default is just: drop a same-named file
---into your own template_dir().
---@return {name:string, path:string, builtin:boolean}[]
local function raw_templates()
  local user = scan_dir(template_dir(), false)

  local bdir = builtin_dir()
  local builtin = bdir and scan_dir(bdir, true) or {}

  local by_name, out = {}, {}
  for _, t in ipairs(user) do
    by_name[t.name] = t
  end
  for _, t in ipairs(builtin) do
    if not by_name[t.name] then
      by_name[t.name] = t
    end
  end
  for name in pairs(by_name) do out[#out + 1] = name end
  table.sort(out)

  local tmpl = {}
  for _, name in ipairs(out) do
    tmpl[#tmpl + 1] = by_name[name]
  end
  return tmpl
end

---Templates in display order: the persisted order first (skipping any entry
---that no longer exists on disk), then any template without an explicit
---position — new or never-reordered — appended alphabetically.
---@return {name:string, path:string, builtin:boolean?}[]
local function list_templates()
  local all = raw_templates()
  local by_name = {}
  for _, t in ipairs(all) do by_name[t.name] = t end

  local ordered, seen = {}, {}
  for _, name in ipairs(load_order()) do
    local t = by_name[name]
    if t and not seen[name] then
      ordered[#ordered + 1] = t
      seen[name] = true
    end
  end
  for _, t in ipairs(all) do
    if not seen[t.name] then
      ordered[#ordered + 1] = t
      seen[t.name] = true
    end
  end
  return ordered
end

---Move `name` up (-1) or down (+1) one position in the persisted display
---order. Normalizes the order to the full current template list first (so a
---template that was never explicitly ordered can still be moved), then
---writes the swapped order back. No-op (false) at either boundary or when
---`name` doesn't exist.
---@param name string
---@param delta -1|1
---@return boolean moved
function M.move(name, delta)
  local current = list_templates()
  local names, at = {}, nil
  for i, t in ipairs(current) do
    names[i] = t.name
    if t.name == name then at = i end
  end
  if not at then return false end

  local target = at + delta
  if target < 1 or target > #names then return false end

  names[at], names[target] = names[target], names[at]
  return save_order(names)
end

-- ── Creation ──────────────────────────────────────────────────────────────────

local function create_from(tmpl_path, dest_path)
  local ok, lines = pcall(vim.fn.readfile, tmpl_path)
  if not ok then
    notify.error("Cannot read template: " .. tmpl_path)
    return false
  end
  local content   = table.concat(lines, "\n")
  local rendered  = substitute(content, dest_path)
  local rendered_lines = {}
  for l in (rendered .. "\n"):gmatch("([^\n]*)\n") do
    rendered_lines[#rendered_lines + 1] = l
  end
  -- Remove trailing empty line added by the split
  if rendered_lines[#rendered_lines] == "" and #rendered_lines > 1 then
    table.remove(rendered_lines)
  end

  local rc = vim.fn.writefile(rendered_lines, dest_path)
  if rc ~= 0 then
    notify.error("Could not write: " .. dest_path)
    return false
  end
  return true
end

-- ── Picker flow ───────────────────────────────────────────────────────────────

---Display label: built-ins get a marker so the merged list makes clear which
---entries ship with the plugin vs. the user's own (or an override of one).
---@param t {name:string, builtin:boolean?}
---@return string
local function display_name(t)
  return t.builtin and (t.name .. "  [builtin]") or t.name
end

---Plain, non-reorderable picker (fallback when the ui kit's `picker`
---component is unavailable — e.g. lib.nvim absent, or the kit's own mount
---failed).
---@param templates {name:string, path:string, builtin:boolean?}[]
---@param on_select fun(tmpl: {name:string, path:string, builtin:boolean?})
local function pick_template_plain(templates, on_select)
  ui_select(templates, {
    prompt = "Templates",
    format_item = display_name,
  }, function(tmpl)
    if tmpl then on_select(tmpl) end
  end)
end

---Reorderable picker: <CR> selects (as before), <M-j>/<M-k> move the
---highlighted template down/up while the filter is empty — persisted
---immediately via M.move(). Filtering by typing still works (kit.picker's
---own query→on_change), it just can't be combined with reordering in the
---same keystroke, since "move" is only well-defined against the full,
---unfiltered order.
---@param templates {name:string, path:string, builtin:boolean?}[]
---@param on_select fun(tmpl: {name:string, path:string, builtin:boolean?})
local function pick_template_reorderable(templates, on_select)
  local list = templates

  local function render(handle)
    local lines = {}
    for _, t in ipairs(list) do lines[#lines + 1] = display_name(t) end
    handle.set_results(lines)
  end

  -- Forward-declared: `on_change` below closes over `handle`, but on the
  -- right-hand side of a `local handle = kit.picker(...)` statement the new
  -- local isn't in scope yet — that nested closure would resolve `handle` as
  -- a global (always nil) instead of an upvalue. Declaring it first, then
  -- assigning, makes the closures capture the real local.
  local handle
  handle = kit.picker({
    on_change = function(query)
      if query == "" then
        list = templates
      else
        local q = query:lower()
        list = vim.tbl_filter(function(t)
          return t.name:lower():find(q, 1, true) ~= nil
        end, templates)
      end
      render(handle)
    end,
    on_submit = function(idx)
      local tmpl = list[idx]
      if tmpl then on_select(tmpl) end
    end,
  })
  if not handle then
    pick_template_plain(templates, on_select)
    return
  end
  render(handle)

  local function current_idx()
    local results = handle.slots.results
    if not (results and results:is_valid()) then return nil end
    return vim.api.nvim_win_get_cursor(results.winid)[1]
  end

  local function move(delta)
    if handle.query() ~= "" then
      notify.info("Clear the filter to reorder templates")
      return
    end
    local idx = current_idx()
    local tmpl = idx and list[idx]
    if not tmpl or not M.move(tmpl.name, delta) then return end

    templates = list_templates()  -- reload: reflects the just-persisted order
    list = templates
    render(handle)

    local target = math.max(1, math.min(idx + delta, #list))
    local results = handle.slots.results
    if results and results:is_valid() then
      pcall(vim.api.nvim_win_set_cursor, results.winid, { target, 0 })
    end
  end

  local mo = { buffer = handle.slots.prompt.bufnr, nowait = true }
  map({ "i", "n" }, "<M-j>", function() move(1)  end, mo, "Filetree: move template down")
  map({ "i", "n" }, "<M-k>", function() move(-1) end, mo, "Filetree: move template up")
end

---@param templates {name:string, path:string, builtin:boolean?}[]
---@param on_select fun(tmpl: {name:string, path:string, builtin:boolean?})
local function pick_template(templates, on_select)
  if #templates == 0 then
    notify.warn("No templates in: " .. template_dir())
    return
  end

  if has_kit_picker then
    pick_template_reorderable(templates, on_select)
  else
    pick_template_plain(templates, on_select)
  end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Templates whose OWN extension matches `filename`'s extension. Falls back
---to the full unfiltered list when nothing matches (a filter that leaves
---nothing to pick from is a dead end, not a useful restriction) or when
---`filename` has no extension at all.
---@param templates {name:string, path:string, builtin:boolean?}[]
---@param filename string
---@return {name:string, path:string, builtin:boolean?}[]
local function filter_by_extension(templates, filename)
  local ext = vim.fn.fnamemodify(filename, ":e")
  if ext == "" then return templates end

  local matched = {}
  for _, t in ipairs(templates) do
    if vim.fn.fnamemodify(t.name, ":e") == ext then
      matched[#matched + 1] = t
    end
  end
  return #matched > 0 and matched or templates
end

---Prompt for a filename, then open the (extension-filtered) template picker,
---then create the file — in that order, so both the picker and ${module}
---substitution see the real destination path.
---@param dest_dir string  Absolute destination directory.
function M.open(dest_dir)
  require("lib.nvim.ui.kit").input({
    title = "New file (in " .. vim.fn.fnamemodify(dest_dir, ":t") .. "): ",
    on_submit = function(name)
      if not name or name == "" then return end
      name = path_u.slashify(name)  -- accept "/" or "\" if creating into a subdir
      local dest = dest_dir .. "/" .. name

      local templates = filter_by_extension(list_templates(), name)

      pick_template(templates, function(tmpl)
        local function proceed()
          if create_from(tmpl.path, dest) then
            notify.info("Created: " .. name .. " (from " .. tmpl.name .. ")")
            if _adapter and _adapter.refresh then pcall(_adapter.refresh) end
            if _cfg.open_after then
              -- Open in a real editor window, never the tree window itself (loading
              -- a buffer into the tree's own window fights its window-management
              -- autocmds and can hang Neovim — see smart_create/duplicate_node).
              local tree_win = _adapter and _adapter.get_winid and _adapter.get_winid()
              local win = bufutil.find_editor_win(tree_win)
              if win then vim.api.nvim_set_current_win(win) else vim.cmd("vsplit") end
              vim.cmd("edit " .. vim.fn.fnameescape(dest))
            end
          end
        end

        if vim.fn.filereadable(dest) == 1 then
          ui_confirm({
            question = "File exists. Overwrite?",
            on_choice = function(yes) if yes then proceed() end end,
          })
        else
          proceed()
        end
      end)
    end,
  })
end

---Open picker at the current tree node's directory.
function M.open_current()
  if not _adapter then return end
  local node = _adapter.get_current_node()
  local dir  = node
    and (node.type == "directory" and node.path or vim.fn.fnamemodify(node.path, ":h"))
    or vim.fn.getcwd()
  M.open(dir)
end

---Return all available templates.
---@return {name:string, path:string, builtin:boolean?}[]
function M.list()
  return list_templates()
end

---Add a template programmatically.
---@param name    string  Template filename.
---@param content string  Template content.
function M.add_template(name, content)
  local dir  = template_dir()
  local path = dir .. "/" .. name
  local lines = {}
  for l in (content .. "\n"):gmatch("([^\n]*)\n") do lines[#lines+1] = l end
  vim.fn.writefile(lines, path)
  notify.info("Template added: " .. name)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config FiletreeCreateFromTemplateConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _cfg.keymap then
    tree_attach.on_attach(function(buf)
      map("n", _cfg.keymap, M.open_current, {
        buffer = buf, silent = true, desc = "Filetree: create from template",
      })
    end)
  end
end

function M.teardown()
  _adapter = nil
end

return M
