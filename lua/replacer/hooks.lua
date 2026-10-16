---@module 'replacer.hooks'
--- Lua before/after callbacks around the apply pipeline, for running a
--- linter/formatter, invalidating a cache, etc. Two ways to register:
---   - config.hooks = { before_apply = fn|fn[], ... } via setup()
---   - require("replacer.hooks").on(event, fn) programmatically
--- Both fire for a given event; config hooks run first. A hook error is
--- caught and warned, never allowed to abort the apply. A hook may return
--- `false` to veto (skip) that file.
---
--- The registry itself (order, veto, error isolation) is `lib.nvim.hooks`;
--- this module only names the four events and routes errors to the notifier.

local notify = require("replacer.util.notify")

local M = {}

---@alias RP_HookEvent "before_apply"|"after_apply"|"before_write"|"after_write"

local EVENTS = { "before_apply", "after_apply", "before_write", "after_write" }

---@return Lib.Hooks.Registry
local function new_registry()
  return require("lib.nvim.hooks").new({
    events = EVENTS,
    -- every event keeps the answer it always had: `run` returns false when any hook returned false
    vetoable = EVENTS,
    on_error = function(event, err)
      notify.warn(string.format("hook '%s' errored: %s", event, tostring(err)))
    end,
  })
end

local registry = new_registry()

--- Register a hook programmatically (in addition to config.hooks).
---@param event RP_HookEvent
---@param fn fun(ctx: table): boolean|nil
---@return nil
function M.on(event, fn)
  local ok, err = pcall(registry.on, event, fn)
  if not ok then
    -- (the message stays the one this module always raised for an unknown event)
    if not vim.tbl_contains(EVENTS, event) then
      error("replacer.hooks: unknown event '" .. tostring(event) .. "'", 2)
    end
    error(err, 2)
  end
end

--- Remove every programmatically-registered hook (config.hooks is
--- untouched). Mainly for tests.
---@return nil
function M.clear()
  registry.clear()
end

--- Run every hook registered for `event` (config.hooks[event], then
--- M.on() registrations), guarded so a hook error never aborts the apply.
---@param event RP_HookEvent
---@param ctx table
---@param cfg RP_Config|nil
---@return boolean proceed  # false when any hook returned false
function M.run(event, ctx, cfg)
  local proceed = registry.run(event, ctx, cfg and cfg.hooks and cfg.hooks[event] or nil)
  return proceed
end

return M
