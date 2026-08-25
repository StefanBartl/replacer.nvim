---@module 'plugin.replacer'
--- Lazy-friendly plugin entry: everything it does lives in `replacer.bindings`.
---
--- Registration is here rather than in `replacer.setup()` on purpose: the
--- `:Replace*` commands are this plugin's entire interface, so they have to
--- exist whether or not the user ever calls `setup()` to configure anything.
---
--- Idempotent -- `plugin/*` is sourced again on a config reload, and composer
--- would otherwise re-register every verb.

if not vim.g.__replacer_cmd_registered then
  local ok, bindings = pcall(require, "replacer.bindings")
  if ok then
    bindings.setup()
    vim.g.__replacer_cmd_registered = true
  end
end
