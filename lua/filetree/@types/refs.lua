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
---@field lsp_exempt? boolean  This provider's language never gets a `willRenameFiles`
---                            rewrite from a server, so `refs.prefer_lsp` must not skip
---                            it. Set by the markdown and lua providers.
---@field delete_target? string  What a reference to a *deleted* file is rewritten to, so
---                              the dangling link stays visible. Only providers that
---                              declare one take part in `refs.for_delete`.
---@field extensions? string[]  Files that can hold this provider's link syntax at all.
---                              Read by `filetree.refs.outgoing` to skip a file the
---                              provider could never produce a match in; a provider
---                              without one is treated as unrestricted. Set by markdown.
---@field each_link_target? fun(text: string, cfg: FiletreeRefsConfig, fn: fun(col: integer, target: string, decoded: string, kind: string))
---                              Walk every path-like (non-external) link target in one
---                              line of text — the outgoing counterpart of `plan()`'s
---                              `extract` (which finds references *to* a specific path;
---                              this finds every link *from* one, regardless of target).
---                              Only providers that can link out to arbitrary files
---                              implement one — a code provider's outgoing references
---                              are require()/import statements pointing at code, never
---                              at binary assets, so it has nothing to contribute here.
---                              Set by markdown; used by `filetree.refs.outgoing`.

---One outgoing link found while scanning a file's own content for
---`filetree.refs.outgoing` — see that module for how it differs from `FiletreeRef`
---(which is always about a reference found *elsewhere*, pointing at the file
---being mutated).
---@class FiletreeOutgoingLink
---@field file     string   Absolute path of the file the link was found in (the scanned path).
---@field line     integer  1-based line number.
---@field col      integer  1-based byte column of the raw target within the line.
---@field text     string   Full line content at scan time.
---@field target   string   The link exactly as written ("./assets/shot.png"), undecoded.
---@field resolved string   Absolute path the target resolves to (best-effort).
---@field exists   boolean  Whether `resolved` names a file that exists on disk right now.
---@field provider string   Name of the provider that produced this link ("markdown").
---@field kind     string   Provider-specific link kind ("inline"|"refdef"|"html"|"wiki").
---@field display  string   Picker/quickfix display text.

---One outgoing link, classified for the cascade-delete-assets concept
---(`filetree.refs.assets`) — everything `FiletreeOutgoingLink` has, plus
---whether it qualifies as a deletable asset.
---@class FiletreeAssetCandidate : FiletreeOutgoingLink
---@field is_asset         boolean   Resolves under a configured assets root AND its extension is allowed.
---@field still_referenced boolean   Some file OTHER than the one being deleted still links to it. Only ever computed (and meaningful) when `is_asset` is true.
---@field referenced_by    string[]  Absolute paths of those other files, when `still_referenced`.

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
---@field markdown? boolean
---@field lua?      boolean
---@field python?   boolean
---@field ts_js?    boolean

---Config for the experimental `plaintext` provider: rewrite bare filesystem
---paths written as running text (prose or code comments), not just paths
---inside link/require/import syntax. Opt-in; a match is rewritten only when it
---resolves to exactly the moved file.
---@class FiletreeRefsPlaintextConfig
---@field enabled?            boolean   Turn the provider on (default false).
---@field comments?           boolean   Also scan comment lines in source files, not only prose/text files (default true).
---@field extensions?         string[]  Prose/text extensions scanned in full. Unset ⇒ provider built-in list (md, markdown, mdx, txt, text, rst, org, adoc, norg, …).
---@field comment_extensions? string[]  Source extensions whose comment lines are scanned. Unset ⇒ provider built-in list (lua, py, js, jsx, ts, tsx, sh, vim, c, cpp, rs, go, rb, java, toml, yaml, …).

---In-development reference features. Each is opt-in and its shape may change.
---@class FiletreeRefsExperimentalConfig
---@field plaintext? FiletreeRefsPlaintextConfig

---@class FiletreeRefsConfig
---@field enabled?    boolean
---@field providers?  FiletreeRefsProvidersConfig
---@field on_rename?  "ask"|"auto"|"off"
---@field on_move?    "ask"|"auto"|"off"
---@field on_delete?  "ask"|"auto"|"off"
---@field copy?       boolean   Scan for refs on a *copy* too (default false: a copy breaks nothing).
---@field picker?     "auto"|"telescope"|"fzf-lua"|"quickfix"
---@field prefer_lsp? boolean   Skip textual code providers when an LSP client applied a workspace edit.
---@field wiki_links? boolean   Also rewrite `[[wiki]]`-style markdown links (default false).
---@field experimental? FiletreeRefsExperimentalConfig  In-development reference features, each opt-in.
---@field scan?       FiletreeRefsScanConfig
---@field undo?       boolean   Keep an undo token per apply (default true).
---@field undo_depth  integer?  How many applies stay undoable (default 10). The stack holds only the replaced line content, so raising this is cheap.

---One entry of the undo stack: the lines an apply replaced, per file.
---@class FiletreeRefsUndoEntry
---@field file  string
---@field lines table<integer, string>  line number → content before the apply

return {}
