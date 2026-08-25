---@module 'replacer.bindings.keymaps'
---@brief The keymaps replacer.nvim sets, all of them buffer-local.
---@description
--- **replacer.nvim installs no global keymaps.** Everything below is
--- buffer-local to a window this plugin opened itself, so it can only ever
--- shadow a key *inside* that window.
---
--- Two surfaces, and only one of them lives here:
---
---   * The `:ReplaceTest` panel's close keys -- `<Esc>` and `q`. Fixed, not
---     configurable: a scratch panel with no other bindings has no key worth
---     arguing about, and both are what every float in this ecosystem uses.
---
---   * The picker keymaps (`config.keymaps`), set inside the fzf-lua /
---     telescope result window. Those stay in `replacer.pickers.*`: each engine
---     takes its mappings in its own shape, at the moment it builds the picker,
---     and a copy of them here could only ever be a second place to forget to
---     update. `config/DEFAULTS.lua` is where their defaults are documented.

local map = require("lib.nvim.map")

local M = {}

---Bind the `:ReplaceTest` panel's close keys.
---@param bufnr integer          The panel's scratch buffer
---@param close fun()            Closes the panel window
---@return nil
function M.attach_test_panel(bufnr, close)
  for _, lhs in ipairs({ "<Esc>", "q" }) do
    map("n", lhs, close, {
      buffer = bufnr,
      nowait = true,
      silent = true,
      desc = "[replacer.nvim] close the :ReplaceTest panel",
    })
  end
end

return M
