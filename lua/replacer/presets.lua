---@module 'replacer.presets'
--- Named, reusable replace requests, stored at
--- stdpath("data")/replacer/presets.json.
---   :ReplaceSavePreset {name} {old} {new} [scope] [--flags]
---   :ReplacePreset {name}   -- re-runs it exactly as saved

local notify = require("replacer.util.notify")

local M = {}

---@return string
local function presets_path()
  return vim.fn.stdpath("data") .. "/replacer/presets.json"
end

--- Load the stored presets (name -> body). Never errors; returns {} on any
--- read/parse failure (e.g. first run, no file yet).
---@return table<string, table>
function M.load()
  local ok, lines = pcall(vim.fn.readfile, presets_path())
  if not ok or type(lines) ~= "table" or #lines == 0 then return {} end
  local ok_json, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok_json or type(data) ~= "table" then return {} end
  return data
end

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
    old = request.old, new = request.new, scope = request.scope,
    all = request.all and true or false,
    overrides = request.overrides or {},
    filters = request.filters or { file_types = {}, globs = {}, exclude = {} },
  }
  save(presets)
end

--- Load a saved preset as a runnable RP_Request, or nil if unknown.
---@param name string
---@return RP_Request|nil
function M.as_request(name)
  local p = M.load()[name]
  if not p then return nil end
  return {
    old = p.old, new = p.new, scope = p.scope or "",
    all = p.all and true or false, dry = false, export = nil, line_range = nil,
    overrides = p.overrides or {},
    filters = p.filters or { file_types = {}, globs = {}, exclude = {} },
  }
end

--- Delete a saved preset. No-op (not an error) if it doesn't exist.
---@param name string
---@return nil
function M.delete(name)
  local presets = M.load()
  if presets[name] == nil then return end
  presets[name] = nil
  save(presets)
end

--- Sorted preset names, for <Tab> completion.
---@return string[]
function M.names()
  local names = {}
  for name in pairs(M.load()) do names[#names + 1] = name end
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
  local usercmd = require("lib.nvim.usercmd")
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
      old = "", new = "", scope = "", all = false, dry = false, export = nil,
      line_range = nil, overrides = {}, filters = { file_types = {}, globs = {}, exclude = {} },
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
    local req = M.as_request(name)
    if not req then
      notify.error("no such preset: '" .. name .. "'")
      return
    end
    run_fun(req)
  end, {
    nargs = 1,
    complete = function() return M.names() end,
    desc = "Run a saved preset: :ReplacePreset {name}",
  })
end

return M
