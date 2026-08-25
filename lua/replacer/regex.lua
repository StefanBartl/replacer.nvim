---@module 'replacer.regex'
--- Regex helpers: an escaping helper, backreference expansion (\0-\9) in
--- replacement text for regex-mode searches, and a small live pattern-test
--- float (:ReplaceTest).

local notify = require("replacer.util.notify")

local M = {}

--------------------------------------------------------------------------------
-- Escaping
--------------------------------------------------------------------------------

-- Vim regex "magic"-mode special characters that need escaping to be taken
-- literally inside a pattern.
local MAGIC_CHARS = [=[\/.*$^~[]]=]

--- Escape `text` so it can be embedded literally inside a Vim regex pattern.
---@param text string
---@return string
function M.escape(text)
  return vim.fn.escape(text or "", MAGIC_CHARS)
end

--------------------------------------------------------------------------------
-- Backreferences (\0-\9) in replacement text
--------------------------------------------------------------------------------

--- True when `text` contains an unescaped `\<digit>` backreference token.
---@param text string|nil
---@return boolean
function M.has_backrefs(text)
  return text ~= nil and text:find("\\%d") ~= nil
end

--- Expand `\0`-`\9` backreferences in `new_text` using the capture groups
--- Vim regex `pattern` produces against `line`. `\0` is the whole match;
--- `\1`-`\9` are `\(...\)` submatch groups. A reference beyond what the
--- pattern actually captured expands to "". Backend-agnostic: every match
--- (ripgrep or vimgrep) already carries its own full source line, so this
--- needs no cooperation from the collector.
---@param new_text string
---@param line string
---@param pattern string
---@return string
function M.expand_backrefs(new_text, line, pattern)
  if not M.has_backrefs(new_text) then
    return new_text
  end

  local ok, groups = pcall(vim.fn.matchlist, line, pattern)
  if not ok or type(groups) ~= "table" then
    return new_text
  end

  return (new_text:gsub("\\(%d)", function(d)
    return groups[tonumber(d) + 1] or ""
  end))
end

--------------------------------------------------------------------------------
-- :ReplaceEscape
--------------------------------------------------------------------------------

--- Escape `text`, echo it, and put it in the unnamed register for immediate
--- pasting into a :Replace/:Surround invocation.
---@param text string
function M.escape_and_report(text)
  local escaped = M.escape(text)
  pcall(vim.fn.setreg, '"', escaped)
  notify.info(string.format('escaped (also copied to the unnamed register ""): %s', escaped))
end

--------------------------------------------------------------------------------
-- :ReplaceTest — small live pattern-test float
--------------------------------------------------------------------------------

local TEST_NS = vim.api.nvim_create_namespace("replacer_regex_test")

---@internal
--- Highlight every occurrence of line 1 (pattern) inside line 2 (sample).
---@param buf integer
local function highlight_test_buffer(buf)
  vim.api.nvim_buf_clear_namespace(buf, TEST_NS, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 2, false)
  local pattern, sample = lines[1] or "", lines[2] or ""
  if pattern == "" or sample == "" then
    return
  end

  -- Invalid/incomplete pattern while typing just yields no highlights (pcall
  -- swallows the Vim regex error rather than spamming it on every keystroke).
  pcall(function()
    local pos = 0
    local guard = 0
    while true do
      guard = guard + 1
      if guard > 1000 then
        break
      end -- pathological pattern safety valve
      local mt = vim.fn.matchstrpos(sample, pattern, pos)
      local matched, s, e = mt[1], mt[2], mt[3]
      if s == -1 or not matched or matched == "" then
        break
      end
      vim.api.nvim_buf_set_extmark(buf, TEST_NS, 1, s, { end_col = e, hl_group = "ReplacerTarget" })
      pos = e
      if pos >= #sample then
        break
      end
    end
  end)
end

--- Open a small floating window with two editable lines (pattern / sample
--- text) and live-highlight every match as either line changes. Closes on
--- <Esc>/q. Only a buffer-local autocmd is used (auto-removed when the
--- scratch buffer wipes), so nothing leaks past the window's lifetime.
---@param pattern string|nil
---@param sample string|nil
function M.open_test_panel(pattern, sample)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    pattern or "",
    sample or "",
    "",
    "-- line 1: pattern (Vim regex) · line 2: sample text",
  })

  pcall(vim.api.nvim_set_hl, 0, "ReplacerTarget", { link = "Search" })

  local width = math.min(80, math.max(40, vim.o.columns - 10))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = 4,
    row = math.floor((vim.o.lines - 4) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " :ReplaceTest — pattern / sample ",
    title_pos = "center",
  })

  -- Both hooks live in `replacer.bindings` -- see that module's header for why
  -- the wiring is kept apart from the highlighting it drives.
  require("replacer.bindings.autocmds").attach_test_panel(buf, highlight_test_buffer)

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  require("replacer.bindings.keymaps").attach_test_panel(buf, close)

  vim.api.nvim_win_set_cursor(win, { 1, #(pattern or "") })
  highlight_test_buffer(buf)
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

--- Register :ReplaceEscape and :ReplaceTest.
---@return nil
function M.register()
  local usercmd = require("lib.nvim.usercmd")
  local tokenize = require("replacer.command").tokenize

  usercmd.create("ReplaceEscape", function(opts)
    local raw = (type(opts.args) == "string") and opts.args or ""
    if raw == "" then
      notify.error("Usage: :ReplaceEscape {text}")
      return
    end
    M.escape_and_report(raw)
  end, { nargs = "+", desc = "Escape text for use as a Vim regex pattern" })

  usercmd.create("ReplaceTest", function(opts)
    local raw = (type(opts.args) == "string") and opts.args or ""
    local toks = tokenize(raw)
    M.open_test_panel(toks[1], toks[2])
  end, {
    nargs = "*",
    desc = "Open a small live regex pattern-test float: :ReplaceTest [pattern] [sample]",
  })
end

return M
