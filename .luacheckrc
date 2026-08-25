-- luacheck configuration for filetree.nvim
std = "luajit"
read_globals = { "vim" }

-- The codebase favours readability over an 80/120 column cap; stylua owns line length.
max_line_length = false

ignore = {
  "212", -- unused argument (common in adapter/callback signatures)
  "212/self", -- unused self
  "122", -- setting a read-only field of a global (e.g. vim.*): common in Neovim
}

-- Fixture files under TESTS/ are sample projects for the reference-engine test
-- harness, not part of the plugin itself. (The path used to say
-- `TESTS/smart_rename_refs/` -- the suite moved to `TESTS/refs/` and the
-- exclusion did not follow, so it excluded nothing at all.) Shipped file
-- templates use placeholder syntax (e.g. "$1", "$name") and are not valid
-- standalone Lua.
exclude_files = {
  "TESTS/refs/fixtures/**",
  "lua/filetree/assets/templates/**",
}
