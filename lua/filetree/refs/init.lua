---@module 'filetree.refs'
--- Reference engine — the single place that knows "file X moves to Y, who
--- points at X, and how must that pointer read afterwards?".
---
--- Every filesystem mutation in filetree.nvim routes through here instead of
--- carrying its own copy of the scan/ask/rewrite dance:
---
---   smart_rename ─┐
---   copy_move   ──┼──►  filetree.refs  ──►  providers ──► confirm ──► apply
---   rename_batch ─┤     (scan/resolve)      (markdown,     (chooser,   (buffer
---   move        ──┤                          lua, python,   picker,     or disk,
---   trash       ──┘                          ts_js, …)      diff)       undoable)
---
--- Usage — always prefetch first, mutate second:
---
---   local handle = refs.prefetch({ old_path }, { op = "rename" })
---   -- ... user types a new name / navigates to a target ...
---   handle.await(function(result)
---     -- the scan is finished and saw the file at its OLD location
---     do_the_rename()
---     refs.handle_result(result, { [old_path] = new_path }, { op = "rename" })
---   end)
---
--- The prefetch/await split is what makes this race-free: the scan starts while
--- the file still exists and the mutation happens strictly inside the await
--- callback, so a reference can never be missed because the file moved out from
--- under the scanner.

local registry = require("filetree.refs.registry")
local scan = require("filetree.refs.scan")
local apply = require("filetree.refs.apply")
local ui = require("filetree.refs.ui")
local ftpath = require("filetree.util.path")
local notify = require("filetree.util.notify").create("[filetree.refs]")

local M = {}

M.registry = registry
M.apply = apply
M.ui = ui

-- ── Config ────────────────────────────────────────────────────────────────────

-- Shared with `filetree.config.DEFAULTS` (one table, two consumers — see
-- filetree/refs/DEFAULTS.lua) so a default can never mean one thing to
-- `setup({ refs = … })` and another to the engine itself.
---@type FiletreeRefsConfig
local DEFAULTS = require("filetree.refs.DEFAULTS")

---@type FiletreeRefsConfig
local _cfg = vim.deepcopy(DEFAULTS)

---@param cfg FiletreeRefsConfig?
function M.setup(cfg)
  _cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), cfg or {})
end

---@return FiletreeRefsConfig
function M.config()
  return _cfg
end

---Register an extra provider (see `filetree.refs.registry`).
---@param provider FiletreeRefProvider
---@return boolean ok, string? err
function M.register(provider)
  return registry.register(provider)
end

-- ── Built-in providers ────────────────────────────────────────────────────────
-- Registration order doubles as display order in the chooser's summary.

registry.register(require("filetree.refs.providers.markdown"))
registry.register(require("filetree.refs.providers.lua"))
registry.register(require("filetree.refs.providers.python"))
registry.register(require("filetree.refs.providers.ts_js"))

-- ── Mode helpers ──────────────────────────────────────────────────────────────

---The configured mode for an operation, honouring a per-call override.
---@param op "rename"|"move"|"delete"|"copy"
---@param override? "ask"|"auto"|"off"
---@return "ask"|"auto"|"off"
function M.mode(op, override)
  if override then return override end
  if not _cfg.enabled then return "off" end
  if op == "copy" then return _cfg.copy and _cfg.on_move or "off" end
  if op == "delete" then return _cfg.on_delete end
  if op == "move" then return _cfg.on_move end
  return _cfg.on_rename
end

---Whether a scan for `op` would do anything at all — checked by call sites
---before they pay for a prefetch.
---@param op "rename"|"move"|"delete"|"copy"
---@param override? "ask"|"auto"|"off"
---@return boolean
function M.active(op, override)
  return M.mode(op, override) ~= "off" and #registry.enabled(_cfg) > 0
end

-- ── Context ───────────────────────────────────────────────────────────────────

---@internal
---Search root for `path`: the nearest project root, or the cwd.
---@param path string
---@return string
local function resolve_root(path)
  if _cfg.scan and _cfg.scan.root == "cwd" then return vim.fn.getcwd() end
  local ok_pr, project_root = require("filetree.features").load("project_root")
  if ok_pr and project_root and type(project_root.find) == "function" then
    local ok_find, found = pcall(project_root.find, ftpath.parent(path))
    if ok_find and type(found) == "string" and found ~= "" then return found end
  end
  return vim.fn.getcwd()
end

---@internal
---@param path string
---@param opts? { root?: string }
---@return FiletreeRefCtx
local function make_ctx(path, opts)
  return {
    root = (opts and opts.root) or resolve_root(path),
    -- Computed while the path still exists — a moved-away directory would
    -- otherwise report as "not a directory" and silently disable the
    -- prefix matching every provider needs for a directory move.
    is_dir = vim.fn.isdirectory(path) == 1,
    cfg = _cfg,
  }
end

-- ── Scan ──────────────────────────────────────────────────────────────────────

---Start scanning for references to `paths` and return a handle whose
---`await(cb)` delivers the result — immediately when the scan already
---finished, else when it does.
---
---Call this the moment the user triggers the action (while the files still
---exist), and perform the mutation inside `await`.
---@param paths string[]
---@param opts? { op?: "rename"|"move"|"delete"|"copy", mode?: "ask"|"auto"|"off", root?: string }
---@return { await: fun(cb: fun(result: FiletreeRefScanResult)) }
function M.prefetch(paths, opts)
  opts = opts or {}
  local state = { done = false, result = nil, waiters = {} }

  ---@param result FiletreeRefScanResult
  local function finish(result)
    state.result = result
    state.done = true
    local waiters = state.waiters
    state.waiters = {}
    for _, w in ipairs(waiters) do w(result) end
  end

  ---@type FiletreeRefScanResult
  local result = { refs = {}, plans = {} }

  -- Nothing to scan resolves *synchronously*, on purpose: `await` then runs its
  -- callback inline, so a paste with no cut items, or a setup with references
  -- switched off, is not deferred by an event-loop tick it has no use for.
  if not M.active(opts.op or "move", opts.mode) or #paths == 0 then
    finish(result)
    return {
      await = function(cb)
        if state.done then cb(state.result)
        else state.waiters[#state.waiters + 1] = cb end
      end,
    }
  end

  -- Build every (path, provider) plan up front, then run them all in parallel.
  local jobs = {}
  for _, path in ipairs(paths) do
    local ctx = make_ctx(path, opts)
    for _, provider in ipairs(registry.enabled(_cfg)) do
      local ok, plan = pcall(provider.plan, path, ctx)
      if ok and plan then
        result.plans[path] = result.plans[path] or {}
        result.plans[path][provider.name] = plan
        jobs[#jobs + 1] = { plan = plan, ctx = ctx }
      elseif not ok then
        notify.debug(string.format("provider '%s' failed to plan for %s: %s",
          provider.name, path, tostring(plan)))
      end
    end
  end

  if #jobs == 0 then
    finish(result) -- no provider had anything to look for
  else
    local pending = #jobs
    for _, job in ipairs(jobs) do
      scan.run_plan(job.plan, job.ctx, function(refs)
        for _, r in ipairs(refs) do result.refs[#result.refs + 1] = r end
        pending = pending - 1
        if pending == 0 then finish(result) end
      end)
    end
  end

  return {
    await = function(cb)
      if state.done then cb(state.result)
      else state.waiters[#state.waiters + 1] = cb end
    end,
  }
end

---Scan without the prefetch/await split, for callers that have nothing to
---overlap it with (the delete flow, which must know the refs before it can
---even draw its confirmation).
---@param paths string[]
---@param opts? table
---@param cb fun(result: FiletreeRefScanResult)
function M.scan(paths, opts, cb)
  M.prefetch(paths, opts).await(cb)
end

-- ── Resolve ───────────────────────────────────────────────────────────────────

---Set `new_target` on every ref of a scan result, given what moved where.
---
---Refs whose provider cannot express the new location (a Python relative
---import that left its package, a Lua file moved outside every `lua/` root)
---are dropped from the returned list and counted separately, so the caller can
---say so instead of silently doing nothing.
---@param result FiletreeRefScanResult
---@param moves table<string, string>  old path → new path
---@param opts? { lsp_handled?: boolean }
---@return FiletreeRef[] resolved, integer unresolved
function M.resolve(result, moves, opts)
  opts = opts or {}
  local out, unresolved = {}, 0

  for _, ref in ipairs(result.refs) do
    local new_path = moves[ref.source]
    local plan = result.plans[ref.source] and result.plans[ref.source][ref.provider]

    -- An LSP client that handled the rename already rewrote the code
    -- references; re-applying them textually would be at best a no-op and at
    -- worst a double edit. Providers whose language never gets that treatment
    -- (markdown has no server, lua_ls does not implement willRenameFiles) opt
    -- out of the skip via `lsp_exempt`.
    local provider = registry.get(ref.provider)
    local skip_lsp = opts.lsp_handled and _cfg.prefer_lsp
      and not (provider and provider.lsp_exempt)

    if new_path and plan and not skip_lsp then
      local ok, target = pcall(plan.retarget, ref, new_path)
      if ok and type(target) == "string" and target ~= "" and target ~= ref.target then
        ref.new_target = target
        out[#out + 1] = ref
      elseif not ok or target == nil then
        unresolved = unresolved + 1
      end
    end
  end

  return out, unresolved
end

-- ── High-level flows ──────────────────────────────────────────────────────────

---Resolve a finished scan against the moves that just happened, then ask (or
---not, per config) and apply. The one call a mutating feature needs after its
---rename/move succeeded.
---@param result FiletreeRefScanResult
---@param moves table<string, string>   old path → new path
---@param opts? { op?: "rename"|"move"|"copy", mode?: "ask"|"auto"|"off", picker?: string, title?: string, lsp_handled?: boolean }
---@param done? fun(applied: integer)
function M.handle_result(result, moves, opts, done)
  opts = opts or {}
  done = done or function() end

  local resolved, unresolved = M.resolve(result, moves, opts)
  if unresolved > 0 then
    notify.warn(string.format(
      "%d reference(s) could not be rewritten automatically (left untouched)", unresolved))
  end
  if #resolved == 0 then return done(0) end

  local names = {}
  for old in pairs(moves) do names[#names + 1] = ftpath.basename(old) end

  ui.confirm_and_apply(resolved, {
    mode = M.mode(opts.op or "move", opts.mode),
    picker = opts.picker or _cfg.picker,
    title = opts.title or ("References to " .. table.concat(names, ", ")),
    label = string.format("%s: %s", opts.op or "move", table.concat(names, ", ")),
  }, done)
end

---Await `handle` and hand its result to `handle_result` — the shorthand for
---the common "prefetch, mutate, then deal with the refs" shape.
---@param handle { await: fun(cb: fun(result: FiletreeRefScanResult)) }|nil
---@param moves table<string, string>
---@param opts? table
---@param done? fun(applied: integer)
function M.handle_move(handle, moves, opts, done)
  if not handle then return (done or function() end)(0) end
  handle.await(function(result) M.handle_result(result, moves, opts, done) end)
end

---References that would break if `paths` were deleted, each pre-set to the
---provider's "broken reference" marker (markdown links become `REF!`).
---
---Only providers that declare a `delete_target` take part: blanking a
---`require("…")` would leave code that no longer parses meaningfully, which is
---worse than an obviously dangling link, so the code providers deliberately
---sit this one out.
---@param paths string[]
---@param opts? table
---@param cb fun(refs: FiletreeRef[])
function M.for_delete(paths, opts, cb)
  opts = vim.tbl_extend("force", { op = "delete" }, opts or {})
  M.scan(paths, opts, function(result)
    local out = {}
    for _, ref in ipairs(result.refs) do
      local provider = registry.get(ref.provider)
      local marker = provider and provider.delete_target
      if marker then
        ref.new_target = marker
        out[#out + 1] = ref
      end
    end
    cb(out)
  end)
end

-- ── Undo ──────────────────────────────────────────────────────────────────────

---Undo the most recent reference update.
function M.undo()
  if not apply.can_undo() then
    notify.info("Nothing to undo")
    return
  end
  local label = apply.last_label()
  local restored, files = apply.undo()
  if restored > 0 then
    notify.info(string.format("Reverted %d reference(s) in %d file(s) (%s)",
      restored, files, label or "reference update"))
  else
    notify.warn("Nothing was reverted (files changed since the update?)")
  end
end

---Summary of the current state, for `:Filetree refs status`.
---@return string[]
function M.status()
  local lines = {
    string.format("enabled: %s", tostring(_cfg.enabled)),
    string.format("rename: %s   move: %s   delete: %s   copy: %s",
      _cfg.on_rename, _cfg.on_move, _cfg.on_delete, tostring(_cfg.copy)),
    string.format("scan root: %s   ripgrep: %s",
      (_cfg.scan and _cfg.scan.root) or "project",
      vim.fn.executable("rg") == 1 and "yes" or "no (capped fallback walk)"),
    "providers:",
  }
  local flags = _cfg.providers or {}
  for _, p in ipairs(registry.all()) do
    lines[#lines + 1] = string.format("  %s %s",
      flags[p.name] ~= false and "●" or "○", p.name)
  end
  lines[#lines + 1] = apply.can_undo()
    and ("undo available: " .. (apply.last_label() or "?"))
    or "undo available: —"
  return lines
end

return M
