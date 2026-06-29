---@module 'filetree.features.picker.renderer'
---@brief Renders two-digit index labels as extmarks on the tree buffer.

local M = {}

---@type integer
local NS = vim.api.nvim_create_namespace("filetree_picker")

---@param mode string  Current open mode (edit/split/vsplit/tab/preview).
---@return string      Short mode indicator shown in the label.
local function mode_label(mode)
  local labels = { edit = "e", split = "s", vsplit = "v", tab = "t", preview = "p" }
  return labels[mode] or "e"
end

---Render index extmarks for all visible nodes.
---@param bufnr   integer
---@param winid   integer
---@param nodes   FiletreeNode[]
---@param mode    string
function M.update(bufnr, winid, nodes, mode)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)

  local win_width = vim.api.nvim_win_get_width(winid)
  local ml = mode_label(mode)

  for i, node in ipairs(nodes) do
    local label = string.format("%02d", i)
    local hl    = node.type == "directory" and "Directory" or "Normal"
    local col   = 0

    local virt = {
      { string.format("[%s:%s] ", ml, label), "Comment" },
      { node.name, hl },
    }

    -- Only show if line is within buffer
    local line = node.line_number - 1
    if line >= 0 and line < vim.api.nvim_buf_line_count(bufnr) then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, line, col, {
        virt_text          = virt,
        virt_text_pos      = "right_align",
        hl_mode            = "combine",
        priority           = 200,
      })
    end
  end
end

---Clear all picker extmarks from a buffer.
---@param bufnr integer
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  end
end

return M
