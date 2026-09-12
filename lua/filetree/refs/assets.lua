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
---currently references `asset_path` — the incoming-safety recheck. Reuses
---`filetree.refs`'s own scan primitive directly rather than `for_delete`:
---this asks "is it referenced at all", a broader question than
---`for_delete`'s "which refs need a dangling-link marker" (which only
---providers with `delete_target` — markdown alone — take part in).
---@param asset_path string
---@param exclude_file string
---@param root string  Same search root `classify` already resolved for the
---                     root-containment check — passed through explicitly so
---                     this scan doesn't re-resolve it (and risk resolving to
---                     something else) from the asset's own path.
---@param cb fun(referenced_by: string[])
local function still_referenced(asset_path, exclude_file, root, cb)
  local refs = require("filetree.refs")
  refs.scan({ asset_path }, { op = "delete", root = root }, function(result)
    local seen, by = {}, {}
    for _, r in ipairs(result.refs) do
      if not pathutil.same(r.file, exclude_file) and not seen[r.file] then
        seen[r.file] = true
        by[#by + 1] = r.file
      end
    end
    cb(by)
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
    local pending = 0
    local scan_done = false

    local function finish_if_done()
      if scan_done and pending == 0 then cb(candidates) end
    end

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

        if is_asset then
          pending = pending + 1
          still_referenced(candidate.resolved, path, root, function(by)
            candidate.still_referenced = #by > 0
            candidate.referenced_by = by
            pending = pending - 1
            finish_if_done()
          end)
        end
      end
    end

    scan_done = true
    finish_if_done()
  end)
end

return M
