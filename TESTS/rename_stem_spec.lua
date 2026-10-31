-- Test code: when something here comes back nil this file must crash and name it.
---@diagnostic disable: need-check-nil, missing-fields
-- TESTS/rename_stem_spec.lua -- where the rename prompt parks the cursor:
-- right before the extension of a file, at the end otherwise.
--
--   nvim --clean --headless -u NONE -l TESTS/rename_stem_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root)
for _, dep in ipairs({ "lib.nvim", "ui.nvim" }) do
  for _, candidate in ipairs({
    vim.env[dep:upper():gsub("%.", "_") .. "_DIR"] or "",
    vim.fn.fnamemodify(root, ":h") .. "/" .. dep,
    root .. "/.deps/" .. dep,
    vim.fn.stdpath("data") .. "/lazy/" .. dep,
  }) do
    if candidate ~= "" and vim.fn.isdirectory(candidate .. "/lua") == 1 then
      vim.opt.rtp:prepend(candidate)
      break
    end
  end
end

local passed, failed = 0, 0
local function eq(name, got, want)
  if got == want then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print(("  FAIL %s  -- got %s want %s"):format(name, tostring(got), tostring(want)))
  end
end

local stem_end = require("filetree.features.fileops.smart_rename").stem_end
eq("plain extension", stem_end("init.lua"), 4)
eq("last dot wins", stem_end("a.test.lua"), 6)
eq("no extension", stem_end("Makefile"), nil)
eq("dotfile", stem_end(".gitignore"), nil)
eq("trailing dot", stem_end("name."), nil)
eq("directory", stem_end("v1.2", true), nil)

print(("\nfiletree.nvim rename_stem_spec: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
