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

  -- Cascade-delete-assets (docs/ROADMAP/IDEAS/Cascade_Delete_Assets.md): when
  -- a file is deleted, detect links it holds to asset files (screenshots,
  -- etc.) under a configured root and offer to delete those too, once
  -- nothing else still references them. The mirror of the on_delete/for_delete
  -- pipeline above (which handles the OPPOSITE direction: who points AT the
  -- file being deleted), so it gets its own on/off and ask/auto switch rather
  -- than sharing `on_delete` — a user may want one direction without the
  -- other. Opt-in (`enabled = false`) until this has real mileage; wired into
  -- `d`/trash's confirm dialog regardless of this flag, but a no-op while off.
  outgoing_assets = {
    enabled = false,
    on_delete = "ask", -- "ask" | "auto" | "off" — "off" here also short-circuits `enabled`

    -- Tried first relative to the linking file's own directory (the
    -- per-doc-folder convention `images.nvim`'s `paste.dir` already uses),
    -- then relative to the project root. A link outside every root is
    -- disqualified regardless of extension.
    roots = { "assets" },

    -- Allowlist, never a denylist: an unrecognized extension (a linked
    -- source/text file) must never be offered by accident. Deliberately
    -- excludes `pdf` from the default — a linked PDF is often a real
    -- document, not a disposable screenshot; add it explicitly if wanted.
    extensions = { "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "ico", "mp4", "mov" },

    -- No separate `providers` toggle here: the top-level `providers` table
    -- above already governs whether markdown takes part at all (it gates
    -- both the incoming-refs and the outgoing-links path through the same
    -- registry), and it is the only provider that implements outgoing links
    -- today (see `filetree.refs.outgoing`). A second, independent switch
    -- would have nothing to switch yet.
  },

  -- In-development reference features. Each one is opt-in and its config
  -- shape may still change between releases — kept under `experimental` so
  -- that is unambiguous. Only scalars live here on purpose: the list-shaped
  -- options (`extensions`, `comment_extensions`) default to the provider's
  -- own built-in lists when left unset, because `vim.tbl_deep_extend` merges
  -- lists by index and would otherwise leave stray default entries behind a
  -- shorter user list.
  experimental = {
    -- Rewrite bare filesystem paths written as running text — `see
    -- ../Test/Tester.md for the format` in prose, or the same in a code
    -- comment — not just paths inside link/require/import syntax. A bare
    -- token has a wider false-positive surface, so a match is only rewritten
    -- when it *resolves to exactly the moved file*. See
    -- docs/FEATURES/FILEOPS.md#references.
    plaintext = {
      enabled = false,
      -- Also scan comment lines in source files (.lua/.py/.js/…), not only
      -- prose/text files. Set false to restrict to prose/text.
      comments = true,
      -- extensions          = { "md", "txt", … }  -- override prose list
      -- comment_extensions  = { "lua", "py", … }  -- override comment list
    },
  },

  scan = {
    root = "project", -- "project" (nearest root) | "cwd"
    respect_gitignore = true,
    max_files = 5000, -- cap for the ripgrep-free fallback walk
    timeout_ms = 3000,
  },

  -- Keep the previous content of every rewritten line so `:Filetree refs undo`
  -- can put it back.
  undo = true,
  -- How many rewrites stay undoable. The stack holds only the previous line
  -- content, so raising this is cheap.
  undo_depth = 10,
}
