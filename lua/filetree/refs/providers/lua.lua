---@module 'filetree.refs.providers.lua'
--- Lua `require()` reference provider.
---
--- Covers `require("foo.bar")`, `require "foo.bar"`, `require('foo.bar')` and
--- anything that wraps them (`pcall(require, "foo.bar")` is just a `require`
--- token followed by a quoted string, so it matches too).
---
--- Directory moves cascade: renaming `lua/app/rem/` to `lua/app/remolus/` also
--- rewrites `require("app.rem.sub")` → `require("app.remolus.sub")`. The suffix
--- must start with a literal "." so a same-prefix-different-module
--- (`app.rem_other`) is never touched.
---
--- This is the textual fallback for the language whose server never offers
--- `workspace/willRenameFiles` — lua_ls does not implement it, so without this
--- provider a Lua project silently loses every require() on every move.

local pathutil = require("filetree.refs.pathutil")

local M = {}

M.name = "lua"

---lua_ls never advertises `workspace/fileOperations.willRename`, so a Lua
---project gets no LSP-applied edit to defer to — this provider runs even when
---some other client did handle the rename (see `refs.prefer_lsp`).
M.lsp_exempt = true

---Files that can hold Lua require references.
local EXTENSIONS = { "lua" }

---Absolute `.lua` path → dotted require module name, e.g.
---`".../lua/foo/bar.lua"` → `"foo.bar"`. Mirrors the convention used by
---`paths.lua_require_copy`: a trailing `/init` collapses into its parent.
---
---The leading `.*` is greedy on purpose, so this anchors on the *last*
---`/lua/` segment (the nearest require root) rather than the first — an outer
---ancestor directory that happens to be named `lua` (`~/projects/lua/…`) must
---not be mistaken for it.
---
---`.lua` is stripped when present but not required, so a directory path (a
---renamed directory has no extension at all) resolves too.
---@param abs_path string
---@return string?
function M.module_name(abs_path)
  local rel = pathutil.abs(abs_path):match(".*/lua/(.+)$")
  if not rel then return nil end
  -- pathutil.abs() already strips a trailing slash, but a path that *ends* at
  -- the lua/ root itself would leave `rel` empty rather than "/" — the gsub
  -- below is harmless either way and keeps this independent of that detail.
  rel = rel:gsub("/$", ""):gsub("%.lua$", ""):gsub("/init$", "")
  return (rel:gsub("/", "."))
end

---@internal
---Walk every `require`d module string in `text`, calling `fn(col, module)`
---with the 1-based byte column the module name starts at (inside the quotes).
---@param text string
---@param fn fun(col: integer, mod: string)
local function each_require(text, fn)
  local pos = 1
  while true do
    local s, e = text:find("require", pos, true)
    if not s then break end
    pos = e + 1

    -- Skip an identifier that merely ends in "require" (my_require) or
    -- continues past it (requires_x).
    local before = s > 1 and text:sub(s - 1, s - 1) or ""
    local after = text:sub(e + 1, e + 1)
    if not before:match("[%w_]") and not after:match("[%w_]") then
      -- optional "(" and whitespace, then the opening quote
      local rest_start = e + 1
      local _, skip_end = text:find("^%s*%(?%s*", rest_start)
      local q_pos = (skip_end or rest_start - 1) + 1
      local quote = text:sub(q_pos, q_pos)
      if quote == '"' or quote == "'" then
        local close = text:find(quote, q_pos + 1, true)
        if close then
          fn(q_pos + 1, text:sub(q_pos + 1, close - 1))
          pos = close + 1
        end
      end
    end
  end
end

---@param old_path string
---@param ctx FiletreeRefCtx
---@return FiletreeRefPlan|nil
function M.plan(old_path, ctx)
  -- A path outside any `lua/` root has no module name, so nothing can require
  -- it — that is also what keeps this provider off a moved Python package or
  -- an arbitrary directory.
  local old_mod = M.module_name(old_path)
  if not old_mod then return nil end

  return {
    needles = { old_mod },
    extensions = EXTENSIONS,

    extract = function(file, lineno, text)
      local refs = {}
      each_require(text, function(col, mod)
        local is_exact = mod == old_mod
        local is_child = mod:sub(1, #old_mod + 1) == old_mod .. "."
        if not (is_exact or is_child) then return end

        refs[#refs + 1] = {
          file = file,
          line = lineno,
          col = col,
          text = text,
          target = mod,
          provider = M.name,
          source = old_path,
          suffix = is_child and mod:sub(#old_mod + 1) or "",
          display = string.format(
            "%s:%d: %s",
            vim.fn.fnamemodify(file, ":."),
            lineno,
            vim.trim(text)
          ),
        }
      end)
      return refs
    end,

    retarget = function(ref, new_path)
      local new_mod = M.module_name(new_path)
      if not new_mod then return nil end
      return new_mod .. (ref.suffix or "")
    end,
  }
end

return M
