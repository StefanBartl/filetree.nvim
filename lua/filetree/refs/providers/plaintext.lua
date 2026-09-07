---@module 'filetree.refs.providers.plaintext'
--- Experimental: rewrite bare filesystem paths written as running text.
---
--- The syntax-anchored providers (markdown, lua, python, ts_js) each know a
--- grammar — `](target)`, `require("a.b")`, `from a.b import x`. A path a
--- human simply *wrote out* in a sentence or a code comment
--- (`see ../Test/Tester.md for the format`) matches none of them and so was
--- silently left dangling after a rename or move. This provider closes that
--- gap: it scans prose/text files line by line (and, opt-out, comment lines
--- in source files) for path-like tokens and hands them to the same
--- resolve-then-compare machinery every other provider uses.
---
--- It is deliberately opt-in (`refs.experimental.plaintext.enabled`): a bare
--- token has a wider false-positive surface than a bracketed link, so the
--- resolver is the only thing standing between "looks like a path" and "is
--- rewritten" — a token is touched only when it *resolves to exactly the file
--- that moved*, exactly as `pathutil` decides for the markdown provider.
---
--- What it does NOT do:
---   • touch a token already inside link/attr/refdef/wiki syntax — that is the
---     markdown provider's job, and doing both would double-edit the line;
---   • touch a string literal on a real code line — only comment text is
---     scanned in source files, and only when `comments` is on;
---   • follow external URLs, `mailto:` etc. or pure `#anchors`.

local ftpath = require("filetree.util.path")
local pathutil = require("filetree.refs.pathutil")

local M = {}

M.name = "plaintext"

---No language server rewrites a path written in prose, so this provider runs
---even when an LSP client already handled the rename (mirrors markdown/lua).
M.lsp_exempt = true

-- ── Built-in extension lists ──────────────────────────────────────────────────
-- Used when the user has not set an explicit list in
-- `refs.experimental.plaintext.{extensions,comment_extensions}`. Kept out of
-- `refs/DEFAULTS.lua` on purpose: `vim.tbl_deep_extend` merges list-shaped
-- tables by index, so a user list shorter than the default would leave stray
-- trailing defaults behind. A nil in the config means "use this list as-is".

---Files scanned in full (every line is prose).
local PROSE_EXTS = {
  "md",
  "markdown",
  "mdx",
  "mdown",
  "mkd",
  "markdn",
  "txt",
  "text",
  "rst",
  "org",
  "adoc",
  "asciidoc",
  "norg",
  "wiki",
}

---Source files where only comment lines are scanned.
local COMMENT_EXTS = {
  "lua",
  "py",
  "pyi",
  "js",
  "jsx",
  "ts",
  "tsx",
  "sh",
  "bash",
  "zsh",
  "vim",
  "c",
  "h",
  "cpp",
  "hpp",
  "cc",
  "rs",
  "go",
  "rb",
  "java",
  "toml",
  "yaml",
  "yml",
}

---Comment lead-ins per extension. The scanner takes everything from the first
---occurrence of any lead-in to end of line; block-comment markers (`/*`,
---`<!--`) are included so a `/* … path … */` line is covered too.
local COMMENT_LEADERS = {
  lua = { "--" },
  py = { "#" },
  pyi = { "#" },
  rb = { "#" },
  sh = { "#" },
  bash = { "#" },
  zsh = { "#" },
  toml = { "#" },
  yaml = { "#" },
  yml = { "#" },
  js = { "//", "/*", "*" },
  jsx = { "//", "/*", "*" },
  ts = { "//", "/*", "*" },
  tsx = { "//", "/*", "*" },
  c = { "//", "/*", "*" },
  h = { "//", "/*", "*" },
  cpp = { "//", "/*", "*" },
  hpp = { "//", "/*", "*" },
  cc = { "//", "/*", "*" },
  rs = { "//", "/*", "*" },
  go = { "//", "/*", "*" },
  java = { "//", "/*", "*" },
  vim = { '"' },
}

-- ── Small local helpers (URL encode/decode mirror the markdown provider) ──────

---@param s string
---@return string
local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

---@param s string
---@return string
local function url_encode(s)
  return (s:gsub("[ ()]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

---@param t string
---@return boolean
local function is_external(t)
  if t == "" then return true end
  if t:sub(1, 1) == "#" then return true end
  -- scheme (http:, mailto:, tel:) — but not a Windows drive letter (`C:\`)
  if t:match("^%a[%w+.%-]*:") and not t:match("^%a:[/\\]") then return true end
  return false
end

---Cheap pre-filter: does `tok` look enough like a path to be worth resolving?
---The resolver is the real gate — this only rejects the obvious non-paths so a
---dotted identifier in a comment (`pkg.util.shared`) never reaches it.
---@param tok string
---@return boolean
local function looks_like_path(tok)
  if tok == "" then return false end
  if tok:match("[/\\]") then return true end -- has a separator
  if tok:match("^~[/\\]") then return true end -- home-relative
  if tok:match("^%.%.?[/\\]") then return true end -- ./ or ../
  -- No separator: accept only a plain `name.ext` (single dot), so a
  -- multi-segment module name like `a.b.c` is not mistaken for a file.
  return tok:match("^[%w][%w%-]*%.%w[%w]*$") ~= nil
end

---Characters that may appear inside a path token. Whitespace, quotes,
---brackets, `#`, `?`, `,`, `;`, `*` and `|` terminate it.
---@param c string
---@return boolean
local function is_path_char(c)
  return c:match("[%w%._/\\~:%%%+%-@]") ~= nil
end

---The slice of `text` that a source-file scanner should look at, plus the
---0-based column offset of that slice within `text` (so recorded columns stay
---relative to the full line, which is what `refs.apply` verifies against).
---@param text string
---@param ext string
---@return string? body, integer offset
local function comment_body(text, ext)
  local leaders = COMMENT_LEADERS[ext]
  if not leaders then return nil, 0 end
  local best_i, best_len
  for _, ld in ipairs(leaders) do
    local i = text:find(ld, 1, true)
    if i and (not best_i or i < best_i) then
      best_i, best_len = i, #ld
    end
  end
  if not best_i then return nil, 0 end
  local rest = best_i + best_len
  local ws = text:match("^(%s*)", rest) or ""
  local start = rest + #ws
  return text:sub(start), start - 1
end

---Whether the characters right before column `l` in `line` put the token
---inside a construct the markdown provider already owns.
---@param line string
---@param l integer  1-based column the token starts at
---@return boolean
local function in_link_syntax(line, l)
  local before = line:sub(1, l - 1)
  return before:match("%]%(<?$") ~= nil -- ](  or  ](<
    or before:match("%]:%s*$") ~= nil -- [id]:
    or before:match("%[%[$") ~= nil -- [[wiki
    or before:match("src%s*=%s*[\"']?$") ~= nil -- HTML src=
    or before:match("href%s*=%s*[\"']?$") ~= nil -- HTML href=
end

-- ── Provider ─────────────────────────────────────────────────────────────────

---@param old_path string
---@param ctx FiletreeRefCtx
---@return FiletreeRefPlan|nil
function M.plan(old_path, ctx)
  local ex = ctx.cfg and ctx.cfg.experimental and ctx.cfg.experimental.plaintext
  if not (ex and ex.enabled) then return nil end

  local name = ftpath.basename(old_path)
  if name == "" then return nil end

  local scan_comments = ex.comments ~= false
  local exts = {}
  vim.list_extend(exts, ex.extensions or PROSE_EXTS)
  if scan_comments then vim.list_extend(exts, ex.comment_extensions or COMMENT_EXTS) end

  local prose = {}
  for _, e in ipairs(ex.extensions or PROSE_EXTS) do
    prose[e:lower()] = true
  end

  local needles = { name }
  if name:find(" ", 1, true) then needles[#needles + 1] = url_encode(name) end

  return {
    needles = needles,
    extensions = exts,

    extract = function(file, lineno, text)
      local ext = (file:match("%.([%w_]+)$") or ""):lower()
      local body, offset
      if prose[ext] then
        body, offset = text, 0
      elseif scan_comments then
        body, offset = comment_body(text, ext)
        if not body then return {} end
      else
        return {}
      end

      local refs = {}
      local seen = {}

      for _, needle in ipairs(needles) do
        local from = 1
        while true do
          local s = body:find(needle, from, true)
          if not s then break end
          from = s + 1
          local e = s + #needle - 1

          -- Expand outward to the full path token.
          local l, r = s, e
          while l > 1 and is_path_char(body:sub(l - 1, l - 1)) do
            l = l - 1
          end
          while r < #body and is_path_char(body:sub(r + 1, r + 1)) do
            r = r + 1
          end

          -- Trim a trailing `:line` / `#anchor` / `?query` and prose
          -- punctuation; drop leading opening brackets/quotes.
          local tok = body:sub(l, r)
          local anchor = tok:find("[#?]")
          if anchor then
            r = l + anchor - 2
            tok = body:sub(l, r)
          end
          local ln_suffix = tok:match(":(%d+)$")
          if ln_suffix then
            r = r - (#ln_suffix + 1)
            tok = body:sub(l, r)
          end
          while tok ~= "" and tok:sub(-1):match("[%.,;:!%)]") do
            r = r - 1
            tok = body:sub(l, r)
          end
          while tok ~= "" and tok:sub(1, 1):match("[%(%[<\"'`]") do
            l = l + 1
            tok = body:sub(l, r)
          end

          if
            tok ~= ""
            and not seen[l]
            and looks_like_path(tok)
            and not is_external(tok)
            and not in_link_syntax(body, l)
          then
            local resolved, style =
              pathutil.match(url_decode(tok), file, ctx.root, old_path, ctx.is_dir)
            if resolved then
              seen[l] = true
              refs[#refs + 1] = {
                file = file,
                line = lineno,
                col = offset + l,
                text = text,
                target = tok,
                provider = M.name,
                source = old_path,
                style = style,
                resolved = resolved,
                encoded = tok:find("%%%x%x") ~= nil,
                display = string.format(
                  "%s:%d: %s",
                  vim.fn.fnamemodify(file, ":."),
                  lineno,
                  vim.trim(text)
                ),
              }
            end
          end
        end
      end

      return refs
    end,

    retarget = function(ref, new_path)
      local dest = new_path
      if ctx.is_dir and ref.resolved then
        dest = pathutil.remap_under(ref.resolved, old_path, new_path)
      end
      local out = pathutil.retarget({
        style = ref.style or "relative",
        target = ref.target,
        from_file = ref.file,
        root = ctx.root,
        new_path = dest,
      })
      if ref.encoded then out = url_encode(out) end
      return out
    end,
  }
end

return M
