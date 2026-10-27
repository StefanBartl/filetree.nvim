---@module 'filetree.util.confirm_choice'
---@brief Multi-choice button confirm (≤4 options) — a wrapper of the shared dialog for
--- the "Update refs / Inspect first / Leave as-is (/ Cancel)"-style choosers
--- that used to render as a vertical `filetree.util.select` list. Buttons read
--- better than a list once the option count is small and fixed.
---@description
---   require("filetree.util.confirm_choice")(
---     "3 ref(s) to old.lua",
---     { "Update all refs", "Inspect first", "Leave as-is" },
---     function(choice) ... end   -- choice is one of the strings above, or nil
---   )                            -- if the dialog was dismissed (Esc/q)

local dialog = require("filetree.util.dialog")

---@param question string
---@param choices string[]
---@param on_choice fun(choice: string|nil)
return function(question, choices, on_choice)
  dialog.confirm({
    question = question,
    choices = choices,
    on_answer = function(choice)
      on_choice(choice) -- the dialog also passes the button's index: the contract here is the label only
    end,
  })
end
