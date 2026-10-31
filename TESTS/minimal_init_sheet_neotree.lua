-- TESTS/minimal_init_sheet_neotree.lua -- the child editor of the neo-tree test sheets
-- (TESTS/sheets/*.sheet.lua with `minit = "TESTS/minimal_init_sheet_neotree.lua"`).
--
-- TESTS/minimal_init.lua first (filetree.nvim, testing.nvim, lib.nvim, ui.nvim), then the real
-- neo-tree and what it needs: neo-tree.nvim, nui.nvim, plenary.nvim. Each is looked up in, in
-- this order:
--   1. $<NAME>_DIR                         ($NEO_TREE_NVIM_DIR, $NUI_NVIM_DIR, $PLENARY_NVIM_DIR;
--                                           listed in env_allow of .testing.lua)
--   2. <repo>/.deps/<name>
--   3. <repo>/../<name>                    (what CI checks out, at a pinned commit)
--   4. the lazy.nvim directory of the real editor ($LOCALAPPDATA/nvim-data/lazy on Windows,
--      ~/.local/share/nvim/lazy elsewhere): the child's own stdpath('data') is a sandbox.
-- A missing one is FATAL (exit 1, naming every place searched): a sheet that silently ran without
-- neo-tree would prove nothing. The snapshots were taken with the commits CI pins
-- (.github/workflows/ci.yml): a much newer or older local neo-tree may draw the tree differently.

local base = dofile(
  vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
    .. "/minimal_init.lua"
)
local root = base.root

---@param name string
---@return string
local function env_name(name)
  return (name:upper():gsub("[^%w]", "_")) .. "_DIR"
end

---The lazy.nvim directory of the developer's real editor (the child's stdpath is a sandbox).
---@return string?
local function real_lazy()
  if vim.env.LOCALAPPDATA and vim.env.LOCALAPPDATA ~= "" then
    return vim.fs.normalize(vim.env.LOCALAPPDATA) .. "/nvim-data/lazy"
  end
  local home = vim.env.HOME
  if home and home ~= "" then return vim.fs.normalize(home) .. "/.local/share/nvim/lazy" end
  return nil
end

local DEPS = {
  { name = "plenary.nvim", marker = "lua/plenary" },
  { name = "nui.nvim", marker = "lua/nui" },
  { name = "neo-tree.nvim", marker = "lua/neo-tree" },
}

local failures = {}
for _, dep in ipairs(DEPS) do
  local override = vim.env[env_name(dep.name)]
  local lazy = real_lazy()
  local places = {
    { "$" .. env_name(dep.name), override },
    { ".deps/" .. dep.name, root .. "/.deps/" .. dep.name },
    { "../" .. dep.name, vim.fs.dirname(root) .. "/" .. dep.name },
    { "lazy.nvim of the real editor", lazy and (lazy .. "/" .. dep.name) or nil },
  }
  local hit
  if override ~= nil and override ~= "" then
    if vim.fn.isdirectory(override .. "/" .. dep.marker) == 1 then hit = override end
  else
    for i = 2, #places do
      local dir = places[i][2]
      if dir and vim.fn.isdirectory(dir .. "/" .. dep.marker) == 1 then
        hit = dir
        break
      end
    end
  end
  if hit then
    vim.opt.rtp:append(hit)
  else
    local lines =
      { ("error: dependency '%s' not found. Searched, in this order:"):format(dep.name) }
    for i, p in ipairs(places) do
      lines[#lines + 1] = ("  %d. %s (%s)"):format(i, p[1], p[2] or "unset")
    end
    failures[#failures + 1] = table.concat(lines, "\n")
  end
end

if #failures > 0 then
  io.stderr:write(table.concat(failures, "\n"), "\n")
  os.exit(1)
end

-- The sandbox has the XDG roots but not Neovim's own directories below them; neo-tree opens its
-- log file in stdpath('data') on setup and, when that fails, warns in a message long enough for a
-- hit-enter prompt that blocks the child.
for _, what in ipairs({ "data", "state", "cache" }) do
  vim.fn.mkdir(vim.fn.stdpath(what), "p")
end

return base
