---@module 'replacer.bindings.autocmds'
---@brief The autocommands replacer.nvim creates, and the augroup they live in.
---@description
--- There is exactly one, and it is buffer-local: the live re-highlight of
--- `:ReplaceTest`'s pattern/sample panel. That is the whole autocmd surface --
--- replacer does its work when you ask it to, not on events.
---
--- It is here rather than inline in `replacer.regex` for the reason the whole
--- `bindings/` folder exists: "what does this plugin hook into" should be one
--- lookup, not a grep. `regex.lua` still owns the *highlighting*; this module
--- owns the wiring.

local autocmd = require("lib.nvim.autocmd")

local M = {}

---The augroup every replacer autocommand belongs to.
---
---Named even though the only member is buffer-local on a `bufhidden = "wipe"`
---scratch buffer -- and therefore cannot stack across reloads the way an
---ungrouped global autocmd would. A group costs nothing and makes the hook
---visible to `:autocmd` and to anyone auditing what the plugin installs.
M.GROUP = "ReplacerTestPanel"

---Re-highlight the `:ReplaceTest` panel whenever its two lines change.
---
---Buffer-local, so it dies with the panel; no teardown is needed and none is
---offered.
---@param bufnr integer            The test panel's scratch buffer
---@param on_change fun(bufnr: integer)  Re-highlight callback (`regex.highlight_test_buffer`)
---@return nil
function M.attach_test_panel(bufnr, on_change)
  autocmd.create({ "TextChanged", "TextChangedI" }, function()
    on_change(bufnr)
  end, {
    group = M.GROUP,
    buffer = bufnr,
    desc = "[replacer.nvim] :ReplaceTest — re-highlight the sample as the pattern is typed",
  })
end

return M
