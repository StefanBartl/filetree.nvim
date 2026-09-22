---@module 'filetree.util.decoration_style'
--- Central "skin" logic for filetree's own line decorations (git_status,
--- size_info, link_marker, lsp_diagnostics, copy_move's clipboard marker)
--- and the breadcrumb bar's root segment.
---
--- Three built-in skins, resolved by name:
---   "plain"             Today's rendering, untouched -- every `M.chip()`
---                        call returns exactly the single `{text, hl}` chunk
---                        the caller would have built by hand. The default;
---                        every skin below is opt-in via `decoration_style`.
---   "rounded"            Wraps the sign/text in a colored pill: the
---                        caller's own highlight group's `fg` becomes the
---                        pill's `bg` (nvim_get_hl only ever gives markers
---                        an `fg`, never a `bg`), text switches to
---                        black/white for contrast
---                        (`ui.theme.palette.contrast_fg`). Capped with
---                        plain Unicode parenthesis-ornament glyphs
---                        (U+2768/U+2769) -- no Nerd Font required.
---   "rounded_nerdfont"   Same pill, capped with true Powerline rounded caps
---                        (U+E0B6/U+E0B4, the same glyphs ui.nvim's tabline
---                        `rounded` style uses) instead -- needs a terminal
---                        font patched with Nerd Font/Powerline glyphs.
---                        Neovim cannot see the terminal's font (see
---                        `lib.nvim.ui.nerd_font`'s own module doc), so this
---                        degrades to "rounded" -- not tofu boxes -- unless
---                        the user declared `vim.g.have_nerd_font = true`,
---                        the same convention `lib.nvim.ui.nerd_font` and
---                        `filetree.integrations.menu` already read.
---
--- Global style, set once from `setup({ decoration_style = ... })` (mirrors
--- `filetree.util.progress`'s `progress_style`). May also be a table keyed by
--- feature name (`git_status`, `size_info`, `link_marker`, `lsp_diagnostics`,
--- `copy_move`, `breadcrumbs`) plus `default`, so one feature runs a
--- different skin than the rest -- e.g. `{ default = "plain", link_marker =
--- "rounded" }`. A name the registry does not know falls back to "plain"
--- (once-per-name notify.warn, not once per render -- these run on every
--- cursor move); register a custom skin -- a host's own look, or a variant
--- with different caps -- via `M.register(name, fn)`, the same registry
--- shape as `ui.tabline.styles`.
---
--- `ui.nvim` is a hard dependency of this plugin already (see
--- docs/installation.md), so `ui.theme.palette` is bare-required below, same
--- as every other ui.nvim touchpoint in this codebase (see e.g.
--- `features.ui.breadcrumbs`'s `set_winbar()` comment).

local notify = require("filetree.util.notify").create("[filetree.decoration_style]")
local palette = require("ui.theme.palette")
local nerd_font = require("lib.nvim.ui.nerd_font")

local M = {}

---@alias FiletreeDecorationChunk { [1]: string, [2]: string? }
---@alias FiletreeDecorationStyleFn fun(text: string, base_hl: string, pos: "eol"|"inline"): FiletreeDecorationChunk[]

---@type table<string, FiletreeDecorationStyleFn>
local _registry = {}

---Names already warned about this session, so a bad `decoration_style` name
---logs once, not once per render.
---@type table<string, true>
local _warned_unknown = {}

-- ── "plain" ───────────────────────────────────────────────────────────────────

---Exactly what every marker built by hand before this module existed -- one
---chunk, spaced the same way the caller's own render loop always did.
---@type FiletreeDecorationStyleFn
local function plain(text, base_hl, pos)
  if pos == "inline" then return { { text .. " ", base_hl } } end
  return { { " " .. text, base_hl } }
end

-- ── "rounded" / "rounded_nerdfont" ───────────────────────────────────────────

---@type table<string, string>  base_hl -> derived chip group name
local _chip_cache = {}
---@type table<string, string>  base_hl -> derived cap group name
local _cap_cache = {}

---Both caches hold nothing but highlight-group NAMES (stable per `base_hl`);
---the colour each name points at is only ever wrong after a `:colorscheme`
---switch, so a single ColorScheme autocmd -- installed once, here, at
---module load -- invalidates both wholesale instead of every `chip_groups()`
---call re-deriving `base_hl`'s live `fg` just to compare it against what was
---cached last time. `chip_groups()` itself then trusts a cache hit outright.
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("filetree_decoration_style", { clear = true }),
  desc = "[filetree] Invalidate decoration_style's derived chip/cap highlight groups",
  callback = function()
    _chip_cache = {}
    _cap_cache = {}
  end,
})

---(Re-)derive the chip highlight group from `base_hl`'s own `fg`, promoted
---to the pill's `bg`, with a contrasting `fg` for the text inside it -- plus
---a cap group of the same colour with no `bg` of its own, so the cap glyph
---blends into whatever sits behind the row instead of squaring off the
---pill's rounded edge. Cached by `base_hl` name alone (see the ColorScheme
---autocmd above for invalidation) -- a cache hit costs one table lookup, no
---`nvim_get_hl`/`nvim_set_hl` call, which matters here: unlike `accent_hl`
---below (once per breadcrumb rebuild), this runs once per *decorated tree
---line*, on every debounced CursorMoved redraw of git_status/size_info/
---link_marker/lsp_diagnostics/copy_move.
---@param base_hl string
---@return string chip_group, string cap_group
local function chip_groups(base_hl)
  local cached = _chip_cache[base_hl]
  if cached then return cached, _cap_cache[base_hl] end

  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = base_hl, link = false })
  local hex = (ok and hl.fg) and ("#%06x"):format(hl.fg) or "#a0a8b7"

  local chip_group = "FiletreeChip_" .. base_hl:gsub("[^%w]", "_")
  local cap_group = chip_group .. "_Cap"
  vim.api.nvim_set_hl(0, chip_group, { bg = hex, fg = palette.contrast_fg(hex), bold = true })
  vim.api.nvim_set_hl(0, cap_group, { fg = hex })

  _chip_cache[base_hl] = chip_group
  _cap_cache[base_hl] = cap_group
  return chip_group, cap_group
end

-- U+2768/U+2769 MEDIUM (LEFT/RIGHT) PARENTHESIS ORNAMENT -- plain Unicode,
-- no Nerd Font needed; stand-in "rounded" caps per the design report's
-- Machbarkeit section.
local CAP_ROUNDED_LEFT, CAP_ROUNDED_RIGHT = "❨", "❩"
-- U+E0B6/U+E0B4, the same Powerline "rounded" cap glyphs as
-- `ui.tabline.styles`' `rounded` style -- needs a Nerd Font-patched terminal
-- font.
local CAP_NERDFONT_LEFT, CAP_NERDFONT_RIGHT = "\xEE\x82\xB6", "\xEE\x82\xB4"

---Build a `FiletreeDecorationStyleFn` for one pair of cap glyphs.
---@param left string
---@param right string
---@return FiletreeDecorationStyleFn
local function pill(left, right)
  return function(text, base_hl, pos)
    local chip_group, cap_group = chip_groups(base_hl)
    local head = { left, cap_group }
    local body = { " " .. text .. " ", chip_group }
    local tail = { right, cap_group }
    if pos == "inline" then return { head, body, tail, { " " } } end
    return { { " " }, head, body, tail }
  end
end

---Warned about the missing Nerd Font declaration already this session, so
---the notify fires once, not once per render.
---@type boolean
local _warned_no_nerdfont = false

local rounded_pill = pill(CAP_ROUNDED_LEFT, CAP_ROUNDED_RIGHT)
local rounded_nerdfont_pill = pill(CAP_NERDFONT_LEFT, CAP_NERDFONT_RIGHT)

_registry.plain = plain
_registry.rounded = rounded_pill
-- Neovim cannot see the terminal's font (see `lib.nvim.ui.nerd_font`'s own
-- module doc), so without an explicit `vim.g.have_nerd_font = true`
-- declaration this degrades to `_registry.rounded` -- looked up by name, not
-- captured as `rounded_pill` above, so a host that later calls
-- `M.register("rounded", ...)` gets its replacement honoured here too --
-- rather than emitting caps that render as tofu boxes. The gate lives on
-- the registry ENTRY itself (not as a name check in `resolve_name()`) so a
-- host that registers its own "rounded_nerdfont" replaces this gate along
-- with the rendering, exactly like registering any other built-in name.
_registry.rounded_nerdfont = function(text, base_hl, pos)
  if nerd_font.available() then return rounded_nerdfont_pill(text, base_hl, pos) end
  if not _warned_no_nerdfont then
    _warned_no_nerdfont = true
    notify.warn(
      'decoration_style "rounded_nerdfont" needs vim.g.have_nerd_font = true'
        .. ' -- falling back to "rounded"'
    )
  end
  return _registry.rounded(text, base_hl, pos)
end

-- ── Registry ──────────────────────────────────────────────────────────────────

---Register a skin under `name` -- a host's own look, or a variant with
---different caps/colouring. Registering one of the three built-in names
---replaces it for the rest of the session -- deliberate, not guarded, the
---same contract as `ui.tabline.styles.register()`.
---@param name string
---@param fn FiletreeDecorationStyleFn
function M.register(name, fn)
  _registry[name] = fn
  _warned_unknown[name] = nil
end

---Remove a registered skin. No-op if `name` was never registered.
---@param name string
function M.unregister(name)
  _registry[name] = nil
end

---Every registered skin name, built-in and host-added alike, sorted.
---@return string[]
function M.list()
  local names = {}
  for name in pairs(_registry) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

---Whether `name` is registered.
---@param name string?
---@return boolean
function M.exists(name)
  return name ~= nil and _registry[name] ~= nil
end

-- ── Style resolution ─────────────────────────────────────────────────────────

---@type string|table<string, string>
local _style = "plain"

---Set the global (or, via a table, per-feature) skin. Mirrors
---`filetree.util.progress.set_style`; called once from `filetree.init`'s
---`M.setup()` with `cfg.decoration_style`.
---@param style string|table<string, string>|nil
function M.set_style(style)
  _style = style or "plain"
end

---Which skin name resolves for `feature` right now: the per-feature entry
---in a table style, else that table's `default`, else a plain string style
---applied to everything, else "plain". A resolved "rounded_nerdfont" is
---returned as-is here -- whether it actually renders Powerline caps or
---degrades to "rounded" is that registry entry's own call (see its
---definition above), not this function's.
---@param feature string
---@return string
local function resolve_name(feature)
  if type(_style) == "table" then return _style[feature] or _style.default or "plain" end
  if type(_style) == "string" then return _style end
  return "plain"
end

---Whether `feature` is currently skinned at all (resolved name ~= "plain").
---Breadcrumbs reads this to decide whether to show/colour its root segment
----- a "new element" (design report §2), gated behind the same opt-in switch
---as the five markers' chip styling rather than always-on.
---@param feature string
---@return boolean
function M.active(feature)
  return resolve_name(feature) ~= "plain"
end

---Render `text` (with the highlight group its caller would have used
---unstyled) through the skin configured for `feature`. Drop the result
---straight into an extmark's `virt_text = ...`.
---@param feature string  Feature name, e.g. "git_status", "link_marker".
---@param text string     The sign/label itself, with no manual spacing --
---                        every skin adds its own.
---@param base_hl string  Highlight group the caller would have used for a
---                        plain, unstyled `{text, base_hl}` chunk.
---@param pos ("eol"|"inline")?  Where the extmark sits (default "eol");
---                        controls which side gets the connecting space.
---@return FiletreeDecorationChunk[]
function M.chip(feature, text, base_hl, pos)
  local name = resolve_name(feature)
  local fn = _registry[name]
  if not fn then
    if not _warned_unknown[name] then
      _warned_unknown[name] = true
      notify.warn(
        ('unknown decoration_style "%s" -- falling back to "plain"'):format(tostring(name))
      )
    end
    fn = _registry.plain
  end
  return fn(text, base_hl, pos or "eol")
end

-- ── cwd_mode accent (breadcrumbs) ────────────────────────────────────────────

---cwd_mode's five root-policy names -- exactly `ui.theme.palette.accent()`'s
---key set (see that module and `features.nav.cwd_mode`). "follow" (no
---policy) is deliberately absent: there is nothing to colour.
---@type table<string, true>
local ACCENT_KEYS = {
  project = true,
  nearest = true,
  lock = true,
  manual = true,
  tree_leads = true,
}

---The live accent colour for a cwd_mode policy name, straight from
---`ui.theme.palette.accent()` (itself always colorscheme-live -- no caching
---needed here either). `nil` for "follow" or any name the palette does not
---know, so callers fall back to their own default highlight.
---@param key string?
---@return string? hex
function M.accent(key)
  if not key or not ACCENT_KEYS[key] then return nil end
  return palette.accent(key)
end

---A stable highlight group name for `key`'s accent colour, (re-)pointed at
---the live `hex` on every call -- cheap, and (like `chip_groups` above)
---picks up a `:colorscheme` switch on the next render with no autocmd of
---its own.
---@param key string
---@param hex string
---@return string group
function M.accent_hl(key, hex)
  local group = "FiletreeBreadcrumbRoot_" .. key
  vim.api.nvim_set_hl(0, group, { fg = hex, bold = true })
  return group
end

return M
