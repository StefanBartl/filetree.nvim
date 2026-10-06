---@module 'filetree.refs.usage'
--- Batched reference counting: "how often is each of these files referenced,
--- and where?" for a whole set of paths in ONE sweep.
---
--- `filetree.refs.scan` answers that for a single moved path and starts one
--- ripgrep run per (path, provider). That is right for a rename, wrong for a
--- report over a folder of hundreds of screenshots. This module reuses the
--- same provider plans (so "referenced" means exactly what the rest of the
--- engine means by it) but runs each provider's candidate search once with the
--- union of every path's needles, then verifies candidates file by file:
---
---   per provider:  union needles --rg--> candidate files
---   per candidate: per plan whose needle occurs in the file text
---                  -> plan.extract on only the lines holding that needle
---
--- Shared by `:Filetree references`, `:Filetree refs unused` and the `I` node
--- info section.

local registry = require("filetree.refs.registry")
local scan = require("filetree.refs.scan")
local pathutil = require("filetree.refs.pathutil")
local progress = require("filetree.util.progress")
local notify = require("filetree.util.notify").create("[filetree.refs]")

local M = {}

-- Candidate files verified per event-loop tick, so a sweep over a big tree
-- never freezes the editor (same reasoning as `scan`'s walk fallback).
local CHUNK_SIZE = 20

-- A sweep reads far more than one rename's scan does, so its ripgrep run gets
-- at least this long before it is killed (`scan.timeout_ms` is tuned for the
-- single-path case).
local MIN_TIMEOUT_MS = 15000

-- Walk-fallback cap for a sweep (the default `scan.max_files` suits one rename).
local MIN_WALK_FILES = 50000

---@class FiletreeRefUsage
---@field count integer      Number of reference sites (several in one file count several times).
---@field refs  FiletreeRef[]  Sorted by file, line, column.
---@field files string[]     Distinct referencing files, in the order of `refs`.

---@class FiletreeRefUsageMeta
---@field providers     string[]  Providers that took part.
---@field files_scanned integer   Candidate files that were verified.
---@field cancelled     boolean   The user cancelled the progress indicator; results are partial.

---@internal
---@param lowered string  Already-lowercased haystack.
---@param needles string[]  Already-lowercased needles.
---@return boolean
local function has_needle(lowered, needles)
  for _, n in ipairs(needles) do
    if lowered:find(n, 1, true) then return true end
  end
  return false
end

---@internal
---@param needles string[]
---@return string[]
local function lowered(needles)
  local out = {}
  for i, n in ipairs(needles) do
    out[i] = n:lower()
  end
  return out
end

---@internal
---Verify one candidate file against every plan of its provider group.
---@param group table
---@param file string
---@param out table<string, FiletreeRefUsage>
---@param seen table<string, boolean>
local function verify_file(group, file, out, seen)
  local lines = scan.lines_of(file)
  if not lines then return end
  local text = table.concat(lines, "\n"):lower()

  for _, entry in ipairs(group.plans) do
    -- A file never counts as referencing itself.
    if not pathutil.same(file, entry.path) and has_needle(text, entry.lneedles) then
      for lineno, line in ipairs(lines) do
        if has_needle(line:lower(), entry.lneedles) then
          local ok, found = pcall(entry.plan.extract, file, lineno, line)
          if not ok then
            notify.debug(
              string.format("provider '%s' failed in %s: %s", group.provider.name, file, found)
            )
          else
            for _, r in ipairs(found or {}) do
              local key = table.concat({ entry.path, r.file, r.line, r.col }, "\0")
              if not seen[key] then
                seen[key] = true
                local bucket = out[entry.path].refs
                bucket[#bucket + 1] = r
              end
            end
          end
        end
      end
    end
  end
end

---@internal
---Group the plans of every enabled provider: one group per provider holding
---its plans plus the union of their needles and extensions.
---@param paths string[]
---@param root string
---@param cfg FiletreeRefsConfig
---@return table[]
local function build_groups(paths, root, cfg)
  local refs = require("filetree.refs")
  local groups = {}
  for _, provider in ipairs(registry.enabled(cfg)) do
    local group = { provider = provider, plans = {}, needles = {}, exts = {} }
    local seen_needle, seen_ext = {}, {}
    for _, path in ipairs(paths) do
      local ok, plan = pcall(provider.plan, path, refs.context(path, { root = root }))
      if ok and plan then
        group.plans[#group.plans + 1] =
          { path = path, plan = plan, lneedles = lowered(plan.needles) }
        for _, n in ipairs(plan.needles) do
          local k = n:lower()
          if not seen_needle[k] then
            seen_needle[k] = true
            group.needles[#group.needles + 1] = n
          end
        end
        for _, e in ipairs(plan.extensions) do
          if not seen_ext[e] then
            seen_ext[e] = true
            group.exts[#group.exts + 1] = e
          end
        end
      elseif not ok then
        notify.debug(string.format("provider '%s' failed to plan: %s", provider.name, plan))
      end
    end
    if #group.plans > 0 then groups[#groups + 1] = group end
  end
  return groups
end

---Count the references to every path in `paths`.
---
---`cb(by_path, meta)` receives one `FiletreeRefUsage` per input path (a
---path nobody references still gets an entry with `count = 0`). It always
---runs asynchronously except for an empty `paths`.
---
---Runs regardless of the `refs.enabled` / `refs.on_*` switches, which govern
---the rewrite-on-mutation direction; only `refs.providers` decides which
---languages count, so a report never silently goes blind.
---@param paths string[]  Files (not directories).
---@param opts? { root?: string }
---@param cb fun(by_path: table<string, FiletreeRefUsage>, meta: FiletreeRefUsageMeta)
function M.count(paths, opts, cb)
  opts = opts or {}
  local refs = require("filetree.refs")
  local cfg = refs.config()

  ---@type table<string, FiletreeRefUsage>
  local out = {}
  for _, p in ipairs(paths) do
    out[p] = { count = 0, refs = {}, files = {} }
  end
  ---@type FiletreeRefUsageMeta
  local meta = { providers = {}, files_scanned = 0, cancelled = false }
  if #paths == 0 then return cb(out, meta) end

  local root = opts.root or refs.resolve_root(paths[1])
  local groups = build_groups(paths, root, cfg)
  local scan_cfg = vim.tbl_deep_extend("force", cfg, {
    scan = {
      timeout_ms = math.max((cfg.scan and cfg.scan.timeout_ms) or 0, MIN_TIMEOUT_MS),
      -- A count must not read a dead ripgrep as "no references", nor stop at
      -- the rename-sized walk cap: both would report referenced files as unused.
      strict = true,
      max_files = math.max((cfg.scan and cfg.scan.max_files) or 0, MIN_WALK_FILES),
    },
  })

  local seen = {}

  local function finish()
    for _, u in pairs(out) do
      table.sort(u.refs, function(a, b)
        if a.file ~= b.file then return a.file < b.file end
        if a.line ~= b.line then return a.line < b.line end
        return a.col < b.col
      end)
      local files, in_files = {}, {}
      for _, r in ipairs(u.refs) do
        if not in_files[r.file] then
          in_files[r.file] = true
          files[#files + 1] = r.file
        end
      end
      u.files = files
      u.count = #u.refs
    end
    cb(out, meta)
  end

  local gi = 0
  local function next_group()
    gi = gi + 1
    local group = groups[gi]
    if not group then return finish() end
    meta.providers[#meta.providers + 1] = group.provider.name

    scan.candidates(root, group.needles, group.exts, scan_cfg, function(files)
      local total = #files
      local h = total > CHUNK_SIZE
          and progress.create({ title = "[filetree.refs] " .. group.provider.name })
        or nil
      local i = 0

      local function step()
        if h and h.cancelled then
          meta.cancelled = true
          return finish()
        end
        local last = math.min(i + CHUNK_SIZE, total)
        for j = i + 1, last do
          verify_file(group, files[j], out, seen)
        end
        meta.files_scanned = meta.files_scanned + (last - i)
        i = last
        if h then h:update({ text = "counting references…", current = i, total = total }) end
        if i < total then return vim.schedule(step) end
        if h then h:finish(string.format("%d file(s) checked", total)) end
        next_group()
      end

      step()
    end)
  end

  next_group()
end

return M
