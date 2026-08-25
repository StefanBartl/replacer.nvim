
This can be handled the way shells do: either combine different quote types or use backslash escapes. The usual, simple rules:

* Use different quote types to avoid escapes:

  * `:Replace '"test"' ok %`  — the token is `"test"` including the double quotes
  * `:Replace "'test'" ok %`  — the token is `'test'` including the single quotes
* When you need quotes inside the same quote type, escape them with `\`:

  * `:Replace "\"test\"" ok %`  — the token is `"test"` (the double quotes are part of the token)
  * `:Replace '\''test'\'' ok %` — (an example with a nested escape)
* Unquoted is still possible:

  * `:Replace DAS DAS %`
  * `:Replace DAS "DAS with a space" %`

Advantages / recommendations:

* The simplest and most predictable variant for users is the shell-like one: allow `"` and `'` as delimiters and `\` as an escape inside quotes.
* In addition, a backslash can be accepted as an escape *outside* quotes too (e.g. `:\"test\"` or `\"test\"`), so that users can write `:Replace \"test\" ok %` if that is what they are used to.

Implementation proposal — a minimal parser patch:

* The existing `parse_args` already supports escapes **inside** quotes.
* It can be extended so that a backslash outside quotes also takes the next character (i.e. `\` as a general escape), so that `\"test\"` is recognised as one token even when the user does not start inside a quote.

Example: the adapted `parse_args` section (only the relevant addition). The comments are in English (as wanted) and the code is ready to drop into the existing parser.

```lua
-- Extend tokenizer so backslash escapes are honored even outside of quotes.
-- This allows inputs like: :Replace \"test\" ok %
-- Comments in English to follow project convention.

---@param s string
---@return string[] tokens
local function parse_args(s)
  local out = {} ---@type string[]
  if not s or s == "" then return out end

  local i, n = 1, #s
  while i <= n do
    -- skip whitespace
    while i <= n and s:sub(i,i):match("%s") do i = i + 1 end
    if i > n then break end

    local c = s:sub(i,i)
    if c == '"' or c == "'" then
      -- quoted token (existing behavior)
      local q = c
      i = i + 1
      local buf = {} ---@type string[]
      while i <= n do
        local ch = s:sub(i,i)
        if ch == "\\" and i < n then
          -- escape next char inside quotes
          buf[#buf+1] = s:sub(i+1,i+1)
          i = i + 2
        elseif ch == q then
          i = i + 1
          break
        else
          buf[#buf+1] = ch
          i = i + 1
        end
      end
      out[#out+1] = table.concat(buf)
    else
      -- unquoted token, but honor backslash escapes here as well
      local j = i
      local buf = {} ---@type string[]
      while j <= n and not s:sub(j,j):match("%s") do
        local ch = s:sub(j,j)
        if ch == "\\" and j < n then
          -- consume backslash and take next char verbatim
          buf[#buf+1] = s:sub(j+1,j+1)
          j = j + 2
        else
          buf[#buf+1] = ch
          j = j + 1
        end
      end
      out[#out+1] = table.concat(buf)
      i = j
    end
  end

  return out
end
```

Practical examples (what the parser yields as tokens):

* Input: `:Replace "test" "ok" %` → tokens: `{"test", "ok", "%"}`
* Input: `:Replace "\"test\"" ok %` → tokens: `{"\"test\"", "ok", "%"}` (the first token contains the double quotes as part of the text)
* Input: `:Replace '"test"' ok %` → tokens: `{"\"test\"", "ok", "%"}`
* Input: `:Replace \'test\' test %` → tokens: `{"'test'", "test", "%"}`

A further feature that could optionally be offered:

* A small "quote mode" flag (e.g. `--raw` or `--q`) meaning: "interpret the tokens exactly as entered, without Neovim/CLI interpolation" — helpful if further special cases need catching. Usually the combined strategy is enough, though: different quote types + backslash escapes + the parser extension above.

Recommendation:

* The parser extension above can be built in as described (a backslash outside quotes). Then document how users replace quotes: examples in the README (with `:Replace "\"from\"" "to"` and with `:Replace '"from"' 'to'`).
* Add tests that check `parse_args` directly with typical inputs (unit tests) in order to avoid regressions.
