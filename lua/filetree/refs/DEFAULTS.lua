---@module 'filetree.refs.DEFAULTS'
--- Defaults for the reference engine.
---
--- Lives in its own file because two places need the exact same table and must
--- never drift apart: `filetree.config.DEFAULTS` (so `setup({ refs = … })` is
--- documented and deep-merged like every other option) and `filetree.refs`
--- itself (so the engine is usable — in a test, or before `setup()` ran — with
--- no configuration at all).

---@type FiletreeRefsConfig
return {
  enabled = true,

  -- Which languages take part. An unlisted provider (a third-party one
  -- registered via `refs.register`) counts as enabled; only an explicit
  -- `false` turns one off.
  providers = {
    markdown = true,
    lua = true,
    python = true,
    -- Opt-in: without a tsconfig `paths` map, alias-heavy projects get little
    -- out of it, and tsserver already handles renames via willRenameFiles.
    ts_js = false,
  },

  -- What happens after a mutation found references:
  --   "ask"  → chooser (Update all / Select… / Show diff / Leave as-is)
  --   "auto" → update everything without asking
  --   "off"  → don't even scan
  on_rename = "ask",
  on_move = "ask",
  on_delete = "ask", -- trash: mark the now-dangling links as REF!
  copy = false, -- a copy leaves the original in place, so it breaks nothing

  -- Backend for the "Select…" multi-select picker.
  picker = "auto", -- "auto" | "telescope" | "fzf-lua" | "quickfix"

  -- When an LSP client already applied a workspace edit for the rename, skip
  -- the textual code providers instead of editing the same lines twice.
  -- Markdown and Lua opt out of the skip (no server rewrites markdown links,
  -- and lua_ls never implements willRenameFiles).
  prefer_lsp = true,

  -- `[[wiki]]`-style links are not standard markdown, so they are only
  -- scanned when asked for.
  wiki_links = false,

  scan = {
    root = "project", -- "project" (nearest root) | "cwd"
    respect_gitignore = true,
    max_files = 5000, -- cap for the ripgrep-free fallback walk
    timeout_ms = 3000,
  },

  -- Keep the previous content of every rewritten line so `:Filetree refs undo`
  -- can put it back.
  undo = true,
}
