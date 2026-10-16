---@module 'replacer.casing'
--- Case-preserving replace: detect the case style of a matched token and
--- re-apply that same style to the replacement text, so a single :Replace
--- invocation correctly handles every casing of an identifier at once
--- (foo -> bar, Foo -> Bar, FOO -> BAR, fooBar -> bazQux, FooBar -> BazQux).
---
--- The detection and re-casing live in `lib.lua.strings` (`identifier_style` / `apply_style`);
--- this module keeps the names the rest of the plugin uses.

local strings = require("lib.lua.strings")

local M = {}

---@alias RP_CaseStyle "upper"|"lower"|"title"|"camel"|"pascal"

--- Detect the case style of `text`. Returns nil when there is nothing
--- case-bearing to detect (no letters at all).
---@param text string|nil
---@return RP_CaseStyle|nil
function M.detect(text)
  return strings.identifier_style(text)
end

--- Re-case `new_text` to match `style` (as detected by M.detect).
---@param new_text string|nil
---@param style RP_CaseStyle|nil
---@return string
function M.apply(new_text, style)
  return strings.apply_style(new_text, style)
end

return M
