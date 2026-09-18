---@module 'replacer.presets'
--- Named, reusable replace requests, stored at
--- stdpath("data")/replacer/presets.json.
---   :ReplaceSavePreset {name} {old} {new} [scope] [--flags]
---   :ReplacePreset {name}   -- re-runs it exactly as saved

local notify = require("replacer.util.notify")

local M = {}

---@internal
---@return string
local function presets_path()
  return vim.fn.stdpath("data") .. "/replacer/presets.json"
end

--- Load the stored presets (name -> body). Never errors; returns {} on any
--- read/parse failure (e.g. first run, no file yet).
---
--- A decode failure on non-empty content is not the same situation as no
--- file existing at all: `M.save`/`M.delete` always rewrite the WHOLE file
--- via `save`, so falling straight through to an empty table here means the
--- very next `:ReplaceSavePreset`/`:ReplacePreset` deletion silently
--- replaces the corrupt file with a fresh one-entry file — every other
--- saved preset is gone with no trace it ever existed. Back up the original
--- bytes once, same as `replacer.history` (same load-modify-save shape), so
--- "the file was briefly unreadable" never turns into "every preset is
--- gone".
---@return table<string, table>
function M.load()
  local ok, lines = pcall(vim.fn.readfile, presets_path())
  if not ok or type(lines) ~= "table" or #lines == 0 then
    return {}
  end
  local raw = table.concat(lines, "\n")
  local ok_json, data = pcall(vim.json.decode, raw)
  if not ok_json or type(data) ~= "table" then
    local fh = io.open(presets_path() .. ".corrupt", "wb")
    if fh then
      fh:write(raw)
      fh:close()
    end
    return {}
  end
  return data
end

---@internal
---@param presets table<string, table>
local function save(presets)
  require("lib.nvim.fs.write.to_file")(presets_path(), vim.json.encode(presets))
end

--- Save `request` under `name`, overwriting any existing preset of that name.
---@param name string
---@param request RP_Request
---@return nil
function M.save(name, request)
  local presets = M.load()
  presets[name] = {
    old = request.old,
    new = request.new,
    scope = request.scope,
    all = request.all and true or false,
    overrides = request.overrides or {},
    filters = request.filters or { file_types = {}, globs = {}, exclude = {} },
  }
  save(presets)
end

-- SEC-33: presets.json is a persisted snapshot -- untrusted on load (a hand
-- edit, a truncated write, a future format). No single filter list from it
-- is expected to legitimately need more than a handful of entries; this
-- caps each one so a corrupted/malicious file can't blow up the argv built
-- from it downstream (rg spawn, glob matching).
local MAX_FILTER_ENTRIES = 200

---@internal
--- Coerce `v` into a clean array of strings, dropping non-string entries
--- and entries beyond `MAX_FILTER_ENTRIES` (SEC-33: type + count cap).
---@param v any
---@return string[]
local function safe_string_list(v)
  if type(v) ~= "table" then
    return {}
  end
  local out = {}
  for i = 1, math.min(#v, MAX_FILTER_ENTRIES) do
    if type(v[i]) == "string" then
      out[#out + 1] = v[i]
    end
  end
  return out
end

--- Load a saved preset as a runnable RP_Request.
---
--- SEC-33: every field from the decoded preset is re-validated before it
--- reaches the replace pipeline -- a numeric/table `old`/`new`, a non-table
--- `filters`, or a non-table `overrides.changed_only` must be rejected
--- cleanly here instead of throwing deep inside init.lua/rg.lua/gitfiles.lua.
---@param name string
---@return RP_Request|nil req, string|nil err  # err is set only when the preset exists but is malformed
function M.as_request(name)
  local p = M.load()[name]
  if p == nil then
    return nil, nil
  end
  if type(p) ~= "table" or type(p.old) ~= "string" or type(p.new) ~= "string" then
    return nil, string.format("preset '%s' is corrupt (old/new must be strings)", name)
  end

  local overrides = (type(p.overrides) == "table") and vim.deepcopy(p.overrides) or {}
  -- `changed_only` bypasses cfg_mod.resolve()'s own coercion (it is read
  -- raw at the call site) and is handed straight to `ipairs`, which throws
  -- on a non-table.
  if overrides.changed_only ~= nil and type(overrides.changed_only) ~= "table" then
    overrides.changed_only = nil
  end

  local filters = (type(p.filters) == "table") and p.filters or {}

  ---@type RP_Request
  local req = {
    old = p.old,
    new = p.new,
    scope = (type(p.scope) == "string") and p.scope or "",
    all = p.all and true or false,
    dry = false,
    export = nil,
    line_range = nil,
    overrides = overrides,
    filters = {
      file_types = safe_string_list(filters.file_types),
      globs = safe_string_list(filters.globs),
      exclude = safe_string_list(filters.exclude),
    },
  }
  return req, nil
end

--- Delete a saved preset. No-op (not an error) if it doesn't exist.
---@param name string
---@return nil
function M.delete(name)
  local presets = M.load()
  if presets[name] == nil then
    return
  end
  presets[name] = nil
  save(presets)
end

--- Sorted preset names, for <Tab> completion.
---@return string[]
function M.names()
  local names = {}
  for name in pairs(M.load()) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local SAVE_USAGE = "Usage: :ReplaceSavePreset {name} {old} {new} [scope] [--flags]"

--- Register :ReplaceSavePreset and :ReplacePreset.
---@param run_fun fun(request: RP_Request): nil
---@return nil
function M.register(run_fun)
  local usercmd = require("lib.nvim.bindings.usercmd")
  local command = require("replacer.command")

  usercmd.create("ReplaceSavePreset", function(opts)
    local raw = (type(opts.args) == "string") and opts.args or ""
    local tokens, unterminated = command.tokenize(raw)
    if unterminated then
      notify.error("ReplaceSavePreset: unterminated quote in argument list.\n" .. SAVE_USAGE)
      return
    end
    if #tokens == 0 then
      notify.error(SAVE_USAGE)
      return
    end
    local name = table.remove(tokens, 1)

    ---@type RP_Request
    local req = {
      old = "",
      new = "",
      scope = "",
      all = false,
      dry = false,
      export = nil,
      line_range = nil,
      overrides = {},
      filters = { file_types = {}, globs = {}, exclude = {} },
    }
    local positionals, err = command.apply_tokens(tokens, req)
    if not positionals then
      notify.error("ReplaceSavePreset: " .. err)
      return
    end
    if #positionals < 2 or #positionals > 3 then
      notify.error(SAVE_USAGE)
      return
    end
    req.old, req.new, req.scope = positionals[1], positionals[2], positionals[3] or ""

    M.save(name, req)
    notify.info(string.format("preset '%s' saved: %s -> %s", name, req.old, req.new))
  end, { nargs = "+", desc = SAVE_USAGE })

  usercmd.create("ReplacePreset", function(opts)
    local name = (type(opts.args) == "string") and opts.args or ""
    if name == "" then
      notify.error("Usage: :ReplacePreset {name}")
      return
    end
    local req, err = M.as_request(name)
    if not req then
      notify.error(err or ("no such preset: '" .. name .. "'"))
      return
    end
    run_fun(req)
  end, {
    nargs = 1,
    complete = function()
      return M.names()
    end,
    desc = "Run a saved preset: :ReplacePreset {name}",
  })
end

return M
