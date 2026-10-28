---@module 'filetree.util.confirm'
---@brief Small yes/no confirmation dialog with an optional info body.
---@description
--- Routes through `filetree.util.dialog` (lib.nvim's shared dialog: ui.kit's horizontal Yes/No buttons,
--- `vim.ui.select` when no float can open) instead of hand-rolling a floating window. The optional `body`
--- (e.g. file metadata) is folded into the question as leading lines, since the dialog centers and wraps
--- multi-line questions above the buttons.
---
---   require("filetree.util.confirm")({
---     title    = " Trash ",
---     body     = { "  Path: /x/y.lua", "  Size: 2 KB" },
---     question = "Send to trash?",
---     on_choice = function(yes) ... end,
---   })
---
--- Keys inside the dialog: h/l (or arrows/<Tab>) move focus, <CR> confirms
--- the focused button, <Esc>/q cancels (= No).

local dialog = require("filetree.util.dialog")

local MAX_BODY_LINES = 6

---@class FiletreeConfirmOpts
---@field title?     string      Window title.
---@field body?      string[]    Info lines shown above the question.
---@field question?  string      The yes/no question (default "Confirm?").
---@field on_choice  fun(yes: boolean)

---@param opts FiletreeConfirmOpts
return function(opts)
  opts = opts or {}
  local on_choice = opts.on_choice or function() end
  local body = opts.body or {}
  local question = opts.question or "Confirm?"

  -- The question is the last line and the dialog cuts the end of a text that does not fit: a body of dozens of
  -- lines (a name with newlines in it, a long listing) must not push it out.
  local lines = {}
  for i, l in ipairs(body) do
    if i > MAX_BODY_LINES then
      lines[#lines + 1] = "  …"
      break
    end
    lines[#lines + 1] = l
  end
  lines[#lines + 1] = question

  dialog.confirm({
    title = opts.title,
    question = table.concat(lines, "\n"),
    on_answer = on_choice,
  })
end
