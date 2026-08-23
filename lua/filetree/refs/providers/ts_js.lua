---@module 'filetree.refs.providers.ts_js'
--- JavaScript/TypeScript module-specifier provider.
---
--- Covers every spelling that carries a specifier: `import x from "…"`,
--- `import "…"`, `export … from "…"`, dynamic `import("…")` and CommonJS
--- `require("…")`.
---
--- Two kinds of specifier are resolved:
---
---   * **relative** — `./x`, `../x/y`, resolved against the importing file's
---     directory, then through the usual extension/`index` candidates
---     (`x`, `x.ts`, `x.tsx`, `x.js`, …, `x/index.ts`, …);
---   * **alias** — `@/components/x`, resolved through the `paths`/`baseUrl`
---     map of the nearest `tsconfig.json` / `jsconfig.json` (`extends` chains
---     are followed). Without that step the provider would be close to
---     useless in any modern project, where most imports are aliased.
---
--- Rewrites keep the flavour of the original: an aliased import stays aliased
--- while the destination is still under that alias, a relative one stays
--- relative, an extensionless specifier stays extensionless, and a specifier
--- written with an explicit `.js` (the ESM-on-TypeScript convention) keeps its
--- `.js` even though the file on disk is `.ts`.
---
--- `tsserver` implements `workspace/willRenameFiles`, so when an LSP client
--- already applied a workspace edit this provider stays out of the way (see
--- `refs.prefer_lsp`); it is the fallback for everyone running without it.

local ftpath = require("filetree.util.path")
local pathutil = require("filetree.refs.pathutil")

local M = {}

M.name = "ts_js"

---Files that can hold JS/TS imports.
local EXTENSIONS = { "ts", "tsx", "js", "jsx", "mjs", "cjs", "mts", "cts" }

---Extension candidates tried when resolving an extensionless specifier.
local RESOLVE_EXTS = { ".ts", ".tsx", ".d.ts", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts" }

---@internal
---@param p string
---@return string
local function strip_ext(p)
  return (p:gsub("%.d%.ts$", ""):gsub("%.[cm]?[tj]sx?$", ""))
end

-- ── tsconfig / jsconfig alias map ─────────────────────────────────────────────

---@type table<string, { base: string, paths: table<string, string[]> }|false>
local _alias_cache = {}

---@internal
---Strip `//` and `/* */` comments and trailing commas so `vim.json.decode`
---accepts a real-world tsconfig (JSON with comments is the norm there).
---@param raw string
---@return string
local function strip_jsonc(raw)
  local out = raw:gsub("/%*.-%*/", "")
  out = out:gsub("([^:])//[^\n]*", "%1")
  out = out:gsub(",(%s*[%]}])", "%1")
  return out
end

---@internal
---@param file string
---@return table|nil
local function read_config(file)
  local ok_read, raw = pcall(vim.fn.readfile, file)
  if not ok_read or type(raw) ~= "table" then return nil end
  local ok_json, decoded = pcall(vim.json.decode, strip_jsonc(table.concat(raw, "\n")))
  if not ok_json or type(decoded) ~= "table" then return nil end
  return decoded
end

---@internal
---Nearest tsconfig/jsconfig at or above `dir`.
---@param dir string
---@return string|nil
local function find_config(dir)
  local found = vim.fs.find({ "tsconfig.json", "jsconfig.json" }, { upward = true, path = dir, type = "file" })
  return found and found[1] or nil
end

---@internal
---Resolve the alias map of the config at `file`, following `extends`.
---@param file string
---@param depth integer
---@return { base: string, paths: table<string, string[]> }|nil
local function load_alias_map(file, depth)
  if depth > 5 then return nil end
  local cfg = read_config(file)
  if not cfg then return nil end

  local dir = ftpath.parent(file)
  local co = cfg.compilerOptions or {}
  local map = nil

  if type(cfg.extends) == "string" then
    local parent_path = cfg.extends
    if parent_path:sub(1, 1) == "." then
      parent_path = pathutil.abs(dir .. "/" .. parent_path)
      if not parent_path:match("%.json$") then parent_path = parent_path .. ".json" end
      map = load_alias_map(parent_path, depth + 1)
    end
    -- A package-name `extends` ("@tsconfig/node20/tsconfig.json") lives in
    -- node_modules and never carries project-local path aliases, so it is
    -- deliberately not chased.
  end

  if type(co.paths) == "table" then
    -- `paths` are relative to baseUrl when set, and to the config's own
    -- directory otherwise (TS 4.4+ allows paths without baseUrl).
    local base = pathutil.abs(dir .. "/" .. (co.baseUrl or "."))
    map = { base = base, paths = co.paths }
  elseif map and co.baseUrl then
    map = { base = pathutil.abs(dir .. "/" .. co.baseUrl), paths = map.paths }
  end

  return map
end

---@internal
---Alias map governing `file`, or nil when the project has none.
---@param file string
---@return { base: string, paths: table<string, string[]> }|nil
local function alias_map_for(file)
  local dir = ftpath.parent(file)
  local cached = _alias_cache[dir]
  if cached ~= nil then return cached or nil end

  local cfg_file = find_config(dir)
  local map = cfg_file and load_alias_map(cfg_file, 1) or nil
  _alias_cache[dir] = map or false
  return map
end

---Drop the tsconfig cache (config files can change between operations).
function M.reset_cache()
  _alias_cache = {}
end

---@internal
---Every filesystem path an alias specifier could denote.
---@param spec string
---@param file string
---@return string[]
local function alias_candidates(spec, file)
  local map = alias_map_for(file)
  if not map then return {} end

  local out = {}
  for pattern, targets in pairs(map.paths) do
    local prefix, suffix = pattern:match("^(.-)%*(.-)$")
    if prefix then
      if spec:sub(1, #prefix) == prefix and (suffix == "" or spec:sub(-#suffix) == suffix) then
        local captured = spec:sub(#prefix + 1, #spec - #suffix)
        for _, t in ipairs(targets) do
          out[#out + 1] = pathutil.abs(map.base .. "/" .. (t:gsub("%*", captured)))
        end
      end
    elseif spec == pattern then
      for _, t in ipairs(targets) do
        out[#out + 1] = pathutil.abs(map.base .. "/" .. t)
      end
    end
  end
  return out
end

---@internal
---Express `new_path` through the same alias `spec` used, when it still lives
---under that alias' target directory.
---@param spec string
---@param file string
---@param new_path string
---@return string|nil
local function alias_retarget(spec, file, new_path)
  local map = alias_map_for(file)
  if not map then return nil end

  for pattern, targets in pairs(map.paths) do
    local prefix, suffix = pattern:match("^(.-)%*(.-)$")
    if prefix and spec:sub(1, #prefix) == prefix then
      for _, t in ipairs(targets) do
        local t_prefix = t:match("^(.-)%*") or t
        local base_dir = pathutil.abs(map.base .. "/" .. t_prefix):gsub("/+$", "")
        if pathutil.under(new_path, base_dir) then
          local rest = pathutil.relative(new_path, base_dir)
          return prefix .. rest .. suffix
        end
      end
    end
  end
  return nil
end

-- ── Specifier scanning ────────────────────────────────────────────────────────

---@internal
---Walk every module specifier in `text`, calling `fn(col, spec)` with the
---1-based byte column the specifier starts at (inside its quotes).
---@param text string
---@param fn fun(col: integer, spec: string)
local function each_specifier(text, fn)
  -- The keyword forms that introduce a specifier. Each pattern ends right
  -- before the opening quote so the column arithmetic below is uniform.
  local leads = {
    "from%s*[\"']",
    "import%s*[\"']",
    "import%s*%(%s*[\"']",
    "require%s*%(%s*[\"']",
  }
  for _, lead in ipairs(leads) do
    local init = 1
    while true do
      local s, e = text:find(lead, init)
      if not s then break end
      local quote = text:sub(e, e)
      local close = text:find(quote, e + 1, true)
      if close then
        local spec = text:sub(e + 1, close - 1)
        if spec ~= "" then fn(e + 1, spec) end
        init = close + 1
      else
        init = e + 1
      end
    end
  end
end

---@internal
---Whether `resolved` (a specifier resolved to a filesystem path, possibly
---without extension) denotes `wanted`. Returns the concrete path it matched.
---@param resolved string
---@param wanted string
---@param is_dir boolean
---@return string? matched
local function resolves_to(resolved, wanted, is_dir)
  if is_dir then
    if pathutil.same(resolved, wanted) or pathutil.under(resolved, wanted) then
      return resolved
    end
    return nil
  end
  if pathutil.same(resolved, wanted) then return resolved end

  ---@param base string
  ---@return string?
  local function try(base)
    for _, ext in ipairs(RESOLVE_EXTS) do
      if pathutil.same(base .. ext, wanted) then return base .. ext end
      if pathutil.same(base .. "/index" .. ext, wanted) then return base .. "/index" .. ext end
    end
    return nil
  end

  local hit = try(resolved)
  if hit then return hit end

  -- ESM-on-TypeScript: `./x.js` is the correct specifier for `x.ts`, so a
  -- specifier that already carries an extension still has to be matched
  -- against the other extensions of the same stem.
  local base = strip_ext(resolved)
  if base ~= resolved then return try(base) end
  return nil
end

---@param old_path string
---@param ctx FiletreeRefCtx
---@return FiletreeRefPlan|nil
function M.plan(old_path, ctx)
  local name = ftpath.basename(old_path)
  if name == "" then return nil end

  -- An `index.ts` is imported through its *directory* name, so that is the
  -- string to pre-filter on.
  local stem = strip_ext(name)
  local needle = stem
  if stem == "index" and not ctx.is_dir then
    needle = ftpath.basename(ftpath.parent(old_path))
  end
  if needle == "" then return nil end

  M.reset_cache()

  return {
    needles = { needle },
    extensions = EXTENSIONS,

    extract = function(file, lineno, text)
      local refs = {}
      each_specifier(text, function(col, spec)
        local kind, matched
        if spec:sub(1, 1) == "." then
          local abs = pathutil.abs(ftpath.parent(file) .. "/" .. spec)
          matched = resolves_to(abs, old_path, ctx.is_dir)
          kind = "relative"
        else
          for _, cand in ipairs(alias_candidates(spec, file)) do
            matched = resolves_to(cand, old_path, ctx.is_dir)
            if matched then break end
          end
          kind = "alias"
        end
        if not matched then return end

        refs[#refs + 1] = {
          file = file,
          line = lineno,
          col = col,
          text = text,
          target = spec,
          provider = M.name,
          source = old_path,
          kind = kind,
          resolved = matched,
          display = string.format("%s:%d: %s",
            vim.fn.fnamemodify(file, ":."), lineno, vim.trim(text)),
        }
      end)
      return refs
    end,

    retarget = function(ref, new_path)
      local dest = new_path
      if ctx.is_dir and ref.resolved then
        dest = pathutil.remap_under(ref.resolved, old_path, new_path)
      end

      -- An explicit extension in the original specifier is kept verbatim: in
      -- ESM-on-TypeScript, `./x.js` is the *correct* way to import `x.ts`, so
      -- rewriting it to the file's real extension would break the import.
      local orig_ext = ref.target:match("(%.[cm]?[tj]sx?)$")
      local had_index = ref.target:match("/index$") ~= nil

      local function shape(base)
        if orig_ext then return strip_ext(base) .. orig_ext end
        local out = strip_ext(base)
        if not had_index then out = out:gsub("/index$", "") end
        return out
      end

      if ref.kind == "alias" then
        local aliased = alias_retarget(ref.target, ref.file, dest)
        if aliased then return shape(aliased) end
        -- Moved out of every alias root: fall through to a relative specifier
        -- rather than leaving a now-wrong alias behind.
      end

      local rel = pathutil.relative(dest, ftpath.parent(ref.file))
      rel = shape(rel)
      if rel:sub(1, 1) ~= "." then rel = "./" .. rel end
      return rel
    end,
  }
end

return M
