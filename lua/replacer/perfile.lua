---@module 'replacer.perfile'
--- Per-file confirmation step for ALL-mode applies (--confirm-per-file):
--- instead of one global "apply ALL N spots across M files?" confirm, ask
--- All/Skip/Only-some/Quit for each file in turn.
---
--- Uses the native, synchronous vim.fn.confirm() rather than
--- lib.nvim.ui.kit.confirm — a modal multi-choice prompt per file is exactly
--- what vim.fn.confirm is for, and a blocking prompt is the expected/normal
--- interaction here (same as e.g. :confirm quit), so there's no need to
--- chain async confirms through a recursive callback.

local M = {}

--- Group matches by file path, returning a stable (sorted) path order so
--- the confirmation sequence is deterministic/reproducible.
---@param items RP_Match[]
---@return table<string, RP_Match[]> by_path, string[] paths
local function group_by_path_sorted(items)
  local by_path = {}
  for i = 1, #items do
    local it = items[i]
    local t = by_path[it.path]
    if not t then t = {}; by_path[it.path] = t end
    t[#t + 1] = it
  end
  local paths = {}
  for p in pairs(by_path) do paths[#paths + 1] = p end
  table.sort(paths)
  return by_path, paths
end

--- Run the per-file confirmation loop, applying accepted files immediately.
---@param items RP_Match[]
---@param new_text string
---@param write_changes boolean
---@param apply_func fun(items: RP_Match[], new_text: string, write_changes: boolean): integer, integer
---@param on_pick_file fun(items: RP_Match[])   # "Only some": open a picker scoped to this file
---@return integer files, integer spots
function M.run(items, new_text, write_changes, apply_func, on_pick_file)
  local by_path, paths = group_by_path_sorted(items)
  local total_files, total_spots = 0, 0

  for _, path in ipairs(paths) do
    local list = by_path[path]
    local rel = vim.fn.fnamemodify(path, ":.")
    local choice = vim.fn.confirm(
      string.format("%s (%d match(es))", rel, #list),
      "&All\n&Skip\n&Only some\n&Quit", 1)

    if choice == 1 then -- All
      local f, s = apply_func(list, new_text, write_changes)
      total_files = total_files + f
      total_spots = total_spots + s
    elseif choice == 3 then -- Only some -> hand off to the picker for this file
      on_pick_file(list)
    elseif choice == 0 or choice == 4 then -- <Esc>/Quit
      break
    end
    -- choice == 2 (Skip): fall through to the next file.
  end

  return total_files, total_spots
end

return M
