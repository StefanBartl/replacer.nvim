---@module 'replacer.util.notify'
---@brief Prefixed notify wrapper for replacer.nvim, backed by lib.nvim.notify.
---@description
--- Every module in this plugin used to call raw vim.notify(...) directly,
--- with inconsistent inline "[replacer] " prefixing (some call sites had it,
--- some didn't). This centralizes on lib.nvim.notify.create("[replacer]"),
--- so every message gets the same prefix and level dispatch.

return require("lib.nvim.notify").create("[replacer]")
