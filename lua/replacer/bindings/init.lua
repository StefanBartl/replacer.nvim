---@module 'replacer.bindings'
---@brief One place that answers "what does replacer.nvim bind".
---@description
--- User commands, keymaps and autocommands, each in its own module:
---
---   * `usrcmds` -- the thirteen `:Replace*` / `:Surround` / `:Wrap` commands
---     registered at load, and which feature module owns each one.
---     (`:ReplaceDebug` is a fourteenth, registered lazily -- see that module.)
---   * `keymaps`  -- buffer-local only; the plugin sets no global keymap.
---   * `autocmds` -- one, buffer-local, for the `:ReplaceTest` panel.
---
--- `plugin/replacer.lua` calls `setup()` once per session. Registration is
--- deliberately not part of `replacer.setup()`: the commands are the plugin's
--- entire interface, so they must exist whether or not the user ever calls
--- `setup()` to configure anything.

local M = {}

---Register every binding. Idempotent via `plugin/replacer.lua`'s guard.
---@return string[] commands  The user commands that were created
function M.setup()
  return require("replacer.bindings.usrcmds").setup(require("replacer").run)
end

return M
