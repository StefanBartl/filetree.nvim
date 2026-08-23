---@module 'filetree.refs.providers.markdown'
--- Markdown reference provider: `[text](./path)`, `![alt](./img.png)`,
--- reference definitions (`[id]: ./path`), HTML `src=`/`href=` attributes and
--- (opt-in) wiki links `[[path]]`.
---
--- A markdown file can link to *anything*, not just other markdown — images,
--- PDFs, source files — so this provider plans for every moved path, whatever
--- its type.
---
--- Matching never compares link text to path text. Each candidate target is
--- resolved against the file it appears in (`./x`, `../x`, `x`, `~/x`, `/x`
--- read both as filesystem- and as project-root-relative) and only the
--- resulting absolute path is compared — see `filetree.refs.pathutil`.
---
--- Rewrites preserve style: an absolute link stays absolute, a `./` link keeps
--- its `./`, a root-relative one keeps its leading slash, and anchors/titles
--- (`](x.md#section "Title")`) are left untouched because only the path slice
--- of the target is replaced.

local ftpath = require("filetree.util.path")
local pathutil = require("filetree.refs.pathutil")

local M = {}

M.name = "markdown"

---No language server rewrites markdown links, so this provider runs even when
---an LSP client already handled the rename (see `refs.prefer_lsp`).
M.lsp_exempt = true

---What a link to a *deleted* file is rewritten to, so the dangling reference
---is visible instead of silently pointing into nothing.
M.delete_target = "REF!"

---Files that can hold markdown references.
local EXTENSIONS = { "md", "markdown", "mdx", "mdown", "qmd", "rmd" }

-- ── Target scanning ───────────────────────────────────────────────────────────

---@internal
---Percent-decode a URL-ish link target (`%20` → " ").
---@param s string
---@return string
local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

---@internal
---Percent-encode the characters that must not appear raw in a markdown target.
---@param s string
---@return string
local function url_encode(s)
  return (s:gsub("[ ()]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

---@internal
---Whether `t` points somewhere this provider must not touch (external URL,
---protocol, pure anchor, empty).
---@param t string
---@return boolean
local function is_external(t)
  if t == "" then return true end
  if t:sub(1, 1) == "#" then return true end
  if t:match("^%a[%w+.%-]*:") and not t:match("^%a:[/\\]") then
    return true -- scheme (http:, mailto:, tel:) — but not a Windows drive
  end
  return false
end

---@internal
---Split a raw target into its path part and the trailing anchor/query, so only
---the path is ever rewritten.
---@param raw string
---@return string path_part
local function path_part(raw)
  local cut = raw:find("[#?]")
  if cut then return raw:sub(1, cut - 1) end
  return raw
end

---@internal
---Walk every link-like target in `text`, calling `fn(col, raw_target, kind)`
---with the 1-based byte column the raw target starts at.
---@param text string
---@param cfg FiletreeRefsConfig
---@param fn fun(col: integer, raw: string, kind: "inline"|"refdef"|"html"|"wiki")
local function each_target(text, cfg, fn)
  -- 1. Inline links and images: ](target) and ](<target with spaces>)
  local pos = 1
  while true do
    local s = text:find("](", pos, true)
    if not s then break end
    local open = s + 2
    if text:sub(open, open) == "<" then
      local close = text:find(">", open + 1, true)
      if close then fn(open + 1, text:sub(open + 1, close - 1), "inline") end
      pos = (close or open) + 1
    else
      local close = text:find(")", open, true)
      if not close then break end
      local inner = text:sub(open, close - 1)
      -- `](path "Title")` — the title starts at the first whitespace.
      local raw = inner:match("^(%S*)") or inner
      if raw ~= "" then fn(open, raw, "inline") end
      pos = close + 1
    end
  end

  -- 2. Reference definitions: `[id]: ./path "Title"`
  do
    local _, _, prefix, target = text:find("^(%s*%[[^%]]*%]:%s*)(%S+)")
    if prefix and target then fn(#prefix + 1, target, "refdef") end
  end

  -- 3. HTML attributes inside markdown: src="…", href='…'
  for _, attr in ipairs({ "src", "href" }) do
    local init = 1
    while true do
      local s, e, value = text:find(attr .. "%s*=%s*[\"']([^\"']*)", init)
      if not s then break end
      if value ~= "" then fn(e - #value + 1, value, "html") end
      init = e + 1
    end
  end

  -- 4. Wiki links: [[target]] / [[target|alias]] — opt-in, not standard markdown.
  if cfg and cfg.wiki_links then
    local init = 1
    while true do
      local s, e, value = text:find("%[%[([^%]]+)%]%]", init)
      if not s then break end
      local target = value:match("^([^|]+)") or value
      fn(s + 2, target, "wiki")
      init = e + 1
    end
  end
end

---@internal
---Wiki links are their own little world: the extension is usually omitted and
---the target may be written relative to the *vault root* rather than to the
---file it appears in. So instead of the one resolution `pathutil.match` does,
---try both bases against both spellings, and remember which one hit so the
---rewrite can reproduce it.
---@param target string
---@param file string
---@param root string
---@param wanted string
---@param is_dir boolean
---@return string? resolved, "relative"|"root"|nil style, string? omitted_ext
local function wiki_match(target, file, root, wanted, is_dir)
  local bases = {
    { dir = ftpath.parent(file), style = "relative" },
    { dir = root, style = "root" },
  }
  for _, base in ipairs(bases) do
    for _, ext in ipairs({ "", ".md", ".markdown" }) do
      local cand = pathutil.abs(base.dir .. "/" .. target .. ext)
      local hit = is_dir and pathutil.under(cand, wanted) or pathutil.same(cand, wanted)
      if hit then return cand, base.style, ext end
    end
  end
  return nil, nil, nil
end

-- ── Provider ──────────────────────────────────────────────────────────────────

---@param old_path string
---@param ctx FiletreeRefCtx
---@return FiletreeRefPlan|nil
function M.plan(old_path, ctx)
  local name = ftpath.basename(old_path)
  if name == "" then return nil end

  local needles = { name }
  if name:find(" ", 1, true) then needles[#needles + 1] = url_encode(name) end
  if ctx.cfg and ctx.cfg.wiki_links then
    local stem = name:gsub("%.[%w_]+$", "")
    if stem ~= name then needles[#needles + 1] = stem end
  end

  return {
    needles = needles,
    extensions = EXTENSIONS,

    extract = function(file, lineno, text)
      local refs = {}
      each_target(text, ctx.cfg, function(col, raw, kind)
        if is_external(raw) then return end
        local target = path_part(raw)
        if target == "" then return end

        local resolved, style, omitted_ext
        if kind == "wiki" then
          resolved, style, omitted_ext =
            wiki_match(url_decode(target), file, ctx.root, old_path, ctx.is_dir)
        else
          resolved, style = pathutil.match(
            url_decode(target), file, ctx.root, old_path, ctx.is_dir)
        end
        if not resolved then return end

        refs[#refs + 1] = {
          file = file,
          line = lineno,
          col = col,
          text = text,
          target = target,
          provider = M.name,
          source = old_path,
          style = style,
          resolved = resolved,
          kind = kind,
          omitted_ext = omitted_ext,
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
      local out
      if ref.kind == "wiki" then
        -- A wiki target carries no leading slash even when it is vault-root
        -- relative, and keeps its extension omitted if the original did.
        local base = ref.style == "root" and ctx.root or ftpath.parent(ref.file)
        out = pathutil.relative(dest, base)
        if ref.omitted_ext and ref.omitted_ext ~= "" then
          out = out:sub(1, #out - #ref.omitted_ext)
        end
      else
        out = pathutil.retarget({
          style = ref.style or "relative",
          target = ref.target,
          from_file = ref.file,
          root = ctx.root,
          new_path = dest,
        })
      end
      -- Only re-encode when the original target was encoded too; a link
      -- written with a literal space keeps its literal space.
      if ref.target:find("%%%x%x") then out = url_encode(out) end
      return out
    end,
  }
end

return M
