---@module 'replacer.checkpoint'
--- Undo checkpoint (--checkpoint): snapshot every file about to be touched
--- by a large ALL-mode apply into stdpath("data")/replacer/checkpoints/<id>/,
--- so :ReplaceUndo can restore them verbatim afterward.
---
--- Deliberately a plain file-snapshot, not git-stash/a temp branch: a stash
--- would also scoop up unrelated uncommitted work-in-progress in the same
--- repository, which is a correctness footgun this plugin has no business
--- introducing. A snapshot only ever touches files this run is about to
--- edit, and restoration is a byte-exact write-back (no newline-injection
--- or other normalization), so undo is exact.

local notify = require("replacer.util.notify")

local M = {}

---@return string
local function checkpoints_dir()
  return vim.fn.stdpath("data") .. "/replacer/checkpoints"
end

--- Sanitize an absolute path into a safe, flat filename for the snapshot dir.
---@param path string
---@return string
local function sanitize(path)
  return (path:gsub("[/\\:]", "_"))
end

--- Byte-exact write (no newline-injection/normalization) so a checkpoint
--- round-trip never alters file content.
---@param path string
---@param content string
---@return boolean
local function write_exact(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir ~= "" then pcall(vim.fn.mkdir, dir, "p") end
  local ok, fh = pcall(io.open, path, "wb")
  if not ok or not fh then return false end
  fh:write(content)
  fh:close()
  return true
end

--- Read a path's CURRENT content, preferring a loaded buffer over disk (so
--- the checkpoint reflects unsaved edits too, consistent with dry-run).
---@param path string
---@return string
local function read_current(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return table.concat(lines, "\n") .. "\n"
  end
  local ok, fh = pcall(io.open, path, "rb")
  if not ok or not fh then return "" end
  local content = fh:read("*a") or ""
  fh:close()
  return content
end

--------------------------------------------------------------------------------
-- Create
--------------------------------------------------------------------------------

--- Create a checkpoint of every distinct path in `items`. Returns the
--- checkpoint id (a timestamp-based directory name) on success, nil on
--- failure or when `items` touches no files.
---@param items RP_Match[]
---@return string|nil id
function M.create(items)
  local paths, seen = {}, {}
  for _, it in ipairs(items) do
    if not seen[it.path] then
      seen[it.path] = true
      paths[#paths + 1] = it.path
    end
  end
  if #paths == 0 then return nil end

  local id = os.date("%Y%m%d-%H%M%S") .. "-" .. tostring(math.random(1000, 9999))
  local dir = checkpoints_dir() .. "/" .. id
  local ok_mkdir = pcall(vim.fn.mkdir, dir, "p")
  if not ok_mkdir then return nil end

  local manifest = {}
  for _, path in ipairs(paths) do
    local snap_name = sanitize(path)
    if write_exact(dir .. "/" .. snap_name, read_current(path)) then
      manifest[#manifest + 1] = { path = path, snapshot = snap_name }
    end
  end
  if #manifest == 0 then return nil end

  local ok_manifest = require("lib.nvim.fs.write.to_file")(
    dir .. "/manifest.json", vim.json.encode(manifest))
  if not ok_manifest then return nil end

  return id
end

--------------------------------------------------------------------------------
-- List / Undo
--------------------------------------------------------------------------------

--- List existing checkpoint ids, most recent first (id is a sortable
--- timestamp prefix).
---@return string[]
function M.list()
  local ok, entries = pcall(vim.fn.readdir, checkpoints_dir())
  if not ok or type(entries) ~= "table" then return {} end
  table.sort(entries, function(a, b) return a > b end)
  return entries
end

--- Restore every file in checkpoint `id` (or the most recent one when nil)
--- from its snapshot: a byte-exact write to disk, plus a reload of any
--- currently loaded buffer for that path.
---@param id string|nil
---@return integer restored, string|nil err
function M.undo(id)
  if not id then
    id = M.list()[1]
    if not id then return 0, "no checkpoints found" end
  end

  local dir = checkpoints_dir() .. "/" .. id
  local ok_read, raw = pcall(vim.fn.readfile, dir .. "/manifest.json")
  if not ok_read or type(raw) ~= "table" or #raw == 0 then
    return 0, "checkpoint '" .. id .. "' not found"
  end
  local ok_json, manifest = pcall(vim.json.decode, table.concat(raw, "\n"))
  if not ok_json or type(manifest) ~= "table" then
    return 0, "checkpoint '" .. id .. "' manifest is corrupt"
  end

  local restored = 0
  for _, entry in ipairs(manifest) do
    local ok_snap, fh = pcall(io.open, dir .. "/" .. entry.snapshot, "rb")
    if ok_snap and fh then
      local content = fh:read("*a") or ""
      fh:close()
      if write_exact(entry.path, content) then
        restored = restored + 1
        local bufnr = vim.fn.bufnr(entry.path)
        if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
          pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd("silent! edit!") end)
        end
      else
        notify.warn("checkpoint: failed to restore " .. entry.path)
      end
    end
  end

  return restored, nil
end

--------------------------------------------------------------------------------
-- :ReplaceUndo
--------------------------------------------------------------------------------

--- Register :ReplaceUndo [id].
---@return nil
function M.register()
  local usercmd = require("lib.nvim.usercmd")
  usercmd.create("ReplaceUndo", function(opts)
    local id = (type(opts.args) == "string" and opts.args ~= "") and opts.args or nil
    local restored, err = M.undo(id)
    if err then
      notify.error("ReplaceUndo: " .. err)
      return
    end
    notify.info(string.format(
      "restored %d file(s) from checkpoint%s",
      restored, id and (" '" .. id .. "'") or " (most recent)"))
  end, {
    nargs = "?",
    complete = function() return M.list() end,
    desc = "Restore files from a replacer checkpoint: :ReplaceUndo [id]",
  })
end

return M
