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
  -- readdir, not glob: a Windows temp path in its 8.3 form (`STEFAN~1`) makes
  -- glob match nothing at all, and the count reads 0 instead of 1.
  check("and writes nothing", #vim.fn.readdir(dir) == 1, vim.inspect(vim.fn.readdir(dir)))
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

  -- a question from a background callback goes through dialog.ask, "No" first, and only "Yes, ..." accepts
  local dialog = require("lib.nvim.ui.dialog")
  local real_ask = dialog.ask
  local seen, answered = nil, {}
  dialog.ask = function(o)
    seen = o
  end
  undo.ask("later?", "do it", function(accepted)
    answered[#answered + 1] = accepted
  end)
  check(
    "asked behind an open dialog, harmless default",
    seen ~= nil
      and seen.question == "later?"
      and seen.choices == "&No\n&Yes, do it"
      and seen.default == 1
      and seen.max_wait_ms == undo.MAX_WAIT_MS
  )
  seen.on_answer("Yes, do it", 2)
  check("Yes accepts", answered[1] == true)
  undo.ask("later?", "do it", function(accepted)
    answered[#answered + 1] = accepted
  end)
  seen.on_answer(nil)
  check("a dismissed or timed-out question declines", answered[2] == false)
  undo.ask("a & b?", "save & go", function() end)
  check("an ampersand in the label is escaped", seen.choices == "&No\n&Yes, save && go")

  -- a lib.nvim without ui.dialog: the helper stands in with ui.kit
  local real_require, kit = require, require("ui.kit")
  local real_kit_ask, kit_seen = kit.ask, nil
  kit.ask = function(o)
    kit_seen = o
  end
  package.loaded["lib.nvim.ui.dialog"] = nil
  _G.require = function(name)
    if name == "lib.nvim.ui.dialog" then error("module '" .. name .. "' not found") end
    return real_require(name)
  end
  local fallback_ok, fallback_err = pcall(undo.ask, "again?", "do it", function() end)
  _G.require = real_require
  package.loaded["lib.nvim.ui.dialog"] = dialog
  kit.ask = real_kit_ask
  check(
    "without ui.dialog the question goes to ui.kit",
    fallback_ok and kit_seen ~= nil,
    fallback_err
  )
  dialog.ask = real_ask
end

-- the two button wrappers ask through the shared dialog and pass the answers on unchanged
do
  local dialog = require("lib.nvim.ui.dialog")
  local real = dialog.confirm
  local seen
  dialog.confirm = function(o)
    seen = o
  end
  local got = {}
  require("filetree.util.confirm")({
    title = " Trash ",
    body = { "Path: /x" },
    question = "Send to trash?",
    on_choice = function(yes)
      got[#got + 1] = yes
    end,
  })
  check("confirm: body and question are one text", seen.question == "Path: /x\nSend to trash?")
  -- a long body does not push the question out: it is the last line, and the dialog cuts the end
  local long_body = {}
  for i = 1, 40 do
    long_body[i] = "line " .. i
  end
  local first = seen
  require("filetree.util.confirm")({
    body = long_body,
    question = "Delete it?",
    on_choice = function() end,
  })
  check(
    "confirm: a long body is capped and the question stays",
    #vim.split(seen.question, "\n") <= 8 and seen.question:sub(-10) == "Delete it?"
  )
  seen = first
  seen.on_answer(true)
  seen.on_answer(false)
  check("confirm: yes and no are passed on", got[1] == true and got[2] == false)
  require("filetree.util.confirm_choice")("Refs?", { "Update", "Leave" }, function(choice)
    got[#got + 1] = choice == nil and "nil" or choice
  end)
  check("confirm_choice: choices are passed on", seen.choices[2] == "Leave")
  seen.on_answer("Update")
  seen.on_answer(nil)
  check("confirm_choice: label and a dismissal", got[3] == "Update" and got[4] == "nil")
  dialog.confirm = real
end

-- the revert question, end to end through the real dialog and kit: the label round trip, the safe default,
-- a dialog that raises
do
  local undo = require("filetree.features.fileops.trash.undo")
  local kit_confirm = require("ui.kit.confirm")
  local accepted
  undo.ask("Revert them too?", "revert them", function(yes)
    accepted = yes
  end)
  vim.wait(500, function()
    return kit_confirm.is_open()
  end, 5)
  check("the revert question is shown by the real kit", kit_confirm.is_open())
  check("and No is focused", kit_confirm.current_focus() == 1)
  kit_confirm.pick(2)
  check("picking Yes accepts (the label round trip through the real parser)", accepted == true)
  accepted = nil
  undo.ask("Revert them too?", "revert them", function(yes)
    accepted = yes
  end)
  vim.wait(500, function()
    return kit_confirm.is_open()
  end, 5)
  kit_confirm.cancel()
  vim.wait(500, function()
    return accepted ~= nil
  end, 5)
  check("dismissing it declines", accepted == false)

  local dialog = require("lib.nvim.ui.dialog")
  local real_ask, real_select, real_notify = dialog.ask, vim.ui.select, vim.notify
  dialog.ask = function()
    error("kit broke")
  end
  local asked_natively
  vim.ui.select = function(items, _, on_choice)
    asked_natively = items
    on_choice(items[2], 2)
  end
  vim.notify = function() end
  accepted = nil
  local ran = pcall(undo.ask, "Revert them too?", "revert them", function(yes)
    accepted = yes
  end)
  dialog.ask, vim.ui.select, vim.notify = real_ask, real_select, real_notify
  check("a dialog that raises does not escape (the end of a delete still runs)", ran)
  check(
    "it is asked natively, No first, and answers",
    asked_natively ~= nil and asked_natively[1] == "No" and accepted == true
  )
end

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
