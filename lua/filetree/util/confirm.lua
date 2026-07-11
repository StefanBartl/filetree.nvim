---@module 'filetree.util.confirm'
---@brief Small yes/no confirmation float with an optional info body.
---@description
--- A nicer replacement for `vim.fn.confirm`'s native "press y/n" prompt (which
--- pushes a full-width message line and hijacks the command area). Renders a
--- rounded floating window showing an optional body (e.g. file metadata) and a
--- `[y]es / [n]o` line, then reports the choice through a callback.
---
---   require("filetree.util.confirm")({
---     title    = " Trash ",
---     body     = { "  Path: /x/y.lua", "  Size: 2 KB" },
---     question = "Send to trash?",
---     on_choice = function(yes) ... end,
---   })
---
--- Keys inside the popup: y / <CR> confirm, n / <Esc> / q cancel.

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

  -- Assemble the buffer content: body, a blank spacer (only if there is a body),
  -- then the prompt line.
  local lines = {}
  for _, l in ipairs(body) do lines[#lines + 1] = l end
  if #body > 0 then lines[#lines + 1] = "" end
  local prompt = "  " .. question .. "   [y]es / [n]o"
  lines[#lines + 1] = prompt

  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(math.max(width + 2, 24), vim.o.columns - 4)
  local height = #lines

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "cursor",
    row       = 1,
    col       = 0,
    width     = width,
    height    = height,
    style     = "minimal",
    border    = "rounded",
    title     = opts.title,
    title_pos = opts.title and "center" or nil,
  })
  vim.api.nvim_set_option_value("cursorline", false, { win = win })
  -- Highlight the prompt line so the y/n choice stands out.
  local ns = vim.api.nvim_create_namespace("filetree_confirm")
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, #lines - 1, 0,
    { line_hl_group = "Question", end_row = #lines })

  local answered = false
  local function finish(yes)
    if answered then return end
    answered = true
    if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
    on_choice(yes)
  end

  local kopts = { buffer = buf, nowait = true, silent = true }
  for _, k in ipairs({ "y", "Y", "<CR>" }) do
    vim.keymap.set("n", k, function() finish(true) end, kopts)
  end
  for _, k in ipairs({ "n", "N", "q", "<Esc>" }) do
    vim.keymap.set("n", k, function() finish(false) end, kopts)
  end
  -- Closing the window any other way (e.g. focus lost) counts as "no".
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once    = true,
    callback = function() finish(false) end,
  })
end
