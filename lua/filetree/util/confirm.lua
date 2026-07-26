---@module 'filetree.util.confirm'
---@brief Small yes/no confirmation dialog with an optional info body.
---@description
--- Routes through `lib.nvim.ui.kit`'s `kit.confirm` (horizontal Yes/No
--- buttons) instead of hand-rolling a floating window. The optional `body`
--- (e.g. file metadata) is folded into the question as leading lines, since
--- kit.confirm centers and renders multi-line questions above the buttons.
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

local kit = require("lib.nvim.ui.kit")

---@class FiletreeConfirmOpts
---@field title?     string      Window title.
---@field body?      string[]    Info lines shown above the question.
---@field question?  string      The yes/no question (default "Confirm?").
---@field on_choice  fun(yes: boolean)

---@param opts FiletreeConfirmOpts
return function(opts)
  opts = opts or {}
  local on_choice = opts.on_choice or function() end
  local body      = opts.body or {}
  local question  = opts.question or "Confirm?"

  local lines = {}
  for _, l in ipairs(body) do lines[#lines + 1] = l end
  lines[#lines + 1] = question

  kit.confirm({
    title = opts.title,
    question = table.concat(lines, "\n"),
    on_answer = on_choice,
  })
end
