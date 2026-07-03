---@module 'filetree.features.compare_dirs'
---@brief Compare two directories and show differences in quickfix.
---@description
--- Selects two directories (via marks or interactive prompt) and produces
--- a diff summary. Three backends in order of preference:
---   1. External visual diff tool (meld / beyond compare / delta)
---   2. `diff -rq dir1 dir2`  → quickfix list
---   3. Builtin Lua file-list comparison (no external deps)
---
--- Marks integration: if exactly two marked paths are directories,
--- compare them directly. Otherwise prompt for the second directory.
---
--- Config:
---   enabled         boolean
---   prefer          "auto"|"meld"|"bc"|"delta"|"builtin"
---   keymap          string?  Key in tree (default "cd").
---   open_quickfix   boolean  Auto-open quickfix after builtin diff (default true).
---
--- Commands (via :Filetree dispatcher):
---   :Filetree compare marked
---   :Filetree compare current

local notify = require("filetree.util.notify").create("[filetree.compare_dirs]")

local map = require("filetree.util.map")
local au  = require("filetree.util.autocmd")
local M = {}

---@type FiletreeCompareDirsConfig
local _cfg = {
  enabled       = false,
  prefer        = "auto",
  keymap        = "cd",
  open_quickfix = true,
}

---@type FiletreeAdapter?
local _adapter = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function is_dir(p)
  return p and vim.fn.isdirectory(p) == 1
end

local function get_two_dirs_from_marks()
  local ok, marks = require("filetree.features").load("marks")
  if not ok or not marks then return nil, nil end
  local all = marks.get_all() or {}
  local dirs = {}
  for _, p in ipairs(all) do
    if is_dir(p) then dirs[#dirs + 1] = p end
  end
  if #dirs >= 2 then return dirs[1], dirs[2] end
  return nil, nil
end

-- ── Backends ──────────────────────────────────────────────────────────────────

local function has_cmd(name)
  return vim.fn.executable(name) == 1
end

local function open_visual_tool(tool, dir1, dir2)
  vim.system({ tool, dir1, dir2 }, { detach = true })
end

local function diff_builtin(dir1, dir2)
  -- Enumerate files in both dirs recursively
  local function list_files(base)
    local out = {}
    local function scan(rel)
      local full = base .. "/" .. rel
      local entries = vim.fn.readdir(full)
      for _, e in ipairs(entries) do
        local child_rel = rel == "" and e or (rel .. "/" .. e)
        local child_full = base .. "/" .. child_rel
        if vim.fn.isdirectory(child_full) == 1 then
          scan(child_rel)
        else
          out[child_rel] = true
        end
      end
    end
    scan("")
    return out
  end

  local f1 = list_files(dir1)
  local f2 = list_files(dir2)
  local all_keys = {}
  for k in pairs(f1) do all_keys[k] = true end
  for k in pairs(f2) do all_keys[k] = true end

  local qf = {}
  local sorted = vim.tbl_keys(all_keys)
  table.sort(sorted)

  for _, rel in ipairs(sorted) do
    local only_in, status
    if f1[rel] and not f2[rel] then
      only_in = dir1; status = "only in A"
    elseif not f1[rel] and f2[rel] then
      only_in = dir2; status = "only in B"
    else
      -- Both exist – compare content
      local a = table.concat(vim.fn.readfile(dir1 .. "/" .. rel), "\n")
      local b = table.concat(vim.fn.readfile(dir2 .. "/" .. rel), "\n")
      if a ~= b then status = "DIFFER" end
    end

    if status then
      qf[#qf + 1] = {
        filename = only_in and (only_in .. "/" .. rel) or (dir1 .. "/" .. rel),
        lnum = 1, col = 1,
        text = string.format("[%s] %s", status, rel),
      }
    end
  end

  if #qf == 0 then
    notify.info("Directories are identical")
    return
  end

  vim.fn.setqflist({}, "r", {
    title = string.format("compare: %s  ↔  %s", vim.fn.fnamemodify(dir1, ":t"), vim.fn.fnamemodify(dir2, ":t")),
    items = qf,
  })
  if _cfg.open_quickfix then vim.cmd("copen") end
  notify.info(string.format("%d difference(s) found", #qf))
end

local function diff_external_cmd(dir1, dir2)
  vim.system({ "diff", "-rq", "--", dir1, dir2 }, { text = true }, function(result)
    vim.schedule(function()
      local lines = vim.split(result.stdout or "", "\n", { plain = true, trimempty = true })
      if #lines == 0 then
        notify.info("Directories are identical")
        return
      end
      local qf = {}
      for _, line in ipairs(lines) do
        qf[#qf + 1] = { filename = dir1, lnum = 1, col = 1, text = line }
      end
      vim.fn.setqflist({}, "r", {
        title = "compare dirs",
        items = qf,
      })
      if _cfg.open_quickfix then vim.cmd("copen") end
      notify.info(string.format("%d line(s) of diff output", #lines))
    end)
  end)
end

-- ── Core ──────────────────────────────────────────────────────────────────────

local function do_compare(dir1, dir2)
  if not is_dir(dir1) then notify.warn("Not a directory: " .. (dir1 or "?")); return end
  if not is_dir(dir2) then notify.warn("Not a directory: " .. (dir2 or "?")); return end

  local prefer = _cfg.prefer
  if prefer == "meld"  and has_cmd("meld")  then open_visual_tool("meld",  dir1, dir2); return end
  if prefer == "bc"    and has_cmd("bcompare") then open_visual_tool("bcompare", dir1, dir2); return end
  if prefer == "auto" then
    if has_cmd("meld")     then open_visual_tool("meld",     dir1, dir2); return end
    if has_cmd("bcompare") then open_visual_tool("bcompare", dir1, dir2); return end
  end
  -- diff -rq or builtin fallback
  if has_cmd("diff") then diff_external_cmd(dir1, dir2)
  else diff_builtin(dir1, dir2) end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Compare two marked directories.
function M.compare_marked()
  local d1, d2 = get_two_dirs_from_marks()
  if not d1 then notify.warn("Mark exactly two directories first"); return end
  do_compare(d1, d2)
end

---Compare current node's directory with a prompted path.
function M.compare_current()
  local dir1
  if _adapter then
    local node = _adapter.get_current_node()
    if node and node.path then
      dir1 = is_dir(node.path) and node.path or vim.fn.fnamemodify(node.path, ":h")
    end
  end
  dir1 = dir1 or vim.fn.getcwd()
  vim.ui.input({ prompt = "Compare with dir: ", default = dir1, completion = "dir" }, function(dir2)
    if dir2 and dir2 ~= "" then do_compare(dir1, dir2) end
  end)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeCompareDirsConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg     = vim.tbl_deep_extend("force", _cfg, config)
  _adapter = adapter

  if _augroup then au.del_group(_augroup) end
  _augroup = au.group("filetree_compare_dirs", true)

  if _cfg.keymap then
    au.acmd("FileType", {
      group   = _augroup,
      pattern = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          map("n", _cfg.keymap, M.compare_current, {
            buffer = buf, silent = true, desc = "Filetree: compare dirs",
          })
        end)
      end,
    })
  end
end

function M.teardown()
  _adapter = nil
  if _augroup then
    au.del_group(_augroup)
    _augroup = nil
  end
end

return M
