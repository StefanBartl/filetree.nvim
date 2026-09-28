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
local ftfs = require("filetree.util.fs")

local M = {}

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
---@param moves table<string, string>
---@return { old: string, new: string }[]
local function expand_files(moves)
  local out = {}
  for old, new in pairs(moves) do
    if vim.fn.isdirectory(new) == 1 then
      for _, new_file in ipairs(ftfs.collect_recursive(new, "files")) do
        local rest = pathutil.relative(new_file, new)
        local old_file = (rest == ".") and old or pathutil.abs(old:gsub("/+$", "") .. "/" .. rest)
        out[#out + 1] = { old = old_file, new = new_file }
      end
    else
      out[#out + 1] = { old = old, new = new }
    end
  end
  return out
end

---Outgoing-link edit records for every file in `moves`, after its own move —
---each already resolved and retargeted. Providers without a `retarget_link`
---(every code provider today — see `filetree.refs.outgoing`'s own doc
---comment for why) contribute nothing here, same as they contribute nothing
---to `filetree.refs.outgoing` itself.
---@param moves table<string, string>  old path -> new path (already landed on disk)
---@param opts { op: "rename"|"move"|"copy", root: string, cfg: FiletreeRefsConfig }
---@return FiletreeRef[]
function M.collect(moves, opts)
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
  if not next(retargetable) then return {} end

  local flat, dirs = moves_index(moves)
  local out = {}

  for _, pr in ipairs(expand_files(moves)) do
    outgoing.scan(pr.new, { root = opts.root, base = pr.old, env = env }, function(links)
      for _, link in ipairs(links) do
        local provider = retargetable[link.provider]
        if provider then
          local final_abs = remap_if_also_moved(link.resolved, flat, dirs)
          local ok, new_target =
            pcall(provider.retarget_link, link, final_abs, { root = opts.root, env = env })
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

  return out
end

return M
