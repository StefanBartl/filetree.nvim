---@module 'filetree.refs.assets'
--- Classifier for the cascade-delete-assets concept — step 2 of
--- `docs/ROADMAP/IDEAS/Cascade_Delete_Assets.md`: given the outgoing links
--- `filetree.refs.outgoing` found in a file that is about to be deleted,
--- decide which of them are actually safe to offer for deletion.
---
--- "Safe" means all three (see the roadmap note §3):
---   1. the target resolves under a configured assets root;
---   2. its extension is on an allowlist (never a denylist — an unknown
---      extension must never be offered by accident);
---   3. no OTHER surviving file still links to it — reusing the same
---      incoming-scan primitive the rest of the engine already has
---      (`filetree.refs`'s own `scan`), just without `for_delete`'s
---      `delete_target` filtering, since "is this referenced at all" is a
---      broader question than "which refs need a dangling-link marker".
---
--- Not wired into the delete dialog yet (step 3) and reads no shared `refs`
--- config yet (step 4) — `roots`/`extensions` are passed in per call, with
--- the same defaults §7 of the roadmap note sketches for the eventual config
--- block, so wiring that block in later is a default swap, not a rewrite.

local outgoing = require("filetree.refs.outgoing")
local pathutil = require("filetree.refs.pathutil")
local ftpath = require("filetree.util.path")

local M = {}

-- `images.nvim`'s `paste.dir` default (see Cascade_Delete_Assets.md §2) —
-- matched deliberately rather than inventing a second convention for the
-- same folder.
M.DEFAULT_ROOTS = { "assets" }

-- Image/video/binary-attachment shapes only. Deliberately excludes `pdf`
-- from the default (a linked PDF is often a real document, not a disposable
-- screenshot) — configurable per the roadmap note, not baked in here.
M.DEFAULT_EXTENSIONS = { "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "ico", "mp4", "mov" }

-- `FiletreeAssetCandidate` is declared in `@types/refs.lua`, alongside the
-- rest of the reference engine's shared shapes — not re-declared here.

---@internal
---Whether `resolved` lives under one of `roots`, each tried first relative to
---`linking_file`'s own directory (the per-doc-folder convention `images.nvim`'s
---`paste.dir` already uses), then relative to the project `root` — see §3.1.
---@param resolved string
---@param linking_file string
---@param root string
---@param roots string[]
---@return boolean
local function under_a_root(resolved, linking_file, root, roots)
  for _, r in ipairs(roots) do
    local near = pathutil.abs(ftpath.parent(linking_file) .. "/" .. r)
    if pathutil.under(resolved, near) then return true end
    if root and root ~= "" then
      local far = pathutil.abs(root:gsub("/+$", "") .. "/" .. r)
      if pathutil.under(resolved, far) then return true end
    end
  end
  return false
end

---@internal
---@param resolved string
---@param extensions string[]
---@return boolean
local function extension_allowed(resolved, extensions)
  local ext = resolved:match("%.([%w_]+)$")
  if not ext then return false end
  ext = ext:lower()
  for _, e in ipairs(extensions) do
    if e:lower() == ext then return true end
  end
  return false
end

---@internal
---Every OTHER file (not `exclude_file`, the one being deleted) that
---currently references any of `asset_paths` — the incoming-safety recheck,
---batched into ONE scan for the whole set of candidates rather than one
---full-project scan per asset (a file linking N images used to fire N
---concurrent scans on every delete). Reuses `filetree.refs`'s own scan
---primitive directly rather than `for_delete`: this asks "is it referenced
---at all", a broader question than `for_delete`'s "which refs need a
---dangling-link marker" (which only providers with `delete_target` —
---markdown alone — take part in).
---@param asset_paths string[]
---@param exclude_file string
---@param root string  Same search root `classify` already resolved for the
---                     root-containment check — passed through explicitly so
---                     this scan doesn't re-resolve it (and risk resolving to
---                     something else) from any one asset's own path.
---@param cb fun(referenced_by: table<string, string[]>)  asset path -> referencing files
local function still_referenced_batch(asset_paths, exclude_file, root, cb)
  if #asset_paths == 0 then return cb({}) end

  local by_asset = {}
  for _, p in ipairs(asset_paths) do
    by_asset[p] = {}
  end

  local refs = require("filetree.refs")
  -- `mode = "auto"` forces this scan to run regardless of the main
  -- `refs.enabled`/`refs.on_delete` switch: this is `outgoing_assets`' own
  -- safety recheck, gated by the caller already having established that
  -- `outgoing_assets` itself is active (see `outgoing_assets_mode`) — it must
  -- not silently go blind just because the UNRELATED incoming-refs direction
  -- is configured "off".
  refs.scan(asset_paths, { op = "delete", root = root, mode = "auto" }, function(result)
    -- Each `FiletreeRef.source` is the exact asset path its provider plan
    -- was built for (see `providers/markdown.lua`'s `plan`), so one merged
    -- scan result still resolves back to the specific asset it's about.
    local seen = {}
    for _, r in ipairs(result.refs) do
      local bucket = r.source and by_asset[r.source]
      if bucket and not pathutil.same(r.file, exclude_file) then
        local key = r.source .. "\0" .. r.file
        if not seen[key] then
          seen[key] = true
          bucket[#bucket + 1] = r.file
        end
      end
    end
    cb(by_asset)
  end)
end

---Classify the outgoing links of `path` (the file about to be deleted).
---Runs the outgoing scan itself, then for every link that resolves to an
---existing file, checks root + extension; only candidates passing both go
---through the (comparatively expensive) incoming-safety recheck.
---
---A link whose target does not currently exist on disk is left out of the
---result entirely — there is no file to cascade-delete for it, and it is
---`filetree.refs.outgoing`'s job, not this classifier's, to surface a
---dangling link.
---@param path string
---@param opts? { root?: string, roots?: string[], extensions?: string[] }
---@param cb fun(candidates: FiletreeAssetCandidate[])
function M.classify(path, opts, cb)
  opts = opts or {}
  local roots = opts.roots or M.DEFAULT_ROOTS
  local extensions = opts.extensions or M.DEFAULT_EXTENSIONS

  outgoing.scan(path, opts, function(links)
    local root = opts.root or outgoing.resolve_root(path)
    local candidates = {}
    local asset_candidates = {}

    for _, link in ipairs(links) do
      if link.exists then
        local is_asset = under_a_root(link.resolved, path, root, roots)
          and extension_allowed(link.resolved, extensions)

        ---@type FiletreeAssetCandidate
        local candidate = vim.tbl_extend("force", {}, link)
        candidate.is_asset = is_asset
        candidate.still_referenced = false
        candidate.referenced_by = {}
        candidates[#candidates + 1] = candidate

        if is_asset then asset_candidates[#asset_candidates + 1] = candidate end
      end
    end

    if #asset_candidates == 0 then return cb(candidates) end

    local asset_paths = {}
    for _, c in ipairs(asset_candidates) do
      asset_paths[#asset_paths + 1] = c.resolved
    end

    still_referenced_batch(asset_paths, path, root, function(by_asset)
      for _, c in ipairs(asset_candidates) do
        local by = by_asset[c.resolved] or {}
        c.still_referenced = #by > 0
        c.referenced_by = by
      end
      cb(candidates)
    end)
  end)
end

---Split classified candidates into what's actually safe to delete vs. what
---is being kept back because some OTHER surviving file still references it.
---Every consumer of `refs.outgoing_assets` (filetree's own trash dialog,
---fileops.nvim's soft integration) needs exactly this bucketing, so it lives
---here once rather than being re-derived at each call site.
---@param candidates FiletreeAssetCandidate[]
---@return FiletreeAssetCandidate[] deletable, FiletreeAssetCandidate[] kept
function M.split(candidates)
  local deletable, kept = {}, {}
  for _, c in ipairs(candidates) do
    if c.is_asset then
      if c.still_referenced then
        kept[#kept + 1] = c
      else
        deletable[#deletable + 1] = c
      end
    end
  end
  return deletable, kept
end

---Basenames of `assets`, for a notify line — full paths would be noise once
---there is more than one.
---@param assets FiletreeAssetCandidate[]
---@return string[]
function M.basenames(assets)
  local out = {}
  for _, c in ipairs(assets) do
    out[#out + 1] = vim.fn.fnamemodify(c.resolved, ":t")
  end
  return out
end

return M
