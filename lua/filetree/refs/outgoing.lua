---@module 'filetree.refs.outgoing'
--- Outgoing-link extraction: what does *this* file link to, resolved to
--- absolute paths on disk — the mirror of the incoming scan (`refs.for_delete`
--- asks "who points at this file"; this asks "what does this file point at").
---
--- Step 1 of the cascade-delete-assets concept
--- (`docs/ROADMAP/IDEAS/Cascade_Delete_Assets.md`): read the file's own
--- content *before* it is deleted — same prefetch-before-mutation discipline
--- as the rest of the engine, call this the moment the delete is triggered,
--- while the path still exists — and return every resolved link target,
--- unfiltered. No classifier yet (assets-folder / extension allowlist, the
--- incoming-safety recheck) — those are the next steps in the roadmap note,
--- not this module.

local scan = require("filetree.refs.scan")
local pathutil = require("filetree.refs.pathutil")
local registry = require("filetree.refs.registry")
local ftpath = require("filetree.util.path")

local M = {}

-- `FiletreeOutgoingLink` is declared in `@types/refs.lua`, alongside the rest
-- of the reference engine's shared shapes — not re-declared here.

---Search root for `path`: the nearest project root, or the cwd. Mirrors
---`filetree.refs`'s own (private) `make_ctx`/`resolve_root` — kept as a
---separate copy rather than exposed from there, since `refs/init.lua`
---requires this module and a back-reference would cycle. Exported (not
---`@internal`) so `filetree.refs.assets` can resolve the same root without a
---third copy.
---@param path string
---@return string
function M.resolve_root(path)
  local cfg = require("filetree.refs").config()
  if cfg.scan and cfg.scan.root == "cwd" then return vim.fn.getcwd() end
  local ok_pr, project_root = require("filetree.features").load("project_root")
  if ok_pr and project_root and type(project_root.find) == "function" then
    local ok_find, found = pcall(project_root.find, ftpath.parent(path))
    if ok_find and type(found) == "string" and found ~= "" then return found end
  end
  return vim.fn.getcwd()
end

---@internal
---Lowercased extension of `path` (no dot), or "" if it has none. Same pattern
---`refs/scan.lua`'s candidate walk uses.
---@param path string
---@return string
local function extension_of(path)
  local ext = path:match("%.([%w_]+)$")
  return ext and ext:lower() or ""
end

---@internal
---Whether `provider` declares support for `ext` via its static `extensions`
---list. A provider without one (none exist today) is treated as applying to
---every file, matching `plan()`'s own "no extensions ⇒ unrestricted" absence
---of a default.
---@param provider FiletreeRefProvider
---@param ext string
---@return boolean
local function provider_handles_extension(provider, ext)
  if type(provider.extensions) ~= "table" or #provider.extensions == 0 then return true end
  for _, e in ipairs(provider.extensions) do
    if e:lower() == ext then return true end
  end
  return false
end

---@internal
---Best-effort pick among a target's candidate absolute readings — a
---root-relative `/x` reads two ways (filesystem root or project root, see
---`pathutil.resolve_candidates`): prefer whichever exists on disk, else the
---first (filesystem) reading. A broken link still gets a `resolved` path
---(useful to a future caller), just with `exists = false`.
---@param target string
---@param from_file string
---@param root string
---@return string resolved, boolean exists
local function resolve_one(target, from_file, root)
  local candidates = pathutil.resolve_candidates(target, from_file, root)
  for _, cand in ipairs(candidates) do
    if vim.fn.filereadable(cand) == 1 then return cand, true end
  end
  return candidates[1], false
end

---@internal
---Registered, enabled providers that can walk their own outgoing link
---targets. Deliberately reads `each_link_target` presence rather than a
---fixed name list: only `markdown` implements it today (see
---`Cascade_Delete_Assets.md` §3 for why a code provider — lua/python/ts_js —
---never will, their outgoing "references" are require()/import statements
---pointing at code, not at binary assets), but a future provider opts in the
---same way `plan`/`delete_target` already work.
---@param cfg FiletreeRefsConfig
---@return FiletreeRefProvider[]
local function providers_for(cfg)
  local out = {}
  for _, p in ipairs(registry.enabled(cfg)) do
    if type(p.each_link_target) == "function" then out[#out + 1] = p end
  end
  return out
end

---Outgoing links found in `path`'s own current content, resolved to absolute
---paths.
---
---Synchronous today — reading one file's own lines needs no project-wide
---ripgrep pass — but callback-shaped so the signature stays stable once the
---classifier (assets-folder + extension allowlist) and the incoming-safety
---recheck land on top of this and genuinely need to be async.
---@param path string
---@param opts? { root?: string }
---@param cb fun(links: FiletreeOutgoingLink[])
function M.scan(path, opts, cb)
  opts = opts or {}
  local cfg = require("filetree.refs").config()
  local ext = extension_of(path)
  local providers = {}
  for _, p in ipairs(providers_for(cfg)) do
    if provider_handles_extension(p, ext) then providers[#providers + 1] = p end
  end

  if #providers == 0 then return cb({}) end

  local lines = scan.lines_of(path)
  if not lines then return cb({}) end

  local root = opts.root or M.resolve_root(path)
  local out = {}

  for _, provider in ipairs(providers) do
    for lineno, text in ipairs(lines) do
      provider.each_link_target(text, cfg, function(col, target, decoded, kind)
        local resolved, exists = resolve_one(decoded, path, root)
        out[#out + 1] = {
          file = path,
          line = lineno,
          col = col,
          text = text,
          target = target,
          resolved = resolved,
          exists = exists,
          provider = provider.name,
          kind = kind,
          display = string.format(
            "%s:%d: %s",
            vim.fn.fnamemodify(resolved, ":."),
            lineno,
            vim.trim(text)
          ),
        }
      end)
    end
  end

  cb(out)
end

return M
