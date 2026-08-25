---@module 'replacer.bindings.usrcmds'
---@brief Every user command replacer.nvim registers, and who owns it.
---@description
--- The command *specs* stay in the feature modules -- `:ReplaceUndo` cannot be
--- described without checkpoint.lua's snapshot model, and a spec kept away from
--- the code it drives is a spec that drifts. What lives here is the answer to
--- "which commands does this plugin create, and where does each one come from",
--- which used to exist only as a hand-maintained `pcall(require, ...)` ladder
--- inside `plugin/replacer.lua`.
---
--- `:ReplaceDebug` is deliberately absent: `replacer.debug` registers it on
--- first use rather than at load, because it exists to instrument a session
--- that is already misbehaving.

local M = {}

---Which module registers which commands, in registration order.
---
---`needs_run` marks the modules whose `register()` takes the core `run`
---function -- they build a request and hand it to the same executor `:Replace`
---uses, rather than reimplementing the apply path.
---@type { module: string, commands: string[], needs_run: boolean }[]
M.REGISTRY = {
  { module = "replacer.command", commands = { "Replace", "Replacer" }, needs_run = true },
  { module = "replacer.surround", commands = { "Surround", "Wrap" }, needs_run = true },
  { module = "replacer.regex", commands = { "ReplaceEscape", "ReplaceTest" }, needs_run = false },
  { module = "replacer.root", commands = { "ReplaceRoot" }, needs_run = true },
  { module = "replacer.checkpoint", commands = { "ReplaceUndo" }, needs_run = false },
  { module = "replacer.history", commands = { "ReplaceHistory" }, needs_run = true },
  {
    module = "replacer.presets",
    commands = { "ReplacePreset", "ReplaceSavePreset" },
    needs_run = true,
  },
  { module = "replacer.batch", commands = { "ReplaceBatch" }, needs_run = true },
  { module = "replacer.fnames", commands = { "ReplaceFNames" }, needs_run = false },
}

---Register every command in `REGISTRY`.
---
---Each `register()` is pcall'd around its `require`, which is what the old
---ladder in `plugin/replacer.lua` did too: one feature module failing to load
---must not cost the user `:Replace` itself.
---@param run fun(request: table)  `replacer.run`
---@return string[] registered  Names of the commands that were created
function M.setup(run)
  local registered = {}

  for _, entry in ipairs(M.REGISTRY) do
    local ok, mod = pcall(require, entry.module)
    if ok and type(mod) == "table" and type(mod.register) == "function" then
      mod.register(entry.needs_run and run or nil)
      for _, name in ipairs(entry.commands) do
        registered[#registered + 1] = name
      end
    end
  end

  return registered
end

---Every command name this module can create, flattened -- for `:checkhealth`
---and the generated binding docs, neither of which should have to walk
---`REGISTRY` itself.
---@return string[]
function M.names()
  local out = {}
  for _, entry in ipairs(M.REGISTRY) do
    for _, name in ipairs(entry.commands) do
      out[#out + 1] = name
    end
  end
  return out
end

return M
