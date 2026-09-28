---@module 'filetree.refs.own_links'
--- Outgoing links found INSIDE a moved/renamed/copied file's own content,
--- rewritten so they still resolve correctly now that the file's own
--- location changed — the mirror of the rest of this engine's INCOMING-refs
--- pipeline (`refs.resolve`/`refs.handle_result`): those ask "who points at
--- the file that moved, and how must THAT pointer read afterwards"; this
--- asks "what does the file that moved point at, and does that link text —
--- written for its OLD position — still mean the same thing from its NEW
--- one".
---
--- Pure gather step, the same split `refs.resolve()`/`refs.handle_result()`
--- already use: `M.collect` only returns `FiletreeRef`-shaped edit records
--- (each already resolved — there is no separate "who matches" step the way
--- incoming refs need one, since the file's own new position IS the move
--- that just happened). Confirmation, `apply.run` and undo are
--- `refs.handle_result`'s job, which folds this list in alongside the
--- incoming-refs one.

local outgoing = require("filetree.refs.outgoing")
local pathutil = require("filetree.refs.pathutil")
local registry = require("filetree.refs.registry")
local scan = require("filetree.refs.scan")
local ftfs = require("filetree.util.fs")
local symlink = require("filetree.util.symlink")
local progress = require("filetree.util.progress")
local notify = require("filetree.util.notify").create("[filetree.refs]")

local M = {}

-- Per-tick cap on how many files' outgoing links get scanned+retargeted
-- before yielding, mirroring `refs/scan.lua`'s `WALK_CHUNK_SIZE` — a
-- directory move dropped straight into a project-wide "wiki" of a few
-- hundred markdown notes (this plugin's own typical use case) must not stall
-- the editor for the whole batch.
local CHUNK_SIZE = 20

---@internal
---Directories a directory-move walk never has reason to descend into, same
---list `refs/scan.lua` prunes for the incoming-refs side of this same
---concern.
---@param name string
---@return boolean
local function prune(name)
  return scan.PRUNE_DIRS[name] == true
end

---@internal
---Split `moves` into files moved directly and directories moved — a
---directory entry expands to per-file work in `expand_files` below, but is
---ALSO kept here (not just expanded) so a link that resolves under it can be
---remapped without re-deriving the same prefix walk twice.
---@param moves table<string, string>
---@return table<string, string> flat  old path key -> new path, non-directory moves only
---@return { old: string, new: string }[] dirs
local function moves_index(moves)
  local flat, dirs = {}, {}
  for old, new in pairs(moves) do
    if vim.fn.isdirectory(new) == 1 then
      dirs[#dirs + 1] = { old = old, new = new }
    else
      flat[pathutil.key(old)] = new
    end
  end
  return flat, dirs
end

---@internal
---A link's resolved (pre-move) target may itself be part of the SAME move
---batch — e.g. a folder moved together with an asset it links to. Remap it
---to its own new location too, rather than only re-anchoring the link from
---the referrer's new position.
---@param resolved_old string
---@param flat table<string, string>
---@param dirs { old: string, new: string }[]
---@return string
local function remap_if_also_moved(resolved_old, flat, dirs)
  local hit = flat[pathutil.key(resolved_old)]
  if hit then return hit end
  for _, d in ipairs(dirs) do
    if pathutil.under(resolved_old, d.old) then
      return pathutil.remap_under(resolved_old, d.old, d.new)
    end
  end
  return resolved_old
end

---@internal
---Expand `moves` (files and directories alike) into one `{old, new}` pair
---per FILE: a directory move needs its own outgoing links checked file by
---file, each against the correspondingly nested old path.
---
---Two safety filters apply, neither of which the caller can opt out of:
---
---  * `prune` skips `.git`/`node_modules`/`dist`/… subtrees entirely (not
---    just from the listing — from the walk itself, via `collect_recursive`'s
---    `ignore_fn`), the same set `refs/scan.lua` already prunes for the
---    incoming-refs side of this feature. Without it, moving a directory that
---    happens to contain a populated `node_modules` would enumerate and then
---    line-scan every file in it.
---  * A **symlink entry — the directory-walk case here, or a single moved
---    file that is itself a symlink, in the `else` branch below — is dropped
---    entirely, never scanned or rewritten.** `outgoing.scan` reads through a
---    symlink to its real target's content (`vim.fn.readfile` follows links),
---    and `refs.apply`'s `writefile` would write back through the same link —
---    i.e. straight into whatever file the symlink actually points at, which
---    can be *outside the project entirely* (a shipped repo/archive
---    containing a symlink masquerading as a note is enough to reach this).
---    Left un-rewritten instead, the same documented-scope-cut posture
---    `providers/markdown.lua`'s `retarget_link` already applies to
---    wikilinks: silently doing nothing is safe, guessing is not.
---@param moves table<string, string>
---@return { old: string, new: string }[]
local function expand_files(moves)
  local out = {}
  for old, new in pairs(moves) do
    if vim.fn.isdirectory(new) == 1 then
      for _, new_file in ipairs(ftfs.collect_recursive(new, "files", prune)) do
        if not symlink.is_link(new_file) then
          local rest = pathutil.relative(new_file, new)
          local old_file = (rest == ".") and old or pathutil.abs(old:gsub("/+$", "") .. "/" .. rest)
          out[#out + 1] = { old = old_file, new = new_file }
        end
      end
    elseif not symlink.is_link(new) then
      out[#out + 1] = { old = old, new = new }
    end
  end
  return out
end

---@internal
---Scan+retarget one `{old, new}` pair's outgoing links into `out`, resolving
---the project root fresh for THIS file unless the caller forced one — a
---batch that spans more than one nested project root (each with its own
---marker file) must not have a file from one root's links resolved against
---another's, the same per-path discipline `refs/init.lua`'s own `make_ctx`
---already applies on the incoming-refs side.
---@param pr { old: string, new: string }
---@param opts { root?: string, env: FiletreeRefEnvRoots }
---@param flat table<string, string>
---@param dirs { old: string, new: string }[]
---@param retargetable table<string, FiletreeRefProvider>
---@param out FiletreeRef[]
local function process_one(pr, opts, flat, dirs, retargetable, out)
  local file_root = opts.root or outgoing.resolve_root(pr.new)
  outgoing.scan(pr.new, { root = file_root, base = pr.old, env = opts.env }, function(links)
    for _, link in ipairs(links) do
      local provider = retargetable[link.provider]
      if provider then
        local final_abs = remap_if_also_moved(link.resolved, flat, dirs)
        local ok, new_target =
          pcall(provider.retarget_link, link, final_abs, { root = file_root, env = opts.env })
        if
          ok
          and type(new_target) == "string"
          and new_target ~= ""
          and new_target ~= link.target
        then
          out[#out + 1] = {
            file = pr.new,
            line = link.line,
            col = link.col,
            text = link.text,
            target = link.target,
            new_target = new_target,
            provider = link.provider,
            source = link.resolved,
            display = link.display,
          }
        end
      end
    end
  end)
end

---Outgoing-link edit records for every file in `moves`, after its own move —
---each already resolved and retargeted. Providers without a `retarget_link`
---(every code provider today — see `filetree.refs.outgoing`'s own doc
---comment for why) contribute nothing here, same as they contribute nothing
---to `filetree.refs.outgoing` itself.
---
---Always asynchronous (even a small batch is handed to `cb` via one
---`vim.schedule`, matching `refs/scan.lua`'s own small-case convention) — a
---batch under `scan.max_files` runs in one uninterrupted pass; a larger one
---(directory move dropped on a big note vault) is chunked `CHUNK_SIZE` files
---per event-loop tick with a `[filetree.refs]` progress indicator, same
---shape as `refs/scan.lua`'s ripgrep-free fallback walk, so this never
---freezes the editor for the whole batch.
---@param moves table<string, string>  old path -> new path (already landed on disk)
---@param opts { op: "rename"|"move"|"copy", root?: string, cfg: FiletreeRefsConfig }
---@param cb fun(edits: FiletreeRef[])
function M.collect(moves, opts, cb)
  cb = cb or function() end
  local cfg = opts.cfg
  local ol = cfg.outgoing_links or {}
  ---@type FiletreeRefEnvRoots
  local env = {
    names = ol.env_vars or {},
    extra = { { name = "NVIM_CONFIG_DIR", root = vim.fn.stdpath("config") } },
  }

  ---@type table<string, FiletreeRefProvider>
  local retargetable = {}
  for _, p in ipairs(registry.enabled(cfg)) do
    if type(p.retarget_link) == "function" then retargetable[p.name] = p end
  end
  if not next(retargetable) then return cb({}) end

  local flat, dirs = moves_index(moves)
  local files = expand_files(moves)

  local max_files = (cfg.scan and cfg.scan.max_files) or 5000
  local capped = #files > max_files
  local total = capped and max_files or #files
  if capped then
    notify.warn(string.format("own outgoing-link scan stopped at %d file(s)", max_files))
  end

  local out = {}
  local file_opts = { root = opts.root, env = env }

  if total <= CHUNK_SIZE then
    for i = 1, total do
      process_one(files[i], file_opts, flat, dirs, retargetable, out)
    end
    return vim.schedule(function()
      cb(out)
    end)
  end

  local h = progress.create({ title = "[filetree.refs]" })
  local i = 0

  local function step()
    if h and h.cancelled then
      -- Edits found so far are still reported -- a partial rewrite offer is
      -- more useful than none.
      return cb(out)
    end

    local last = math.min(i + CHUNK_SIZE, total)
    for j = i + 1, last do
      process_one(files[j], file_opts, flat, dirs, retargetable, out)
    end
    i = last

    if h then h:update({ text = "scanning own links…", current = i, total = total }) end

    if i < total then
      vim.schedule(step)
      return
    end

    if h then h:finish(string.format("%d own-link edit(s) found", #out)) end
    cb(out)
  end

  step()
end

return M
