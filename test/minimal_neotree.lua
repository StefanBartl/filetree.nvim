-- minimal_neotree.lua
-- Minimal test config: neo-tree.nvim + filetree.nvim, no user config loaded.
--
-- Usage:
--   nvim --clean -u test/minimal_neotree.lua [path]
--
-- lazy.nvim is bootstrapped into a temporary data dir so your real config
-- is never touched.  All state (plugins, cache) lands in:
--   %TEMP%/filetree-test/  (Windows)   or   /tmp/filetree-test/  (Unix)

-- ── Temp data dir ─────────────────────────────────────────────────────────────

local tmp = (vim.fn.has("win32") == 1 and vim.env.TEMP or "/tmp") .. "/filetree-test"
vim.fn.mkdir(tmp, "p")

vim.env.XDG_DATA_HOME   = tmp .. "/data"
vim.env.XDG_CONFIG_HOME = tmp .. "/config"
vim.env.XDG_CACHE_HOME  = tmp .. "/cache"
vim.env.XDG_STATE_HOME  = tmp .. "/state"
vim.env.XDG_RUNTIME_DIR = tmp .. "/run"

-- Override stdpath so lazy and filetree store state in our temp dir
local std = vim.fn.stdpath
vim.fn.stdpath = function(what)
  local map = {
    data   = tmp .. "/data/nvim",
    config = tmp .. "/config/nvim",
    cache  = tmp .. "/cache/nvim",
    state  = tmp .. "/state/nvim",
    run    = tmp .. "/run",
  }
  return map[what] or std(what)
end

-- ── Bootstrap lazy.nvim ───────────────────────────────────────────────────────

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ── Basic editor options ──────────────────────────────────────────────────────

vim.opt.termguicolors = true
vim.opt.number        = true
vim.opt.signcolumn    = "yes"
vim.opt.updatetime    = 400
vim.g.mapleader       = " "

-- ── filetree.nvim local path ──────────────────────────────────────────────────

-- Resolve the repo root relative to this file so it works from any cwd.
local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

-- ── Plugin specs ──────────────────────────────────────────────────────────────

require("lazy").setup({

  -- ── Dependencies of neo-tree ────────────────────────────────────────────────
  { "nvim-lua/plenary.nvim",        lazy = false },
  { "nvim-tree/nvim-web-devicons",  lazy = false },
  { "MunifTanjim/nui.nvim",         lazy = false },

  -- ── neo-tree ────────────────────────────────────────────────────────────────
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    lazy   = false,
    opts   = {
      close_if_last_window = false,
      filesystem = {
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = false,  -- keep test env quiet
      },
      window = {
        position = "left",
        width    = 35,
        mappings = {
          -- Keep defaults intact; filetree adds its own keymaps via autocmds.
        },
      },
    },
  },

  -- ── filetree.nvim (local dev) ───────────────────────────────────────────────
  {
    dir    = repo_root,
    name   = "filetree.nvim",
    lazy   = false,
    config = function()
      require("filetree").setup({
        adapter = "neotree",

        -- Phase 3a: global keymap remap (uncomment to test)
        -- keymaps = {
        --   ["gs"] = "<leader>gs",  -- rename live_search key
        --   ["I"]  = false,          -- disable node_info keymap
        -- },

        -- Phase 3b: rename :Filetree command (uncomment to test)
        -- command = { name = "Ft", aliases = { "Filetree" } },

        -- Phase 3c: disable specific feature autocmds (uncomment to test)
        -- autocmds = { auto_reveal = false },

        -- ignore_list: hide .git, node_modules, etc. (true = default, false = show all, {…} = custom list)
        -- ignore_list = false,                          -- show everything
        -- ignore_list = { ".git", "node_modules" },    -- custom list (overrides built-in defaults)

        -- Noop neotree's built-in `i` (run_command) so shell_run can use it
        adapter_keymaps = { ["i"] = false },

        features = {
          -- ── Group A: Adapter basics ──────────────────────────────────────
          -- Tests: is_open(), get_current_node(), get_visible_nodes(), refresh()
          current_hl = {
            enabled     = true,
            file_hl     = "CursorLine",
            parent_hl   = "Visual",
            debounce_ms = 100,
          },

          -- ── Group B: CWD / reveal ────────────────────────────────────────
          -- Tests: autocmds, adapter.open_reveal()
          cwd_sync = {
            enabled       = true,
            debounce_ms   = 150,
            parent_levels = 0,
            keep_focus    = true,
          },
          auto_reveal = {
            enabled      = true,
            debounce_ms  = 200,
            keep_focus   = true,
          },

          -- ── Group C: Virtual text / extmarks ─────────────────────────────
          -- Tests: nvim_buf_set_extmark, EOL virt_text
          marks = {
            enabled           = true,
            indicator         = "✓",
            hl_group          = "DiagnosticOk",
            keymap            = "m",
            keymap_all        = "]m",
            keymap_unmark_all = "[m",
            keymap_clear      = "<C-m>",
            keymap_show       = "<leader>ms",
          },
          git_status = {
            enabled    = true,
            debounce_ms = 300,
            symbols    = { added = "+", modified = "~", deleted = "-", renamed = "r", untracked = "?" },
            hl = {
              added     = "DiagnosticOk",
              modified  = "DiagnosticWarn",
              deleted   = "DiagnosticError",
              untracked = "Comment",
            },
          },

          -- ── Group D: Floating windows ─────────────────────────────────────
          -- Tests: nvim_open_win, buffer keymaps, close-on-q
          node_info = {
            enabled        = true,
            keymap         = "I",
            show_lines     = true,
            max_lines_size = 5 * 1024 * 1024,
          },
          preview = {
            enabled     = true,
            keymap      = "<Tab>",
            keymap_open = "<CR>",
            max_lines   = 40,
            image = { backend = "auto" },     -- images: snacks → image.nvim → system
            pdf   = { backend = "pdfport" },  -- PDFs: pdfport.nvim → system
          },

          -- ── Group K: Cursor / reset / save ───────────────────────────────
          cursor_hide = {
            enabled = true,
          },
          tree_reset = {
            enabled = true,
            keymap  = "<Esc>",
          },
          buffer_save = {
            enabled         = true,
            keymap_adjacent = "<C-s>",
            keymap_node     = "<M-s>",
            force           = true,
          },
          open_replace = {
            enabled = true,
            keymap  = "O",
          },
          reveal_alt = {
            enabled = true,
            keymap  = "B",
          },

          -- ── Group L: Window / system / shell ─────────────────────────────
          window_size_cycler = {
            enabled = true,
            keymap  = "w",
            sizes   = { 35, 55, 18 },
          },
          open_in_fm = {
            enabled = true,
            keymap  = "<leader>fm",
          },
          shell_run = {
            enabled     = true,
            keymap      = "i",    -- neotree's `i` nooped via adapter_keymaps above
            close_on_ok = true,
            split       = "split",
            height      = 12,
          },

          -- ── Group E: Input / search ───────────────────────────────────────
          -- Tests: vim.ui.input, floating prompt buffer, dimming
          filter = {
            enabled = true,
            keymap  = "/",
            hl_dim  = "Comment",
          },
          live_search = {
            enabled          = true,
            keymap           = "gs",  -- "?" conflicts with neotree cheatsheet
            debounce_ms      = 80,
            hl_dim           = "Comment",
            commit_to_filter = true,
          },

          -- ── Group F: Clipboard / copy ─────────────────────────────────────
          -- Tests: vim.fn.setreg, notify
          path_copy = {
            enabled      = true,
            keymap_abs   = "[a",          -- copy absolute path (original: [a)
            keymap_rel   = "]a",          -- copy base/dir path  (original: ]a)
            keymap_pick  = "<leader>yp",  -- format picker
            keymap_name  = "<leader>yn",  -- filename only
          },
          copy_file_list = {
            enabled          = true,
            keymap_files_abs = "[f",
            keymap_files_rel = "]f",
            keymap_dirs_abs  = "[F",
            keymap_dirs_rel  = "]F",
            preview_limit    = 5,
          },
          lua_require_copy = {
            enabled = true,
            keymap  = "rq",
          },

          -- ── Group G: Navigation ───────────────────────────────────────────
          -- Tests: adapter.open_reveal(), cwd changes
          tree_traverse = {
            enabled      = true,
            keymap_up    = "-",   -- navigate to parent (original: -)
            keymap_down  = "+",   -- set dir as root    (original: +)
            sync_cwd     = true,
          },

          -- ── Group H: Find / grep ──────────────────────────────────────────
          -- Tests: telescope/fzf-lua cascade, vim.ui.select fallback
          find_or_grep_menu = {
            enabled = true,
            keymap  = "<M-p>",
            prefer  = "auto",
          },
        },
      })
    end,
  },
}, {
  root    = vim.fn.stdpath("data") .. "/lazy",
  lockfile = tmp .. "/lazy-lock.json",
  performance = {
    reset_packpath = false,  -- keep system plugins accessible
  },
})

-- ── Test keymaps (outside tree buffer) ───────────────────────────────────────

-- Toggle neo-tree
vim.keymap.set("n", "<C-e>", "<cmd>Neotree toggle<cr>",
  { desc = "Toggle neo-tree" })

-- Open neo-tree at cwd
vim.keymap.set("n", "<leader>e", "<cmd>Neotree reveal<cr>",
  { desc = "Reveal current file in neo-tree" })

-- checkhealth shortcut
vim.keymap.set("n", "<leader>H", "<cmd>checkhealth filetree<cr>",
  { desc = "filetree health check" })

-- Print active adapter info
vim.keymap.set("n", "<leader>fa", function()
  local ok, ft = pcall(require, "filetree")
  if not ok then vim.notify("filetree not loaded", vim.log.levels.ERROR); return end
  local a = ft.adapter()
  if a then
    vim.notify("Active adapter: " .. a.name, vim.log.levels.INFO)
  else
    vim.notify("No adapter resolved", vim.log.levels.WARN)
  end
end, { desc = "Print active filetree adapter" })

-- Print current node info (raw)
vim.keymap.set("n", "<leader>fn", function()
  local ok, ft = pcall(require, "filetree")
  if not ok then return end
  local a = ft.adapter()
  if not a then vim.notify("No adapter", vim.log.levels.WARN); return end
  local node = a.get_current_node()
  if node then
    vim.notify(vim.inspect(node), vim.log.levels.INFO)
  else
    vim.notify("No node under cursor (are you in the tree?)", vim.log.levels.WARN)
  end
end, { desc = "Inspect current tree node" })

-- ── Minimal colorscheme ───────────────────────────────────────────────────────
vim.cmd("colorscheme habamax")

-- ── Startup message ───────────────────────────────────────────────────────────
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.defer_fn(function()
      vim.notify(
        "filetree.nvim test env\n"
        .. "  <C-e>      toggle neo-tree\n"
        .. "  <leader>e  reveal current file\n"
        .. "  <leader>H  checkhealth filetree\n"
        .. "  <leader>fa print active adapter\n"
        .. "  <leader>fn inspect node under cursor",
        vim.log.levels.INFO,
        { title = "filetree test" }
      )
    end, 500)
  end,
})
