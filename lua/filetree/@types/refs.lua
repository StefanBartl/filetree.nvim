---@meta
---@module 'filetree.@types.refs'
--- Types for the reference engine (`filetree.refs`) — the subsystem that keeps
--- cross-file references (markdown links, require()/import statements) pointing
--- at the right file after a rename, move or delete.

---A single reference found in a file, pointing at a path that is about to move
---(or has just moved).
---
---`col`/`#target` locate the exact byte range of the reference *inside* `text`,
---so applying a change never has to pattern-match the whole line: the apply
---step verifies that `text:sub(col, col + #target - 1) == target` still holds
---and rewrites exactly that slice. A drifted line (unsaved edits) therefore
---fails verification and is skipped instead of being corrupted.
---@class FiletreeRef
---@field file       string   Absolute path of the file containing the reference.
---@field line       integer  1-based line number inside `file`.
---@field col        integer  1-based byte column of `target` within the line.
---@field text       string   Full line content at scan time.
---@field target     string   The reference exactly as written ("./Test.md", "foo.bar").
---@field new_target string?  Replacement text; set by the resolve step.
---@field provider   string   Name of the provider that produced this ref.
---@field source     string   Absolute path this reference points at (the moved item).
---@field display    string   Picker/quickfix display text.

---Everything a provider needs to know about one pending mutation.
---@class FiletreeRefCtx
---@field root   string   Search root (project root or cwd).
---@field is_dir boolean  Whether the moved item is a directory.
---@field cfg    FiletreeRefsConfig

---A provider's per-path plan: the search recipe plus the two callbacks that
---turn candidate lines into refs and refs into new targets. Returning nil from
---`plan()` means "this provider has nothing to do for this path" (e.g. the Lua
---provider for a file outside any `lua/` root).
---@class FiletreeRefPlan
---@field needles    string[]  Fixed strings for the ripgrep pre-filter.
---@field extensions string[]  Extensions of files that may contain such refs.
---@field extract    fun(file: string, lineno: integer, text: string): FiletreeRef[]
---@field retarget   fun(ref: FiletreeRef, new_path: string): string|nil

---@class FiletreeRefProvider
---@field name string
---@field plan fun(old_path: string, ctx: FiletreeRefCtx): FiletreeRefPlan|nil

---Result of a scan: the refs themselves plus the plans that produced them
---(kept so the resolve step can call the right `retarget`).
---@class FiletreeRefScanResult
---@field refs  FiletreeRef[]
---@field plans table<string, table<string, FiletreeRefPlan>>  source path → provider → plan

---@class FiletreeRefsScanConfig
---@field root              "project"|"cwd"  Search root (default "project").
---@field respect_gitignore boolean          Pass ripgrep's ignore rules (default true).
---@field max_files         integer          Cap for the no-ripgrep fallback walk (default 5000).
---@field timeout_ms        integer          Per-scan timeout (default 3000).

---@class FiletreeRefsProvidersConfig
---@field markdown boolean
---@field lua      boolean
---@field python   boolean
---@field ts_js    boolean

---@class FiletreeRefsConfig
---@field enabled     boolean
---@field providers   FiletreeRefsProvidersConfig
---@field on_rename   "ask"|"auto"|"off"
---@field on_move     "ask"|"auto"|"off"
---@field on_delete   "ask"|"auto"|"off"
---@field copy        boolean   Scan for refs on a *copy* too (default false: a copy breaks nothing).
---@field picker      "auto"|"telescope"|"fzf-lua"|"quickfix"
---@field prefer_lsp  boolean   Skip textual code providers when an LSP client applied a workspace edit.
---@field wiki_links  boolean   Also rewrite `[[wiki]]`-style markdown links (default false).
---@field scan        FiletreeRefsScanConfig
---@field undo        boolean   Keep an undo token per apply (default true).
---@field undo_depth  integer?  How many applies stay undoable (default 10). The stack holds only the replaced line content, so raising this is cheap.

---One entry of the undo stack: the lines an apply replaced, per file.
---@class FiletreeRefsUndoEntry
---@field file  string
---@field lines table<integer, string>  line number → content before the apply

return {}
