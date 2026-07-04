---@module 'filetree.util.path'
---@brief Pure path operations: normalize, convert, transform, escape.
---@description
--- No global state, no project-root lookup — every function derives its result
--- purely from its arguments (relative paths resolve against an explicit base or
--- the cwd). Features that need project-root-relative paths pass the base in.

local platform = require("filetree.util.platform")

local M = {}

---Expand to absolute path and strip surrounding quotes.
---@param p string
---@return string
function M.to_absolute(p)
  p = vim.fn.fnamemodify(p, ":p")
  return (p:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1"))
end

---Expand to absolute path and normalize separators to the OS default.
---Kept as an alias of to_absolute for backwards compatibility.
---@param p string
---@return string
function M.normalize(p)
  return M.to_absolute(p)
end

---Convert to a Unix-style absolute path (forward slashes).
---@param p string
---@return string
function M.to_unix(p)
  return (M.to_absolute(p):gsub("\\", "/"))
end

---Replace backslashes with forward slashes, without touching absoluteness or
---the path's meaning otherwise (no fnamemodify, no cwd resolution) — a pure
---string transform. This is filetree's single canonical separator: prompts,
---notifications and any other path shown to the user always display with `/`,
---on every OS, and any raw path typed by the user (who may type either `/` or
---`\`) is sanitized to this form immediately after `vim.ui.input` returns, before
---it is used for anything. Forward slashes work fine for Neovim's own path/buffer
---APIs and for libuv on Windows; only literal OS-shell invocations (e.g.
---explorer.exe, cmd /c) need native backslashes, and those call sites convert
---explicitly at the point of use (see open_in_fm/open_with).
---@param p string
---@return string
function M.slashify(p)
  return (p:gsub("\\", "/"))
end

---Convert to a Windows-style absolute path (backslashes).
---@param p string
---@return string
function M.to_win(p)
  return (M.to_absolute(p):gsub("/", "\\"))
end

---Return the parent directory of a path (forward-slash, see M.slashify).
---@param p string
---@return string
function M.parent(p)
  return M.slashify(vim.fn.fnamemodify(p, ":h"))
end

---Return the filename (tail) of a path.
---@param p string
---@return string
function M.basename(p)
  return vim.fn.fnamemodify(p, ":t")
end

---Resolve a path to a directory: a file yields its parent, a directory yields
---itself. Used to turn a node path into a working directory.
---@param p string
---@return string
function M.ensure_dir(p)
  if p == nil or p == "" then
    return platform.get_cwd()
  end
  if vim.fn.isdirectory(p) == 1 then
    return p
  end
  local parent = M.parent(p)
  if parent == "" or parent == "." then
    return platform.get_cwd()
  end
  return parent
end

---Return `p` relative to `base` (default: cwd). Falls back to `:~:.` form when
---`p` is not under `base`. Purely argument-driven — no project-root lookup.
---@param p    string
---@param base string?  Base directory (default: cwd).
---@return string
function M.relative(p, base)
  base = base or platform.get_cwd()
  local abs_p    = M.to_unix(p):gsub("/$", "")
  local abs_base = M.to_unix(base):gsub("/$", "")
  if abs_p:sub(1, #abs_base) == abs_base then
    local rel = abs_p:sub(#abs_base + 2)
    return rel == "" and "." or rel
  end
  -- fnamemodify's ":~:." returns OS-native separators (backslash on Windows);
  -- slashify keeps this consistent with the rest of the plugin's forward-slash
  -- display convention.
  return M.slashify(vim.fn.fnamemodify(abs_p, ":~:."))
end

---Escape a path for use as a vim command argument.
---@param p string
---@return string
function M.fnameescape(p)
  return vim.fn.fnameescape(p)
end

---Escape a path as a single shell argument (cross-platform quoting).
---@param p string
---@return string
function M.escape_shell_arg(p)
  if platform.is_windows() then
    return '"' .. p:gsub('"', '""') .. '"'
  end
  return "'" .. p:gsub("'", "'\\''") .. "'"
end

---Wrap a path in double quotes only when it contains whitespace.
---@param p string
---@return string
function M.quote_if_needed(p)
  if p:find("%s") then
    return '"' .. p .. '"'
  end
  return p
end

return M
