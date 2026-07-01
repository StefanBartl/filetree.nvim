---@module 'filetree.features.quick_open'
---@brief Frecency-based fast file opener combining all filetree collections.
---@description
--- Aggregates recent_files + bookmarks + pins into a single scored list,
--- sorted by a frecency score (frequency × recency decay). Fuzzy-filter
--- as you type inside the floating picker.
---
--- Frecency algorithm:
---   Each open increments a visit count and records the timestamp.
---   Score = visit_count / (1 + hours_since_last_visit * decay_rate)
---   Default decay_rate: 0.5 (score halves every 2 hours of no access).
---
--- Storage: stdpath("data")/filetree/quick_open.json
---   { path: { count: N, last: unix_ts } }
---
--- Config:
---   enabled       boolean
---   keymap        string?   Open picker (default "<C-p>" — inside tree only).
---   max_items     integer   Max entries shown (default 50).
---   decay_rate    number    Frecency decay per hour (default 0.5).
---   sources       string[]  Which collections to include
---                           (default {"recent","bookmarks","pins"}).
---   split         "edit"|"vsplit"|"split"  How to open (default "edit").
---
--- Commands (via :Filetree dispatcher):
---   :Filetree quickopen

local notify = require("filetree.util.notify").create("[filetree.quick_open]")

local M = {}

---@type FiletreeQuickOpenConfig
local _cfg = {
  enabled    = false,
  keymap     = "<C-p>",
  max_items  = 50,
  decay_rate = 0.5,
  sources    = { "recent", "bookmarks", "pins" },
  split      = "edit",
}

-- ── Frecency store ────────────────────────────────────────────────────────────

local _store = {}  ---@type table<string, {count: integer, last: integer}>

local function store_path()
  return vim.fn.stdpath("data") .. "/filetree/quick_open.json"
end

local function load_store()
  local p = store_path()
  if vim.fn.filereadable(p) == 0 then return {} end
  local ok, lines = pcall(vim.fn.readfile, p)
  if not ok or #lines == 0 then return {} end
  local decoded = vim.fn.json_decode(table.concat(lines, ""))
  return type(decoded) == "table" and decoded or {}
end

local function save_store()
  local dir = vim.fn.stdpath("data") .. "/filetree"
  if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end
  vim.fn.writefile({ vim.fn.json_encode(_store) }, store_path())
end

local function frecency_score(entry)
  if not entry then return 0 end
  local hours = (os.time() - (entry.last or 0)) / 3600
  return entry.count / (1 + hours * _cfg.decay_rate)
end

local function record_open(path)
  local e = _store[path] or { count = 0, last = 0 }
  _store[path] = { count = e.count + 1, last = os.time() }
  save_store()
end

-- ── Source aggregation ────────────────────────────────────────────────────────

local function feat(name)
  return require("filetree.features").require(name)
end

local function collect_paths()
  local seen  = {}
  local paths = {}

  local function add(path)
    if path and path ~= "" and not seen[path] then
      seen[path]      = true
      paths[#paths + 1] = path
    end
  end

  local src = _cfg.sources
  for _, s in ipairs(src) do
    if s == "recent" then
      local f = feat("recent_files")
      if f then for _, p in ipairs(f.get_all and f.get_all() or {}) do add(p) end end
    elseif s == "bookmarks" then
      local f = feat("bookmarks")
      if f then
        for _, b in ipairs(f.get_all and f.get_all() or {}) do
          add(type(b) == "string" and b or b.path)
        end
      end
    elseif s == "pins" then
      local f = feat("pin_node")
      if f then for _, p in ipairs(f.get_all and f.get_all() or {}) do add(p) end end
    end
  end

  return paths
end

-- ── Fuzzy filter ─────────────────────────────────────────────────────────────

local function fuzzy_match(path, query)
  if query == "" then return true end
  local name = vim.fn.fnamemodify(path, ":t"):lower()
  return name:find(query:lower(), 1, true) ~= nil
end

-- ── Floating picker ───────────────────────────────────────────────────────────

local function open_picker()
  local all_paths = collect_paths()

  -- Sort by frecency score
  table.sort(all_paths, function(a, b)
    return frecency_score(_store[a]) > frecency_score(_store[b])
  end)

  if #all_paths > _cfg.max_items then
    all_paths = vim.list_slice(all_paths, 1, _cfg.max_items)
  end

  local query       = ""
  local filtered    = {}

  local buf = vim.api.nvim_create_buf(false, true)
  local width  = math.min(72, vim.o.columns - 6)
  local height = math.min(20, vim.o.lines - 6)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    width = width, height = height,
    row   = math.floor((vim.o.lines - height) / 2) - 3,
    col   = math.floor((vim.o.columns - width) / 2),
    title = " Quick Open ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = true

  local input_buf = vim.api.nvim_create_buf(false, true)
  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    width = width, height = 1,
    row   = math.floor((vim.o.lines - height) / 2) - 3 + height + 1,
    col   = math.floor((vim.o.columns - width) / 2),
    title = " filter ",
    title_pos = "left",
  })

  local function render_list()
    filtered = {}
    for _, p in ipairs(all_paths) do
      if fuzzy_match(p, query) then
        filtered[#filtered + 1] = p
      end
    end
    local lines = vim.tbl_map(function(p)
      local score = frecency_score(_store[p])
      return string.format("[%.1f] %s", score, vim.fn.fnamemodify(p, ":~:."))
    end, filtered)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  local function open_selected(split_cmd)
    local row  = vim.api.nvim_win_get_cursor(win)[1]
    local path = filtered[row]
    if not path then return end
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_win_close, input_win, true)
    record_open(path)
    vim.cmd(split_cmd .. " " .. vim.fn.fnameescape(path))
  end

  local function close_all()
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_win_close, input_win, true)
  end

  render_list()

  -- Input autocmd
  local grp = vim.api.nvim_create_augroup("filetree_quick_open_input", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = grp, buffer = input_buf,
    callback = function()
      query = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""
      render_list()
    end,
  })

  local list_km = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>",  function() open_selected(_cfg.split) end,  list_km)
  vim.keymap.set("n", "<C-v>", function() open_selected("vsplit") end, list_km)
  vim.keymap.set("n", "<C-x>", function() open_selected("split")  end, list_km)
  vim.keymap.set("n", "<Esc>", close_all, list_km)
  vim.keymap.set("n", "q",     close_all, list_km)
  vim.keymap.set("n", "<Tab>", function()
    if vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_set_current_win(input_win)
    end
  end, list_km)

  local inp_km = { buffer = input_buf, nowait = true, silent = true }
  vim.keymap.set({ "i", "n" }, "<Esc>",   close_all, inp_km)
  vim.keymap.set({ "i", "n" }, "<CR>", function()
    vim.api.nvim_set_current_win(win)
    open_selected(_cfg.split)
  end, inp_km)
  vim.keymap.set({ "i", "n" }, "<C-v>", function()
    vim.api.nvim_set_current_win(win)
    open_selected("vsplit")
  end, inp_km)
  vim.keymap.set({ "i", "n" }, "<C-k>", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    if row > 1 then vim.api.nvim_win_set_cursor(win, { row - 1, 0 }) end
  end, inp_km)
  vim.keymap.set({ "i", "n" }, "<C-j>", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local max = #filtered
    if row < max then vim.api.nvim_win_set_cursor(win, { row + 1, 0 }) end
  end, inp_km)

  vim.cmd("startinsert!")
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.open() open_picker() end

function M.record(path) record_open(path) end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@type integer?
local _augroup = nil

---@param config FiletreeQuickOpenConfig
---@param _adapter FiletreeAdapter
function M.setup(config, _adapter)
  if not config.enabled then return end
  _cfg   = vim.tbl_deep_extend("force", _cfg, config)
  _store = load_store()

  if _augroup then pcall(vim.api.nvim_del_augroup_by_id, _augroup) end
  _augroup = vim.api.nvim_create_augroup("filetree_quick_open", { clear = true })

  if _cfg.keymap then
    vim.api.nvim_create_autocmd("FileType", {
      group   = _augroup,
      pattern = { "neo-tree", "NvimTree" },
      callback = function(ev)
        local buf = ev.buf
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.keymap.set("n", _cfg.keymap, M.open, {
            buffer = buf, silent = true,
            desc   = "Filetree: quick open (frecency)",
          })
        end)
      end,
    })
  end
end

function M.teardown()
  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
end

return M
