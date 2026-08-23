---@module 'filetree.refs.ui'
--- The chooser shown after a rename/move found references, plus its two
--- sub-views: the multi-select picker (`filetree.util.refs_picker`, shared with
--- the trash flow) and a read-only unified diff of everything that would
--- change.
---
--- One chooser for *all* providers together — a move that breaks two markdown
--- links and one `require()` asks once, not twice:
---
---   7 reference(s) in 4 file(s) (5 markdown, 2 lua)
---     ▸ Update all
---     ▸ Select…       → picker, Tab/C-a multi-select
---     ▸ Show diff     → unified diff, then back to this chooser
---     ▸ Leave as-is

local kit = require("lib.nvim.ui.kit")
local confirm_choice = require("filetree.util.confirm_choice")
local refs_picker = require("filetree.util.refs_picker")
local notify = require("filetree.util.notify").create("[filetree.refs]")
local apply = require("filetree.refs.apply")

local M = {}

-- ── Summaries ─────────────────────────────────────────────────────────────────

---Deduplicated, cwd-relative list of the files a set of refs lives in, in
---order of first appearance.
---@param refs FiletreeRef[]
---@return string[]
function M.unique_files(refs)
  local seen, files = {}, {}
  for _, r in ipairs(refs) do
    if not seen[r.file] then
      seen[r.file] = true
      files[#files + 1] = vim.fn.fnamemodify(r.file, ":.")
    end
  end
  return files
end

---"7 reference(s) in 4 file(s) (5 markdown, 2 lua)"
---@param refs FiletreeRef[]
---@return string
function M.summary(refs)
  local files = M.unique_files(refs)
  local order, counts = {}, {}
  for _, r in ipairs(refs) do
    if not counts[r.provider] then
      counts[r.provider] = 0
      order[#order + 1] = r.provider
    end
    counts[r.provider] = counts[r.provider] + 1
  end

  local parts = {}
  for _, name in ipairs(order) do
    parts[#parts + 1] = string.format("%d %s", counts[name], name)
  end

  return string.format("%d reference(s) in %d file(s) (%s)",
    #refs, #files, table.concat(parts, ", "))
end

-- ── Diff view ─────────────────────────────────────────────────────────────────

---Open a read-only unified diff of what applying `refs` would change.
---@param refs FiletreeRef[]
---@param on_close fun()
function M.show_diff(refs, on_close)
  local rows = apply.preview(refs)
  if #rows == 0 then
    notify.info("Nothing left to change (references already updated?)")
    on_close()
    return
  end

  local lines, current = {}, nil
  for _, row in ipairs(rows) do
    if row.file ~= current then
      current = row.file
      local rel = vim.fn.fnamemodify(row.file, ":.")
      if #lines > 0 then lines[#lines + 1] = "" end
      lines[#lines + 1] = "--- a/" .. rel
      lines[#lines + 1] = "+++ b/" .. rel
    end
    lines[#lines + 1] = string.format("@@ line %d @@", row.line)
    lines[#lines + 1] = "-" .. row.before
    lines[#lines + 1] = "+" .. row.after
  end

  local surf = kit.viewer({
    title = " Reference changes ",
    lines = lines,
    filetype = "diff",
  })
  if surf and surf.on_close then
    surf:on_close(function() vim.schedule(on_close) end)
  else
    on_close()
  end
end

-- ── Chooser ───────────────────────────────────────────────────────────────────

---@internal
---@param refs FiletreeRef[]
---@param opts { label?: string }
local function do_apply(refs, opts)
  local applied, files_changed = apply.run(refs, { label = opts.label })
  if applied > 0 then
    notify.info(string.format("Updated %d reference(s) in %d file(s)%s",
      applied, files_changed,
      applied < #refs and string.format(" (%d skipped: line changed since the scan)", #refs - applied) or ""))
  else
    notify.warn("No reference could be updated (lines changed since the scan?)")
  end
  return applied
end

---Ask what to do with `refs`, then do it.
---@param refs FiletreeRef[]
---@param opts { mode: "ask"|"auto"|"off", picker?: string, title?: string, label?: string }
---@param done? fun(applied: integer)
function M.confirm_and_apply(refs, opts, done)
  done = done or function() end
  if #refs == 0 or opts.mode == "off" then return done(0) end

  if opts.mode == "auto" then
    return done(do_apply(refs, opts))
  end

  local title = opts.title or "References"
  notify.info(M.summary(refs) .. ": " .. table.concat(M.unique_files(refs), ", "))

  local function ask()
    confirm_choice(
      M.summary(refs),
      { "Update all", "Select…", "Show diff", "Leave as-is" },
      function(choice)
        if choice == "Update all" then
          done(do_apply(refs, opts))

        elseif choice == "Select…" then
          refs_picker.pick(
            refs,
            { prefer = opts.picker or "auto", title = title },
            function(selected)
              done(#selected > 0 and do_apply(selected, opts) or 0)
            end,
            function() done(0) end -- Esc: the mutation already happened, nothing to undo
          )

        elseif choice == "Show diff" then
          M.show_diff(refs, ask) -- back to the chooser once the diff closes

        else
          done(0) -- "Leave as-is" or dismissed
        end
      end
    )
  end

  ask()
end

return M
