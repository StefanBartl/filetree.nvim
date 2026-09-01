---@module 'filetree.features.infra.tree_integrity'
---@brief Keep neo-tree's nui.nvim tree consistent across a `set_nodes()` that
---       re-uses live nodes — the "Error setting nodes" crash.
---@description
--- Symptom (neo-tree + nui.nvim, both current; an upstream bug, not a
--- misconfiguration on our side):
---
--- ```
--- [Neo-tree ERROR] Error setting nodes:  .../nui/tree/init.lua:494:
--- attempt to index local 'node' (a nil value)
--- ```
---
--- followed by a dump of the entire tree, repeating on every render until
--- neo-tree is closed and re-opened.
---
--- ## What actually happens
---
--- 1. nui's `initialize_nodes()` *consumes* a node's children: it reads
---    `node.__children`, records their ids in `node._child_ids`, then sets
---    `node.__children = nil`. Initialization is therefore not idempotent — a
---    node that has been through it no longer knows its children, only their ids.
---
--- 2. `Tree:set_nodes(nodes, parent_id)` first drops the parent's current
---    subtree (`remove_node()` recursively deletes every descendant from
---    `nodes.by_id`), then re-initializes whatever it was handed. Hand it back
---    *live* nodes and step 1 bites: they are re-registered in `by_id`, but
---    their own children are not — `__children` is already nil, so the walk
---    stops there while `_child_ids` keeps listing ids that were just deleted.
---    The tree is now silently inconsistent.
---
--- 3. The next `set_nodes()` over that subtree walks those ids through
---    `remove_node()`, `tree.nodes.by_id[node_id]` yields nil, and indexing
---    `node` throws. It throws *before* `parent_node._child_ids` is reset, so
---    the inconsistency survives — every later render hits it again.
---
--- neo-tree reaches step 2 from exactly one place: the `group_empty_dirs` branch
--- for a lazily loaded single sub-folder (`ui/renderer.lua`, with the default
--- `scan_mode = "shallow"`), which re-exports the whole level via
--- `state.tree:get_nodes(parentId)` and passes those live nodes straight back
--- into `set_nodes`. Expanding a directory that sits next to a one-child chain
--- is enough to trigger it.
---
--- ## What this feature does
---
--- Wraps `NuiTree.set_nodes` with a pre-pass (`M.sanitize`) that runs before nui
--- touches anything:
---
--- * **Re-hydrate** — every live node passed in gets its children handed back as
---   `__children` (read out of `by_id` while that map is still intact), so the
---   re-initialization rebuilds the subtree instead of orphaning it. Nothing is
---   lost, expanded directories stay expanded, and the tree ends up in the state
---   the caller meant.
--- * **Heal** — any id already missing from `by_id` is dropped from the
---   `_child_ids` list nui is about to walk, so `remove_node()` cannot hit nil.
---   A session that is *already* broken repairs itself on the next render
---   instead of staying broken until neo-tree is re-opened.
---
--- Fresh nodes (the normal path: `create_nodes()` → `set_nodes()`) are not
--- touched at all — they carry no `_tree`, so the pre-pass skips them and nui
--- behaves exactly as before.

local notify = require("filetree.util.notify").create("[filetree.tree_integrity]")
local tree_attach = require("filetree.util.tree_attach")

local M = {}

---@type FiletreeTreeIntegrityConfig
local _cfg = {
  enabled = true,
  silent = true, -- only notifier.debug(...) output, and only when healing
}

---Original `NuiTree.set_nodes`, kept so teardown can put it back.
---@type function?
local _original = nil

---How many stale child ids this session has dropped (health / troubleshooting).
---@type integer
local _healed = 0

-- ── Pre-pass ──────────────────────────────────────────────────────────────────

---Drop ids that are no longer in `by_id` from `ids` — in place, because it is
---the very table nui is about to walk — recursively through the subtree it spans.
---@internal
---@param by_id table<string, table>
---@param ids   string[]?
---@param seen  table<string, true>  Cycle guard; a corrupt tree may loop.
---@return integer dropped
local function prune(by_id, ids, seen)
  if type(ids) ~= "table" then return 0 end

  local dropped, keep = 0, {}
  for _, id in ipairs(ids) do
    local node = by_id[id]
    if node == nil then
      dropped = dropped + 1
    else
      keep[#keep + 1] = id
      if not seen[id] then
        seen[id] = true
        dropped = dropped + prune(by_id, node._child_ids, seen)
      end
    end
  end

  if dropped > 0 then
    for i = #ids, 1, -1 do
      ids[i] = nil
    end
    for i, id in ipairs(keep) do
      ids[i] = id
    end
  end

  return dropped
end

---Hand a live node's children back as `__children`, so nui's re-initialization
---walks the whole subtree again instead of stopping at the node itself.
---@internal
---@param by_id table<string, table>
---@param node  table
---@param seen  table<string, true>
local function rehydrate(by_id, node, seen)
  local id = node._id
  if id ~= nil then
    if seen[id] then return end
    seen[id] = true
  end

  local child_ids = node._child_ids
  if type(child_ids) ~= "table" or #child_ids == 0 then return end

  local children = {}
  for _, child_id in ipairs(child_ids) do
    local child = by_id[child_id]
    if child ~= nil then
      rehydrate(by_id, child, seen)
      children[#children + 1] = child
    end
  end

  node.__children = children
  -- An *empty table*, deliberately, not nil. `has_children()` reads
  -- `_child_ids or __children`, so an empty list makes nui's `remove_node()`
  -- stop at this node rather than detaching the very children we just handed
  -- back; and `initialize_nodes()` appends into the existing table, so leaving
  -- the old ids in place would duplicate every one of them.
  node._child_ids = {}
end

---Make `tree` safe for the `set_nodes(nodes, parent_id)` that is about to run.
---Public because it *is* the feature — the wrapper around it is a two-line
---delegate — and because it is the part worth testing (and worth calling by
---hand from a repro).
---@param tree      any      NuiTree instance (nui's internals carry no types we can name).
---@param nodes     any      Nodes about to be handed to `set_nodes`.
---@param parent_id string?  Parent whose children are being replaced.
---@return integer dropped   Stale child ids removed (0 on a healthy tree).
function M.sanitize(tree, nodes, parent_id)
  local store = type(tree) == "table" and tree.nodes or nil
  local by_id = type(store) == "table" and store.by_id or nil
  if type(by_id) ~= "table" then return 0 end

  -- 1. Heal the ids nui is about to walk through `remove_node()`. On a healthy
  --    tree this finds nothing, at the cost of one pass over the doomed subtree.
  -- `store` is nui's own node table; `root_ids` is its internal index and
  -- carries no annotation upstream.
  ---@type integer[]|nil
  local doomed = store.root_ids
  if parent_id ~= nil then
    local parent = by_id[parent_id]
    doomed = parent and parent._child_ids or nil
  end
  local dropped = prune(by_id, doomed, {})

  -- 2. Re-hydrate, but only nodes that already belong to *this* tree: fresh ones
  --    still carry their `__children` and must be left exactly as they are.
  if type(nodes) == "table" then
    local seen = {}
    for _, node in ipairs(nodes) do
      if type(node) == "table" and node._initialized and node._tree == tree then
        rehydrate(by_id, node, seen)
      end
    end
  end

  return dropped
end

-- ── Patch ─────────────────────────────────────────────────────────────────────

---Install the `NuiTree.set_nodes` wrapper. Idempotent, and a no-op while nui is
---not loadable, so callers can simply retry later.
---@return boolean installed
function M.install()
  if _original then return true end

  local ok, NuiTree = pcall(require, "nui.tree")
  if not ok or type(NuiTree) ~= "table" then return false end

  local original = NuiTree.set_nodes
  if type(original) ~= "function" then return false end
  _original = original

  -- nui builds its classes middleclass-style: assigning on the class propagates
  -- into the shared instance metatable, so trees that already exist (an open
  -- neo-tree) pick this up too.
  NuiTree.set_nodes = function(self, nodes, parent_id)
    local ok_pre, dropped = pcall(M.sanitize, self, nodes, parent_id)
    if not ok_pre then
      -- Never let the guard itself be what breaks rendering: fall through to
      -- unpatched behaviour, which is no worse than not running the feature.
      notify.debug("sanitize failed: " .. tostring(dropped))
    elseif dropped > 0 then
      _healed = _healed + dropped
      if not _cfg.silent then
        notify.debug(("healed %d stale child id(s) before set_nodes"):format(dropped))
      end
    end
    return original(self, nodes, parent_id)
  end

  return true
end

---Whether the wrapper is currently installed.
---@return boolean
function M.installed()
  return _original ~= nil
end

---Stale child ids dropped since setup (0 means nothing was ever corrupt).
---@return integer
function M.healed()
  return _healed
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param config  FiletreeTreeIntegrityConfig
---@param adapter FiletreeAdapter
function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg = vim.tbl_deep_extend("force", _cfg, config)

  -- nui.nvim is neo-tree's tree implementation; no other adapter has one.
  if not adapter or adapter.name ~= "neotree" then return end

  -- Patch now if nui is already loaded, otherwise wait for the tree buffer
  -- rather than `require`-ing nui at startup: pulling in a lazy plugin's module
  -- just to wrap one method would cost every session that load time, and the
  -- crash cannot happen before a tree exists anyway.
  if package.loaded["nui.tree"] then
    M.install()
  else
    tree_attach.on_attach(function()
      M.install()
    end)
  end
end

function M.teardown()
  if not _original then return end
  local ok, NuiTree = pcall(require, "nui.tree")
  if ok and type(NuiTree) == "table" then NuiTree.set_nodes = _original end
  _original = nil
end

return M
