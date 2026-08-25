---@module 'filetree.features.nav.cwd_mode.DEFAULTS'
--- Defaults for the cwd-mode root policy.
---
--- Lives in its own file because two places need the exact same table and must
--- never drift apart: `filetree.config.DEFAULTS` (so `setup({ features = {
--- cwd_mode = ... } })` is documented and deep-merged like every other option)
--- and the feature itself (so it is usable -- in a test, or before `setup()`
--- ran -- with no configuration at all). Same arrangement as
--- `filetree.refs.DEFAULTS`, for the same reason.
---
--- Before this split, `config/DEFAULTS.lua` carried a hand-copied subset of the
--- table below and had already fallen behind it: the whole `nearest` block --
--- fifteen package markers, the entire configuration surface of one of the six
--- modes -- existed only here, so a user reading the central defaults could not
--- see that it was configurable at all.
---@type FiletreeCwdModeConfig
return {
  enabled = true,
  mode = "follow",
  scope = "global",

  project = {
    -- VCS markers only by default: `project` mode is about "which repository
    -- am I in". Adding package.json / Cargo.toml here turns it into
    -- nearest-package (monorepo) behaviour, which is a deliberate choice, not
    -- the default one.
    markers = { ".git", ".hg", ".svn" },
    skip_dirs = { "node_modules", ".venv", "vendor" },
    max_depth = nil,
    sticky = true,
  },

  -- `nearest` differs from `project` only in where it stops walking: the
  -- package that owns the file, not the repository that contains it. Everything
  -- else (skip_dirs, sticky) is shared, so there is one place to configure it.
  nearest = {
    markers = {
      "package.json",
      "Cargo.toml",
      "go.mod",
      "pyproject.toml",
      "setup.py",
      "*.rockspec",
      "mix.exs",
      "build.zig",
      "CMakeLists.txt",
      -- Last resort: without a VCS marker a file outside any package would
      -- walk to the filesystem root before giving up.
      ".git",
    },
  },

  lock = {
    enforce = true,
    follow_manual_root = true,
  },

  reveal_outside = "skip",

  -- Off by default: it writes to stdpath("cache") and makes a mode outlive the
  -- session that set it, which should be asked for rather than assumed.
  persist = false,

  indicator = {
    enabled = true,
    mode = "auto",
    align = "left",
    show_path = "lock",
    -- Which label set below the badge is built from. "numeric" is the only
    -- style that shows something for `follow` — the point of the digit row
    -- is "which of the N states am I in", and 0 answers that; the other
    -- styles keep treating follow as the inert, nothing-to-report default.
    style = "text", -- "text" | "short" | "numeric" | "icon"
    labels = {
      follow = "",
      project = "PROJECT",
      nearest = "PKG",
      lock = "LOCK",
      manual = "MANUAL",
      tree_leads = "TREE",
    },
    labels_short = {
      follow = "",
      project = "P",
      nearest = "N",
      lock = "L",
      manual = "M",
      tree_leads = "T",
    },
    labels_numeric = {
      follow = "0",
      project = "1",
      nearest = "2",
      lock = "3",
      manual = "4",
      tree_leads = "5",
    },
    -- Nerd Font glyphs. Swap any of these in your own config if one renders
    -- as tofu with your font — badge_text() falls back to "" either way if a
    -- key is missing, so a partial override is always safe.
    icons = {
      follow = "",
      project = "",
      nearest = "",
      lock = "",
      manual = "",
      tree_leads = "",
    },
    hl = {
      follow = "Comment",
      project = "DiagnosticInfo",
      nearest = "DiagnosticInfo",
      lock = "DiagnosticWarn",
      manual = "Comment",
      tree_leads = "DiagnosticHint",
    },
  },

  cycle = { "follow", "project", "lock" },

  keymap_cycle = "L",
  keymap_lock_here = "gp",
}
