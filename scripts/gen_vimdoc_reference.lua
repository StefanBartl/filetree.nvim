-- Generate the FEATURE REFERENCE section of doc/filetree.txt.
--
-- Why this exists: `doc/filetree.txt` carried hand-written sections for ten
-- features while the registry had fifty-nine, so `:help filetree-trash` -- and
-- forty-eight others -- simply did not resolve. The prose for all of them
-- already existed in `docs/FEATURES/*.md`; the vimdoc was not missing content,
-- it was missing a copy of it. Copying it by hand once would have fixed today
-- and re-broken on the next feature, so it is generated instead.
--
-- What it does NOT touch: the ten hand-written sections (5.1 - 5.12). Several
-- are far deeper than anything derivable from the markdown (cwd_mode alone runs
-- 250 lines), and they stay exactly as they are. This only appends 5.13, and
-- only covers features that have no section of their own -- a feature that
-- gains a hand-written section later drops out of here automatically, because
-- the check is "does a tag for it already exist".
--
-- Usage, from the repository root:
--   nvim --clean --headless -u NONE -l scripts/gen_vimdoc_reference.lua
--   nvim --clean --headless -u NONE -l scripts/gen_vimdoc_reference.lua --check
--
-- `--check` writes nothing and exits 1 when the file on disk differs from what
-- would be generated -- that is the CI gate against drift.

local WIDTH = 78
local SECTION = "5.13"
local SECTION_TITLE = "FEATURE REFERENCE"
local SECTION_TAG = "filetree-feature-reference"

-- ── Locate the repo, put it (and lib.nvim) on the rtp ────────────────────────

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root)

local lib_candidates = {}
for _, env in ipairs({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH" }) do
  local v = vim.env[env]
  if v and v ~= "" then lib_candidates[#lib_candidates + 1] = v end
end
lib_candidates[#lib_candidates + 1] = vim.fn.fnamemodify(root, ":h") .. "/lib.nvim"
lib_candidates[#lib_candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"
for _, candidate in ipairs(lib_candidates) do
  if vim.fn.isdirectory(candidate .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(candidate)
    break
  end
end

local DOC = root .. "/doc/filetree.txt"
local FEATURES_DIR = root .. "/docs/FEATURES"

-- ── Text helpers ─────────────────────────────────────────────────────────────

---Feature name -> help tag. Registry names use underscores, vimdoc tags in this
---file have always used hyphens (`filetree-cwd-sync` for `cwd_sync`).
---@param name string
---@return string
local function tag_of(name)
  return "filetree-" .. name:gsub("_", "-")
end

---Title-case a registry name for a heading: `open_replace` -> `OPEN REPLACE`.
---@param name string
---@return string
local function heading_of(name)
  return (name:gsub("_", " "):upper())
end

---A heading line with its tag pushed to the right margin, falling back to a
---line of its own when the two cannot share 78 columns.
---@param left string
---@param tag string
---@return string[]
local function heading_line(left, tag)
  local star = "*" .. tag .. "*"
  local pad = WIDTH - #left - #star
  if pad >= 2 then return { left .. string.rep(" ", pad) .. star } end
  return { left, string.rep(" ", math.max(0, WIDTH - #star)) .. star }
end

---Strip the inline markdown that has no vimdoc equivalent. Backticks stay:
---the hand-written sections already use them for literals, so keeping them
---makes the generated text read like its neighbours.
---@param s string
---@return string
local function inline(s)
  s = s:gsub("%[([^%]]*)%]%([^%)]*%)", "%1") -- [text](link) -> text
  s = s:gsub("%*%*([^%*]+)%*%*", "%1") -- **bold** -> bold (a `*` would be a tag)
  s = s:gsub("<!%-%-.-%-%->", "")
  return s
end

---Wrap `text` to the margin, indented by `indent`, with `hanging` applied to
---every line after the first (so list bullets line up under their own text).
---@param text string
---@param indent string
---@param hanging? string
---@return string[]
local function wrap(text, indent, hanging)
  hanging = hanging or indent
  local out, line = {}, nil
  for word in text:gmatch("%S+") do
    local prefix = (#out == 0) and indent or hanging
    if not line then
      line = prefix .. word
    elseif #line + 1 + #word <= WIDTH then
      line = line .. " " .. word
    else
      out[#out + 1] = line
      line = hanging .. word
    end
  end
  if line then out[#out + 1] = line end
  return out
end

-- ── Markdown parsing ─────────────────────────────────────────────────────────

---One `## ` section of a FEATURES markdown file.
---@class GenSection
---@field title string
---@field body string[]    Prose lines, before the trailing metadata list.
---@field meta table<string, string>  "Module"/"Keymaps"/"Config"/"Commands" -> value

---Split a markdown file into its `## ` sections.
---@param path string
---@return GenSection[]
local function parse_markdown(path)
  local lines = vim.fn.readfile(path)
  local sections, cur = {}, nil
  for _, raw in ipairs(lines) do
    local title = raw:match("^##%s+(.+)$")
    if title then
      cur = { title = title, body = {}, meta = {} }
      sections[#sections + 1] = cur
    elseif cur then
      -- The trailing `- **Module:** ...` block is metadata, not prose.
      local key, value = raw:match("^%-%s+%*%*([%w%s]+):%*%*%s*(.*)$")
      if key then
        cur.meta[key] = value
      else
        cur.body[#cur.body + 1] = raw
      end
    end
  end
  return sections
end

---The registry feature a section documents, read off its `Module:` path.
---Sections whose module is not under `features/` (the adapters, the reference
---engine) describe something other than a feature and return nil.
---@param section GenSection
---@return string?
local function feature_of(section)
  local mod = section.meta["Module"]
  if not mod then return nil end
  return mod:match("features/[%w_]+/([%w_]+)")
end

-- ── Markdown body -> vimdoc lines ────────────────────────────────────────────

---Render one section's prose as vimdoc, at `indent`.
---@param body string[]
---@param indent string
---@return string[]
local function render_body(body, indent)
  local out = {}
  local para = {}
  local in_code = false

  local function flush_para()
    if #para == 0 then return end
    vim.list_extend(out, wrap(inline(table.concat(para, " ")), indent))
    para = {}
  end

  for _, raw in ipairs(body) do
    local fence = raw:match("^%s*```(%w*)")
    if fence then
      flush_para()
      if in_code then
        out[#out + 1] = "<"
        in_code = false
      else
        -- `>lua` opens a highlighted literal block; `<` closes it.
        out[#out + 1] = ">" .. (fence ~= "" and fence or "")
        in_code = true
      end
    elseif in_code then
      out[#out + 1] = indent .. raw
    else
      local line = raw:gsub("%s+$", "")
      local sub = line:match("^###%s+(.+)$")
      local bullet_indent, bullet = line:match("^(%s*)[%-%*]%s+(.+)$")
      local table_row = line:match("^%s*|(.+)")

      if line == "" then
        flush_para()
        if out[#out] ~= "" then out[#out + 1] = "" end
      elseif sub then
        flush_para()
        if out[#out] ~= "" then out[#out + 1] = "" end
        out[#out + 1] = indent .. inline(sub)
        out[#out + 1] = indent .. string.rep("~", #inline(sub))
      elseif table_row then
        -- Seven rows in the whole corpus; a real table renderer would be more
        -- machinery than the case is worth. Keep the cells, drop the pipes.
        flush_para()
        local cells = {}
        for cell in (table_row .. "|"):gmatch("([^|]*)|") do
          cell = vim.trim(inline(cell))
          if cell ~= "" and not cell:match("^[%-%s:]+$") then cells[#cells + 1] = cell end
        end
        if #cells > 0 then
          vim.list_extend(
            out,
            wrap(table.concat(cells, "  ·  "), indent .. "  ", indent .. "     ")
          )
        end
      elseif bullet then
        flush_para()
        local depth = indent .. string.rep(" ", #bullet_indent)
        vim.list_extend(out, wrap(inline(bullet), depth .. "• ", depth .. "  "))
      else
        para[#para + 1] = vim.trim(line)
      end
    end
  end
  flush_para()

  -- An unterminated fence would swallow the rest of the help file.
  if in_code then out[#out + 1] = "<" end

  while out[1] == "" do
    table.remove(out, 1)
  end
  while out[#out] == "" do
    out[#out] = nil
  end
  return out
end

-- ── Build the section ────────────────────────────────────────────────────────

local function build()
  local FEATURES = require("filetree.features").FEATURES
  local catalog = require("filetree.bindings").catalog()

  -- Keys per feature, from the catalog rather than the markdown's own
  -- "Keymaps:" line: the catalog is what actually gets bound.
  local keys = {}
  for _, list in pairs(catalog.keymaps) do
    for _, e in ipairs(list) do
      keys[e.feature] = keys[e.feature] or {}
      table.insert(keys[e.feature], e.lhs)
    end
  end

  local existing = table.concat(vim.fn.readfile(DOC), "\n")

  -- Collect the documentable sections, skipping any feature that already has a
  -- hand-written section (its tag is already in the file).
  local found = {}
  local names = vim.fn.readdir(FEATURES_DIR)
  table.sort(names)
  for _, file in ipairs(names) do
    if file:match("%.md$") and file ~= "README.md" then
      for _, section in ipairs(parse_markdown(FEATURES_DIR .. "/" .. file)) do
        local name = feature_of(section)
        if name and FEATURES[name] then
          local tag = tag_of(name)
          -- The section we generate is the one place this tag may already
          -- appear, so look for it outside our own output.
          local hand_written = existing:find("%*" .. vim.pesc(tag) .. "%*") ~= nil
            and not existing:find("%*" .. vim.pesc(tag) .. "%*.-" .. vim.pesc(SECTION_TAG))
          if not found[name] then
            found[name] = {
              name = name,
              title = section.title,
              body = section.body,
              meta = section.meta,
              category = FEATURES[name].category,
              hand_written = hand_written,
            }
          end
        end
      end
    end
  end

  -- Re-test "already documented" against the file with our own section removed,
  -- so a regeneration does not decide every feature is hand-written.
  local without_ours = existing
  local s = without_ours:find("\n" .. vim.pesc(SECTION) .. " " .. vim.pesc(SECTION_TITLE))
  if s then without_ours = without_ours:sub(1, s) end

  local entries = {}
  for name, e in pairs(found) do
    if not without_ours:find("%*" .. vim.pesc(tag_of(name)) .. "%*") then
      entries[#entries + 1] = e
    end
  end
  table.sort(entries, function(a, b)
    if a.category ~= b.category then return a.category < b.category end
    return a.name < b.name
  end)

  -- ── Emit ───────────────────────────────────────────────────────────────────
  local out = {}
  out[#out + 1] = string.rep("=", WIDTH)
  vim.list_extend(out, heading_line(SECTION .. " " .. SECTION_TITLE, SECTION_TAG))
  out[#out + 1] = ""
  vim.list_extend(
    out,
    wrap(
      "Every feature that has no section of its own above. Generated from "
        .. "docs/FEATURES/*.md and the binding catalog by "
        .. "scripts/gen_vimdoc_reference.lua -- edit those, not this section.",
      ""
    )
  )
  out[#out + 1] = ""
  vim.list_extend(
    out,
    wrap(
      "The markdown originals carry the tables, worked examples and cross-links "
        .. "that do not survive the trip into help format; reach for them when "
        .. "an entry here is thinner than the question you arrived with.",
      ""
    )
  )
  out[#out + 1] = ""

  -- Index, grouped by category.
  local last_category = nil
  for _, e in ipairs(entries) do
    if e.category ~= last_category then
      out[#out + 1] = ""
      out[#out + 1] = e.category:upper()
      last_category = e.category
    end
    local left = "  " .. e.title
    local ref = "|" .. tag_of(e.name) .. "|"
    local dots = WIDTH - #left - #ref - 1
    out[#out + 1] = left .. " " .. string.rep(".", math.max(1, dots)) .. ref
  end

  for _, e in ipairs(entries) do
    out[#out + 1] = ""
    out[#out + 1] = string.rep("-", WIDTH)
    vim.list_extend(out, heading_line(heading_of(e.name), tag_of(e.name)))
    out[#out + 1] = ""
    vim.list_extend(out, render_body(e.body, ""))

    -- Catalog order, not sorted: it groups a feature's keys the way the feature
    -- itself declares them (`d`, `U`, `<leader>th`), where sorting would lead
    -- with `<leader>th` on punctuation alone.
    local klist = keys[e.name]
    if klist and #klist > 0 then
      out[#out + 1] = ""
      vim.list_extend(out, wrap("Keymaps: " .. table.concat(klist, "  "), "", "         "))
    end
    for _, key in ipairs({ "Config", "Commands", "Usercmds" }) do
      local v = e.meta[key]
      if v and vim.trim(v) ~= "" then
        out[#out + 1] = ""
        vim.list_extend(out, wrap(key .. ": " .. inline(v), "", string.rep(" ", #key + 2)))
      end
    end
    out[#out + 1] = ""
    vim.list_extend(
      out,
      wrap("Module: lua/filetree/features/" .. e.category .. "/" .. e.name .. "/", "")
    )
  end
  out[#out + 1] = ""

  return out, #entries
end

-- ── Splice into doc/filetree.txt ─────────────────────────────────────────────

---@param generated string[]
---@return string[]
local function splice(generated)
  local lines = vim.fn.readfile(DOC)

  -- Replace an existing section, else insert before the "6. ADAPTERS" divider.
  local start_at, stop_at
  for i, l in ipairs(lines) do
    if not start_at and l:match("^" .. vim.pesc(SECTION) .. " " .. vim.pesc(SECTION_TITLE)) then
      start_at = i - 1 -- take the "===" divider above it too
    elseif start_at and not stop_at and l:match("^6%.%s+ADAPTERS") then
      stop_at = i - 2 -- leave that section's own divider in place
    end
  end

  local out = {}
  if start_at then
    for i = 1, start_at - 1 do
      out[#out + 1] = lines[i]
    end
    vim.list_extend(out, generated)
    for i = stop_at + 1, #lines do
      out[#out + 1] = lines[i]
    end
  else
    local insert_before
    for i, l in ipairs(lines) do
      if l:match("^6%.%s+ADAPTERS") then
        insert_before = i - 1 -- the divider line
        break
      end
    end
    assert(insert_before, "could not find the '6. ADAPTERS' section to insert before")
    for i = 1, insert_before - 1 do
      out[#out + 1] = lines[i]
    end
    vim.list_extend(out, generated)
    for i = insert_before, #lines do
      out[#out + 1] = lines[i]
    end
  end

  -- Keep the contents list in step with the section's existence.
  local toc_ref = "|" .. SECTION_TAG .. "|"
  local has_toc = false
  for _, l in ipairs(out) do
    if l:find(toc_ref, 1, true) and l:match("^%s+5%.13") then
      has_toc = true
      break
    end
  end
  if not has_toc then
    for i, l in ipairs(out) do
      if l:match("^%s+5%.12 Move") then
        local left = "     " .. SECTION .. " Feature reference "
        local dots = WIDTH - #left - #toc_ref
        table.insert(out, i + 1, left .. string.rep(".", math.max(1, dots)) .. toc_ref)
        break
      end
    end
  end

  return out
end

-- ── Main ─────────────────────────────────────────────────────────────────────

local check_only = false
for _, a in ipairs(vim.v.argv) do
  if a == "--check" then check_only = true end
end

local generated, count = build()
local new_lines = splice(generated)
local old_lines = vim.fn.readfile(DOC)

local changed = table.concat(old_lines, "\n") ~= table.concat(new_lines, "\n")

if check_only then
  if changed then
    io.stderr:write("doc/filetree.txt is out of date -- run scripts/gen_vimdoc_reference.lua\n")
    vim.cmd("cq 1")
  end
  print(("doc/filetree.txt is up to date (%d generated entries)"):format(count))
  vim.cmd("cq 0")
end

vim.fn.writefile(new_lines, DOC)
print(
  ("wrote doc/filetree.txt: %d generated entries, %d -> %d lines"):format(
    count,
    #old_lines,
    #new_lines
  )
)
vim.cmd("cq 0")
