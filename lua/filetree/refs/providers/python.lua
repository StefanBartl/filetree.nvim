---@module 'filetree.refs.providers.python'
--- Python `import` reference provider.
---
--- Covers absolute imports (`import a.b.c`, `import a.b as c`,
--- `from a.b import x`) and relative ones (`from .sibling import x`,
--- `from ..pkg.mod import x`).
---
--- Absolute module names are resolved against the nearest project root, the
--- same convention `smart_rename` used before this provider existed. Relative
--- imports are anchored at the importing file's own package: `.` is its
--- directory, each additional dot climbs one level.
---
--- A relative import is only *rewritten* when the moved file still lives under
--- that same anchor afterwards. Moving a module out of the package would turn
--- the relative import into an absolute one, which is a semantic change (and
--- may be plain wrong, depending on how the package is installed), so those
--- refs are reported as "not rewritable" and left alone instead.

local ftpath = require("filetree.util.path")
local pathutil = require("filetree.refs.pathutil")

local M = {}

M.name = "python"

---Files that can hold Python imports.
local EXTENSIONS = { "py", "pyi" }

---Absolute `.py` path → dotted module name relative to the nearest project
---root (falling back to the file's own directory).
---@param abs_path string
---@param root string
---@return string?
function M.module_name(abs_path, root)
  local root_norm = ftpath.to_unix(root):gsub("/+$", "")
  local rel = ftpath.to_unix(abs_path):gsub("/+$", "")
  if rel:sub(1, #root_norm) == root_norm then
    rel = rel:sub(#root_norm + 2) -- +2 skips the root and its separating "/"
  end
  rel = rel:gsub("%.pyi?$", ""):gsub("/__init__$", "")
  if rel == "" then return nil end
  return (rel:gsub("/", "."))
end

---@internal
---Absolute path a dotted module resolves to, given a base directory
---(`pkg.mod` under `/root` → `/root/pkg/mod`). No extension is appended; the
---caller compares against both `<p>.py` and `<p>/__init__.py`.
---@param mod string
---@param base string
---@return string
local function module_to_path(mod, base)
  return ftpath.to_unix(base:gsub("/+$", "") .. "/" .. mod:gsub("%.", "/"))
end

---@internal
---The file a dotted module (resolved against `base`) denotes, when that file
---is `wanted` — or lives under it, for a moved package. Returns nil when the
---module points somewhere else entirely.
---@param mod string
---@param base string
---@param wanted string
---@param is_dir boolean
---@return string? resolved
local function points_at(mod, base, wanted, is_dir)
  local p = module_to_path(mod, base)
  if is_dir then
    if pathutil.same(p, wanted) or pathutil.under(p, wanted) then return p end
    return nil
  end
  for _, cand in ipairs({ p .. ".py", p .. ".pyi", p .. "/__init__.py" }) do
    if pathutil.same(cand, wanted) then return cand end
  end
  return nil
end

---@internal
---Anchor directory of a relative import (`.` = the file's own directory, each
---further leading dot climbs one level) plus the dotted remainder.
---@param mod string   e.g. "..pkg.mod"
---@param file string
---@return string? anchor_dir, string? rest
local function relative_anchor(mod, file)
  local dots = mod:match("^(%.+)")
  if not dots then return nil, nil end
  local dir = ftpath.parent(file)
  for _ = 2, #dots do dir = ftpath.parent(dir) end
  return dir, mod:sub(#dots + 1)
end

---@internal
---Walk every module token of every import statement in `text`, calling
---`fn(col, mod)`.
---@param text string
---@param fn fun(col: integer, mod: string)
local function each_import(text, fn)
  -- from <mod> import …   (mod may start with dots: relative import)
  local _, _, from_prefix, from_mod = text:find("^(%s*from%s+)([%.%w_]+)")
  if from_prefix and from_mod then
    fn(#from_prefix + 1, from_mod)
    return -- a `from` line has exactly one module token
  end

  -- import <mod>[ as alias][, <mod2>[ as alias2]]
  local _, _, imp_prefix, list = text:find("^(%s*import%s+)([^#]+)")
  if not (imp_prefix and list) then return end

  local offset = #imp_prefix
  local pos = 1
  while pos <= #list do
    local comma = list:find(",", pos, true)
    local chunk_end = (comma or #list + 1) - 1
    local chunk = list:sub(pos, chunk_end)
    local lead, mod = chunk:match("^(%s*)([%.%w_]+)")
    if mod then fn(offset + pos + #lead, mod) end
    pos = chunk_end + 2
  end
end

---@param old_path string
---@param ctx FiletreeRefCtx
---@return FiletreeRefPlan|nil
function M.plan(old_path, ctx)
  local old_mod = M.module_name(old_path, ctx.root)
  if not old_mod then return nil end

  -- The pre-filter needs to catch both spellings: the fully dotted absolute
  -- module and the bare last segment a relative import would use.
  local last = old_mod:match("([^%.]+)$") or old_mod
  local needles = { old_mod }
  if last ~= old_mod then needles[#needles + 1] = last end

  return {
    needles = needles,
    extensions = EXTENSIONS,

    extract = function(file, lineno, text)
      local refs = {}
      each_import(text, function(col, mod)
        local base, rest, relative
        if mod:sub(1, 1) == "." then
          base, rest = relative_anchor(mod, file)
          relative = true
          if not base or rest == "" then return end
        else
          base, rest, relative = ctx.root, mod, false
        end

        local resolved = points_at(rest, base, old_path, ctx.is_dir)
        if not resolved then return end

        refs[#refs + 1] = {
          file = file,
          line = lineno,
          col = col,
          text = text,
          target = mod,
          provider = M.name,
          source = old_path,
          relative = relative,
          anchor = base,
          resolved = resolved,
          display = string.format("%s:%d: %s",
            vim.fn.fnamemodify(file, ":."), lineno, vim.trim(text)),
        }
      end)
      return refs
    end,

    retarget = function(ref, new_path)
      local dest = new_path
      if ctx.is_dir and ref.resolved then
        -- A moved package: the import may point at a module *inside* it, so
        -- remap that module through the old→new directory pair.
        dest = pathutil.remap_under(ref.resolved, old_path, new_path)
      end

      if not ref.relative then
        local new_mod = M.module_name(dest, ctx.root)
        return new_mod
      end

      -- Relative import: only expressible while the destination stays under
      -- the anchor this import climbs to.
      if not pathutil.under(dest, ref.anchor) then return nil end
      local dots = ref.target:match("^(%.+)") or "."
      local rest = pathutil.relative(dest, ref.anchor)
        :gsub("%.pyi?$", ""):gsub("/__init__$", ""):gsub("/", ".")
      if rest == "" or rest == "." then return dots end
      return dots .. rest
    end,
  }
end

return M
