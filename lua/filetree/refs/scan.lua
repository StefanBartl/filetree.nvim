---@module 'filetree.refs.scan'
--- Candidate discovery for the reference engine.
---
--- Two stages, both cheap:
---
---   1. a fixed-string ripgrep pre-filter (`--files-with-matches`) using the
---      provider's `needles`, restricted to the provider's `extensions`, so a
---      project-wide scan only ever reads a handful of files;
---   2. per candidate file, every line is handed to the provider's `extract`,
---      which does the real (path-resolving) verification.
---
--- Line content comes from a *loaded buffer* when the candidate file has one,
--- and from disk otherwise — the same source the apply step will write back
--- to, so the content-verify in `filetree.refs.apply` can never be defeated by
--- unsaved edits sitting between scan and apply.
---
--- Without ripgrep the pre-filter degrades to a capped libuv walk
--- (`scan.max_files`) rather than turning the whole feature off.

local ftpath = require("filetree.util.path")
local ftfs = require("filetree.util.fs")
local notify = require("filetree.util.notify").create("[filetree.refs]")

local M = {}

-- Directories never worth scanning for references. Kept local (and not routed
-- through util.ignore) on purpose: util.ignore is the *display* ignore list,
-- which the user may legitimately want to differ from what a reference scan
-- traverses.
local PRUNE_DIRS = {
  [".git"] = true, ["node_modules"] = true, [".venv"] = true, ["venv"] = true,
  ["dist"] = true, ["build"] = true, ["target"] = true, ["vendor"] = true,
  [".next"] = true, [".cache"] = true, ["__pycache__"] = true,
}

-- ── Line access ───────────────────────────────────────────────────────────────

---@internal
---Find a loaded buffer whose name is `file` (separator-normalized compare, so a
---forward-slash buffer name matches an OS-native path on Windows).
---@param file string
---@return integer|nil
function M.buffer_for(file)
  local key = ftpath.slashify(file)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_is_loaded(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" and ftpath.slashify(name) == key then return b end
    end
  end
  return nil
end

---Lines of `file`, preferring a loaded buffer over the on-disk content.
---@param file string
---@return string[]|nil
function M.lines_of(file)
  local bufnr = M.buffer_for(file)
  if bufnr then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok or type(lines) ~= "table" then return nil end
  return lines
end

-- ── Candidate discovery ───────────────────────────────────────────────────────

---@internal
---@param exts string[]
---@return table<string, boolean>
local function ext_set(exts)
  local set = {}
  for _, e in ipairs(exts) do set[e:lower()] = true end
  return set
end

---@internal
---ripgrep-based candidate search.
---@param root string
---@param needles string[]
---@param exts string[]
---@param cfg FiletreeRefsConfig
---@param cb fun(files: string[]|nil)  nil signals "ripgrep unusable, fall back"
local function candidates_rg(root, needles, exts, cfg, cb)
  if vim.fn.executable("rg") == 0 then return cb(nil) end

  -- argv form (not a shell string) on purpose: rg is exec'd directly, so
  -- there is nothing to quote and no dependency on &shell — the same
  -- reasoning as the scan this replaces in smart_rename.
  local cmd = { "rg", "--files-with-matches", "--fixed-strings", "--color=never", "--ignore-case" }
  if cfg.scan and cfg.scan.respect_gitignore == false then
    cmd[#cmd + 1] = "--no-ignore"
  end
  for _, e in ipairs(exts) do
    cmd[#cmd + 1] = "-g"; cmd[#cmd + 1] = "*." .. e
  end
  for dir in pairs(PRUNE_DIRS) do
    cmd[#cmd + 1] = "-g"; cmd[#cmd + 1] = "!" .. dir .. "/*"
  end
  for _, n in ipairs(needles) do
    cmd[#cmd + 1] = "-e"; cmd[#cmd + 1] = n
  end
  cmd[#cmd + 1] = "--"
  cmd[#cmd + 1] = root

  local timeout = (cfg.scan and cfg.scan.timeout_ms) or 3000
  local ok_spawn = pcall(vim.system, cmd, { text = true, timeout = timeout }, function(result)
    vim.schedule(function()
      -- rg: 0 = matches, 1 = no matches, >1 = error (including a timeout kill)
      if result.code > 1 then
        notify.debug("ripgrep scan failed (code " .. tostring(result.code) .. ")")
        return cb({})
      end
      local files = {}
      for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        files[#files + 1] = ftpath.to_absolute(line)
      end
      cb(files)
    end)
  end)
  if not ok_spawn then cb(nil) end
end

---@internal
---ripgrep-free fallback: walk the tree, keep files with a matching extension,
---and plain-find the needles in their content. Capped by `scan.max_files`.
---@param root string
---@param needles string[]
---@param exts string[]
---@param cfg FiletreeRefsConfig
---@param cb fun(files: string[])
local function candidates_walk(root, needles, exts, cfg, cb)
  local max_files = (cfg.scan and cfg.scan.max_files) or 5000
  local wanted = ext_set(exts)

  local all = ftfs.collect_recursive(root, "files", function(name)
    return PRUNE_DIRS[name] == true
  end)

  local out, seen = {}, 0
  for _, file in ipairs(all) do
    local ext = file:match("%.([%w_]+)$")
    if ext and wanted[ext:lower()] then
      seen = seen + 1
      if seen > max_files then
        notify.warn(string.format(
          "reference scan stopped at %d files (install ripgrep for the fast path)", max_files))
        break
      end
      local lines = M.lines_of(file)
      if lines then
        local hit = false
        for _, line in ipairs(lines) do
          local lower = line:lower()
          for _, n in ipairs(needles) do
            if lower:find(n:lower(), 1, true) then hit = true; break end
          end
          if hit then break end
        end
        if hit then out[#out + 1] = file end
      end
    end
  end

  vim.schedule(function() cb(out) end)
end

---Files that may contain a reference matching `needles`.
---@param root string
---@param needles string[]
---@param exts string[]
---@param cfg FiletreeRefsConfig
---@param cb fun(files: string[])
function M.candidates(root, needles, exts, cfg, cb)
  if #needles == 0 or #exts == 0 then return cb({}) end
  candidates_rg(root, needles, exts, cfg, function(files)
    if files then return cb(files) end
    candidates_walk(root, needles, exts, cfg, cb)
  end)
end

-- ── Plan execution ────────────────────────────────────────────────────────────

---Run one provider plan for one moved path and deliver the refs it found.
---@param plan FiletreeRefPlan
---@param ctx FiletreeRefCtx
---@param cb fun(refs: FiletreeRef[])
function M.run_plan(plan, ctx, cb)
  M.candidates(ctx.root, plan.needles, plan.extensions, ctx.cfg, function(files)
    local refs = {}
    for _, file in ipairs(files) do
      local lines = M.lines_of(file)
      if lines then
        for i, text in ipairs(lines) do
          local found = plan.extract(file, i, text)
          for _, r in ipairs(found or {}) do refs[#refs + 1] = r end
        end
      end
    end
    cb(refs)
  end)
end

return M
