---@module 'replacer.casing'
--- Case-preserving replace: detect the case style of a matched token and
--- re-apply that same style to the replacement text, so a single :Replace
--- invocation correctly handles every casing of an identifier at once
--- (foo -> bar, Foo -> Bar, FOO -> BAR, fooBar -> bazQux, FooBar -> BazQux).
---
--- Pure, side-effect-free, and independent of the rest of the plugin so it
--- is trivially unit-testable.

local M = {}

--------------------------------------------------------------------------------
-- Detection
--------------------------------------------------------------------------------

---@alias RP_CaseStyle "upper"|"lower"|"title"|"camel"|"pascal"

---@internal
--- Split `text` into "words" on `_`, `-`, whitespace, and internal
--- lower->upper camelCase boundaries (so "fooBar" and "foo_bar" both yield
--- { "foo", "bar" }).
---@param text string
---@return string[]
local function split_words(text)
  local words = {} ---@type string[]
  for chunk in text:gmatch("[%a%d]+") do
    local start = 1
    for i = 2, #chunk do
      local prev, cur = chunk:sub(i - 1, i - 1), chunk:sub(i, i)
      if cur:match("%u") and prev:match("%l") then
        words[#words + 1] = chunk:sub(start, i - 1)
        start = i
      end
    end
    words[#words + 1] = chunk:sub(start)
  end
  return words
end

--- Detect the case style of `text`. Returns nil when there is nothing
--- case-bearing to detect (no letters at all).
---@param text string|nil
---@return RP_CaseStyle|nil
function M.detect(text)
  if not text or text == "" or not text:match("%a") then return nil end

  local has_upper = text:match("%u") ~= nil
  local has_lower = text:match("%l") ~= nil
  if has_upper and not has_lower then return "upper" end
  if has_lower and not has_upper then return "lower" end

  -- Mixed case: word-split (separators AND camel boundaries) to tell a
  -- single Capitalized word ("title", e.g. "Foo") apart from a genuine
  -- multi-word identifier ("camel"/"pascal", e.g. "fooBar"/"Foo_Bar").
  local words = split_words(text)
  if #words <= 1 then return "title" end
  if text:sub(1, 1):match("%u") then return "pascal" end
  return "camel"
end

--------------------------------------------------------------------------------
-- Application
--------------------------------------------------------------------------------

--- Re-case `new_text` to match `style` (as detected by M.detect).
---@param new_text string|nil
---@param style RP_CaseStyle|nil
---@return string
function M.apply(new_text, style)
  if not new_text or new_text == "" or not style then return new_text or "" end

  if style == "upper" then return new_text:upper() end
  if style == "lower" then return new_text:lower() end
  if style == "title" then
    return new_text:sub(1, 1):upper() .. new_text:sub(2):lower()
  end

  if style == "camel" or style == "pascal" then
    local words = split_words(new_text)
    if #words == 0 then return new_text end
    local out = {} ---@type string[]
    for i, w in ipairs(words) do
      local lw = w:lower()
      if i == 1 and style == "camel" then
        out[i] = lw
      else
        out[i] = lw:sub(1, 1):upper() .. lw:sub(2)
      end
    end
    return table.concat(out)
  end

  return new_text
end

return M
