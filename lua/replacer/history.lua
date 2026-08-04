---@module 'replacer.history'
--- Recent replace applies (last 50), stored at
--- stdpath("data")/replacer/history.json. :ReplaceHistory re-runs a past
--- entry via vim.ui.select.

local notify = require("replacer.util.notify")

local M = {}

local MAX_ENTRIES = 50

---@internal
---@return string
local function history_path()
  return vim.fn.stdpath("data") .. "/replacer/history.json"
end

--- Load the stored history, newest first. Never errors; returns {} on any
--- read/parse failure (e.g. first run, no file yet).
---@return table[]
function M.load()
  local ok, lines = pcall(vim.fn.readfile, history_path())
  if not ok or type(lines) ~= "table" or #lines == 0 then return {} end
  local ok_json, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok_json or type(data) ~= "table" then return {} end
  return data
end

---@internal
---@param history table[]
local function save(history)
  require("lib.nvim.fs.write.to_file")(history_path(), vim.json.encode(history))
end

--- Record one apply. Only called after a real apply (never for
--- dry-run/export/quickfix, which don't change anything). Guarded by the
--- caller with pcall — a history-write failure must never affect the apply
--- it's recording.
---@param request RP_Request
---@param result { files: integer, spots: integer }|nil
---@return nil
function M.add(request, result)
  if not request or not request.old or request.old == "" then return end
  local history = M.load()
  table.insert(history, 1, {
    timestamp = os.time(),
    old = request.old,
    new = request.new,
    scope = request.scope,
    all = request.all and true or false,
    files = result and result.files or nil,
    spots = result and result.spots or nil,
  })
  while #history > MAX_ENTRIES do table.remove(history) end
  save(history)
end

---@internal
---@param entry table
---@return string
local function format_entry(entry)
  return string.format(
    "%s | %s -> %s | scope=%s%s",
    os.date("%Y-%m-%d %H:%M", entry.timestamp),
    entry.old, entry.new,
    (entry.scope ~= nil and entry.scope ~= "") and entry.scope or "(default)",
    entry.files and string.format(" | %d file(s)/%d spot(s)", entry.files, entry.spots or 0) or "")
end

--- Open vim.ui.select over recent runs; on selection, re-run it (in the
--- interactive picker unless the original run was --all) via `run_fun`.
---@param run_fun fun(request: RP_Request): nil
---@return nil
function M.pick(run_fun)
  local history = M.load()
  if #history == 0 then
    notify.info("no replace history yet")
    return
  end
  local display = {}
  for i, entry in ipairs(history) do
    display[i] = format_entry(entry)
  end
  require("lib.nvim.ui.kit").select({
    items = display,
    title = "Replace history:",
    on_select = function(_, idx)
      local choice = history[idx]
      if not choice then return end
      ---@type RP_Request
      local req = {
        old = choice.old, new = choice.new, scope = choice.scope or "",
        all = choice.all and true or false, dry = false, export = nil, line_range = nil,
        overrides = {}, filters = { file_types = {}, globs = {}, exclude = {} },
      }
      run_fun(req)
    end,
  })
end

--- Register :ReplaceHistory.
---@param run_fun fun(request: RP_Request): nil
---@return nil
function M.register(run_fun)
  local usercmd = require("lib.nvim.usercmd")
  usercmd.create("ReplaceHistory", function() M.pick(run_fun) end, {
    desc = "Re-run a recent :Replace from history: :ReplaceHistory",
  })
end

return M
