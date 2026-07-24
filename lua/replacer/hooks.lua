---@module 'replacer.hooks'
--- Lua before/after callbacks around the apply pipeline, for running a
--- linter/formatter, invalidating a cache, etc. Two ways to register:
---   - config.hooks = { before_apply = fn|fn[], ... } via setup()
---   - require("replacer.hooks").on(event, fn) programmatically
--- Both fire for a given event; config hooks run first. A hook error is
--- caught and warned, never allowed to abort the apply. A before_apply
--- hook may return `false` to veto (skip) that file.

local notify = require("replacer.util.notify")

local M = {}

---@alias RP_HookEvent "before_apply"|"after_apply"|"before_write"|"after_write"

---@type table<RP_HookEvent, (fun(ctx: table): boolean|nil)[]>
local registered = { before_apply = {}, after_apply = {}, before_write = {}, after_write = {} }

--- Register a hook programmatically (in addition to config.hooks).
---@param event RP_HookEvent
---@param fn fun(ctx: table): boolean|nil
---@return nil
function M.on(event, fn)
  if not registered[event] then
    error("replacer.hooks: unknown event '" .. tostring(event) .. "'")
  end
  registered[event][#registered[event] + 1] = fn
end

--- Remove every programmatically-registered hook (config.hooks is
--- untouched). Mainly for tests.
---@return nil
function M.clear()
  for event in pairs(registered) do registered[event] = {} end
end

--- Run every hook registered for `event` (config.hooks[event], then
--- M.on() registrations), guarded so a hook error never aborts the apply.
---@param event RP_HookEvent
---@param ctx table
---@param cfg RP_Config|nil
---@return boolean proceed  # false when any before_apply hook returned false
function M.run(event, ctx, cfg)
  local proceed = true

  local fns = {} ---@type (fun(ctx: table): boolean|nil)[]
  local from_cfg = cfg and cfg.hooks and cfg.hooks[event]
  if type(from_cfg) == "function" then
    fns[#fns + 1] = from_cfg
  elseif type(from_cfg) == "table" then
    vim.list_extend(fns, from_cfg)
  end
  vim.list_extend(fns, registered[event])

  for _, fn in ipairs(fns) do
    local ok, result = pcall(fn, ctx)
    if not ok then
      notify.warn(string.format("hook '%s' errored: %s", event, tostring(result)))
    elseif result == false then
      proceed = false
    end
  end

  return proceed
end

return M
