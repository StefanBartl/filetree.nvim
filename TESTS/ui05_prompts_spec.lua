---@diagnostic disable: need-check-nil, missing-fields, duplicate-set-field
-- ui05_prompts_spec.lua -- two places that used to tell the person what to type now ask:
--   1. saving a buffer that has no file name asks for the name and then writes it (a dismissed prompt writes nothing,
--      an existing file is never replaced);
--   2. a delete whose reference rewrite finished after the file was restored asks whether those references go back
--      too (No first; No leaves them).
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l TESTS/ui05_prompts_spec.lua
--
-- Exit 0 = all passed, 1 = a check failed.

local this = debug.getinfo(1, "S").source:sub(2)
local root_dir = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root_dir)

local candidates = {}
for _, env in ipairs({ "FILETREE_LIB_NVIM", "LIB_NVIM_PATH", "LIB_NVIM_DIR" }) do
  local v = vim.env[env]
  if v and v ~= "" then candidates[#candidates + 1] = v end
end
candidates[#candidates + 1] = vim.fn.fnamemodify(root_dir, ":h") .. "/lib.nvim"
candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"
for _, candidate in ipairs(candidates) do
  if vim.fn.isdirectory(candidate .. "/lua/lib") == 1 then
    vim.opt.rtp:prepend(candidate)
    break
  end
end
local ui_candidates = {}
for _, env in ipairs({ "FILETREE_UI_NVIM", "UI_NVIM_DIR" }) do
  local v = vim.env[env]
  if v and v ~= "" then ui_candidates[#ui_candidates + 1] = v end
end
ui_candidates[#ui_candidates + 1] = vim.fn.fnamemodify(root_dir, ":h") .. "/ui.nvim"
ui_candidates[#ui_candidates + 1] = vim.fn.stdpath("data") .. "/lazy/ui.nvim"
for _, candidate in ipairs(ui_candidates) do
  if vim.fn.isdirectory(candidate .. "/lua/ui") == 1 then
    vim.opt.rtp:prepend(candidate)
    break
  end
end

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. (detail and ("  — " .. detail) or ""))
  end
end

local notes = {}
vim.notify = function(msg, level)
  notes[#notes + 1] = { msg = tostring(msg), level = level }
end
local function told(needle)
  for _, n in ipairs(notes) do
    if n.msg:find(needle, 1, true) then return true end
  end
  return false
end

-- ── 1. saving a buffer without a name ───────────────────────────────────────────
do
  local save = require("filetree.features.fileops.buffer_save")
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")

  -- an editor window holds the nameless buffer; the "tree" is another window
  local editor_buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(editor_buf, 0, -1, false, { "hello" })
  vim.api.nvim_set_current_buf(editor_buf)
  vim.cmd("topleft vsplit")
  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, tree_buf)

  local asked
  local answer
  save.ask_name = function(default, cb)
    asked = default
    cb(answer)
  end

  asked, answer = nil, dir .. "/new.txt"
  notes = {}
  save.save_adjacent()
  check("a nameless buffer asks for the name", asked ~= nil)
  check("and writes it under that name", vim.fn.filereadable(dir .. "/new.txt") == 1)
  check("the old hint is gone", not told("use :w to name it first"))

  -- dismissed: nothing is written
  local other = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(other, 0, -1, false, { "second" })
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= vim.api.nvim_get_current_win() then vim.api.nvim_win_set_buf(win, other) end
  end
  asked, answer = nil, nil
  notes = {}
  save.save_adjacent()
  check("a dismissed prompt asks once", asked ~= nil)
  check("and writes nothing", #vim.fn.glob(dir .. "/*", false, true) == 1)
  check("and says so", told("Not saved"))

  -- an existing file is never replaced
  local third = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(third, 0, -1, false, { "third" })
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= vim.api.nvim_get_current_win() then vim.api.nvim_win_set_buf(win, third) end
  end
  answer = dir .. "/new.txt"
  notes = {}
  save.save_adjacent()
  check("an existing file is not replaced", vim.fn.readfile(dir .. "/new.txt")[1] == "hello")
  check("and the failure is told", told("Save failed"))
  save.ask_name = nil
end

-- ── 2. the references of a restored delete ──────────────────────────────────────
do
  local undo = require("filetree.features.fileops.trash.undo")
  local reverted = {}
  local real_revert = undo.revert_refs
  undo.revert_refs = function(id, count)
    reverted[#reverted + 1] = { id = id, count = count }
  end
  local asked, answer
  undo.confirm = function(question, yes_label, cb)
    asked = { question = question, yes = yes_label }
    cb(answer)
  end

  local function finished_after_restore(path, id)
    -- the delete marked its rewrite as pending; the file was restored; now the rewrite settles
    undo.mark_refs_pending(path)
    undo.attach_refs(path, id, 4)
  end

  if type(undo.mark_refs_pending) ~= "function" then
    check("undo exposes mark_refs_pending for the rewrite that is still running", false)
  else
    asked, answer, reverted = nil, true, {}
    finished_after_restore("/x/a.md", 11)
    check(
      "it asks whether the references go back too",
      asked ~= nil and asked.question:find("4 reference", 1, true) ~= nil
    )
    check("Yes reverts them", #reverted == 1 and reverted[1].id == 11)

    asked, answer, reverted = nil, false, {}
    finished_after_restore("/x/b.md", 12)
    check("No leaves them", asked ~= nil and #reverted == 0)

    asked, answer, reverted = nil, true, {}
    undo.attach_refs("/x/c.md", nil, nil)
    check("nothing rewritten: nothing is asked", asked == nil and #reverted == 0)
  end
  undo.confirm = nil
  undo.revert_refs = real_revert
end

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
