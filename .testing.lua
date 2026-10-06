-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "filetree",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "script",
  -- Lua patterns a file name must match to be a spec (the old runner started these files by name).
  spec_pattern = {
    "_spec%.lua$",
    "^TESTS/smoke%.lua$",
    "^TESTS/units%.lua$",
    "^TESTS/menu%.lua$",
    "^TESTS/cwd_mode%.lua$",
    "^TESTS/sidebar_guard%.lua$",
    "^TESTS/gaps%.lua$",
    "^TESTS/env_roots%.lua$",
    "^TESTS/who_locks%.lua$",
    "^TESTS/cheatsheet%.lua$",
    "^TESTS/keys%.lua$",
    "^TESTS/config_schema%.lua$",
    "^TESTS/nav_switch_toggle%.lua$",
    "^TESTS/create_from_template%.lua$",
    "^TESTS/file_clipboard%.lua$",
    "^TESTS/marks_auto_clear%.lua$",
    "^TESTS/quickpick%.lua$",
    "^TESTS/refs/run%.lua$",
  },
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim", "ui.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "none",
  -- "c" = child started from a -c command (v:vim_did_enter is 0, <cword> works),
  -- "l" = `nvim -l`.
  host = "l",
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  env_allow = {
    "FILETREE_ADAPTER_LINES",
    "FILETREE_LIB_NVIM",
    "FILETREE_TEST_REAL_CLIPBOARD",
    "FILETREE_UI_NVIM",
    "FT_CODE",
    "FT_X",
    "LIB_NVIM_PATH",
    "UI_NVIM_PATH",
  },
}
