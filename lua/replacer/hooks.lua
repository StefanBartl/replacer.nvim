---@module 'replacer.hooks'
--- Lua before/after callbacks around the apply pipeline, for running a
--- linter/formatter, invalidating a cache, etc. Two ways to register:
---   - config.hooks = { before_apply = fn|fn[], ... } via setup()
---   - require("replacer.hooks").on(event, fn) programmatically
--- Both fire for a given event; config hooks run first. A hook error is
--- caught and warned, never allowed to abort the apply. A hook may return
--- `false` to veto (skip) that file; only `before_apply` is a gate.
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
    -- only `before_apply` is a gate (apply.lua reads its answer; the other calls discard it)
    vetoable = { "before_apply" },
    on_error = function(event, err)
      notify.warn(string.format("hook '%s' errored: %s", event, tostring(err)))
    end,
  })
end

local registry = new_registry()

--- Register a hook programmatically (in addition to config.hooks).
--- Strict by design: an unknown `event` or a `fn` that is not a function raises here, at the call
--- site, and registers nothing. (A non-callable entry in `config.hooks` is lenient instead: it is
--- only reported as a warning when the hook runs.)
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
---@return boolean proceed  # false when any before_apply hook returned false (the other events cannot veto)
function M.run(event, ctx, cfg)
  local extra = cfg and cfg.hooks and cfg.hooks[event] or nil
  if type(extra) == "table" then
    -- (a list with nil holes, `{ cond and fn or nil, other }`, must keep what follows the hole:
    -- the registry walks with ipairs, the list is read up to its highest index)
    local dense = {}
    for i = 1, table.maxn(extra) do
      if extra[i] ~= nil then
        dense[#dense + 1] = extra[i]
      end
    end
    extra = dense
  end
  local proceed = registry.run(event, ctx, extra)
  return proceed
end

return M
