---@module 'replacer.perfile'
--- Per-file confirmation step for ALL-mode applies (--confirm-per-file):
--- instead of one global "apply ALL N spots across M files?" confirm, ask
--- All/Skip/Only-some/Quit for each file in turn.
---
--- Uses ui.kit.confirm, which is async/callback-based (no blocking
--- return value like the native vim.fn.confirm this replaces). The file loop
--- is therefore callback-recursive: each file's confirm only advances to the
--- next one from inside its own on_answer callback, and the final totals are
--- delivered via `on_done` instead of a synchronous return. "Only some"
--- hands off to an open-ended picker session and stops the loop right
--- there (like "Quit") rather than racing the next file's confirm float
--- against that still-open picker -- see the "Only some" branch below.

local confirm = require("ui.kit.confirm")
local notify = require("replacer.util.notify")

local M = {}

---@internal
--- Group matches by file path, returning a stable (sorted) path order so
--- the confirmation sequence is deterministic/reproducible.
---@param items RP_Match[]
---@return table<string, RP_Match[]> by_path, string[] paths
local function group_by_path_sorted(items)
  local by_path = {}
  for i = 1, #items do
    local it = items[i]
    local t = by_path[it.path]
    if not t then
      t = {}
      by_path[it.path] = t
    end
    t[#t + 1] = it
  end
  local paths = {}
  for p in pairs(by_path) do
    paths[#paths + 1] = p
  end
  table.sort(paths)
  return by_path, paths
end

--- Run the per-file confirmation loop, applying accepted files immediately.
---@param items RP_Match[]
---@param new_text string
---@param write_changes boolean
---@param apply_func fun(items: RP_Match[], new_text: string, write_changes: boolean, on_result?: fun(files: integer, spots: integer))
---@param on_pick_file fun(items: RP_Match[])   # "Only some": open a picker scoped to this file
---@param on_done fun(files: integer, spots: integer)  # called once the loop ends (Quit/<Esc>/Only-some or all files seen)
function M.run(items, new_text, write_changes, apply_func, on_pick_file, on_done)
  local by_path, paths = group_by_path_sorted(items)
  local total_files, total_spots = 0, 0

  local step

  step = function(i)
    local path = paths[i]
    if not path then
      on_done(total_files, total_spots)
      return
    end

    local list = by_path[path]
    local rel = vim.fn.fnamemodify(path, ":.")

    confirm.open({
      question = string.format("%s (%d match(es))", rel, #list),
      choices = { "All", "Skip", "Only some", "Quit" },
      on_answer = function(choice)
        if choice == "All" then
          -- apply_func may apply asynchronously (wide file set); advance the
          -- per-file loop only once it has settled so the totals are accurate.
          apply_func(list, new_text, write_changes, function(f, s)
            total_files = total_files + f
            total_spots = total_spots + s
            step(i + 1)
          end)
          return
        elseif choice == "Only some" then
          -- UI-53: hand off to the picker for this file and STOP the loop
          -- here instead of immediately advancing to the next file's
          -- confirm float. `on_pick_file` opens an open-ended, asynchronous
          -- UI session (telescope/fzf-lua) with no completion signal back
          -- to this loop; stacking the next confirm float on top of it
          -- while it's still open corrupts the picker's internal registry
          -- (the same class of bug pickers/telescope.lua's `do_all` already
          -- guards against by closing its own picker before opening a
          -- second float). Remaining files are simply not reviewed by this
          -- run -- re-run with --confirm-per-file to continue with them.
          on_pick_file(list)
          local remaining = #paths - i
          if remaining > 0 then
            notify.info(
              string.format(
                "confirm-per-file: stopped after handing '%s' to the picker -- %d file(s) not yet reviewed",
                rel,
                remaining
              )
            )
          end
          on_done(total_files, total_spots)
          return
        elseif choice == nil or choice == "Quit" then -- <Esc>/q or explicit Quit
          on_done(total_files, total_spots)
          return
        end
        -- "Skip": continue to the next file.
        step(i + 1)
      end,
    })
  end

  step(1)
end

return M
