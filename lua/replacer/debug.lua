---@module 'replacer.debug'
--- Debug utilities for troubleshooting replacer issues.
--- Usage: :ReplaceDebug {on|off|status|test}

local notify = require("replacer.util.notify")
local usercmd = require("lib.nvim.bindings.usercmd")

local M = {}

---@type boolean
local debug_enabled = false

--- Enable debug mode
function M.enable()
  debug_enabled = true
  -- Update config if plugin is loaded
  local ok, replacer = pcall(require, "replacer")
  if ok and replacer.options then
    replacer.options.ext_highlight_opts = replacer.options.ext_highlight_opts or {}
    replacer.options.ext_highlight_opts.debug = true
  end
  notify.info("Debug mode ENABLED")
end

--- Disable debug mode
function M.disable()
  debug_enabled = false
  local ok, replacer = pcall(require, "replacer")
  if ok and replacer.options then
    if replacer.options.ext_highlight_opts then
      replacer.options.ext_highlight_opts.debug = false
    end
  end
  notify.info("Debug mode DISABLED")
end

--- Get debug status
function M.status()
  local ok, replacer = pcall(require, "replacer")
  local cfg_debug = ok
      and replacer.options
      and replacer.options.ext_highlight_opts
      and replacer.options.ext_highlight_opts.debug
    or false

  notify.info(
    string.format(
      "Debug: %s (config: %s)",
      debug_enabled and "ON" or "OFF",
      cfg_debug and "ON" or "OFF"
    )
  )
  return debug_enabled
end

--- Run test suite
function M.test()
  notify.info("Running test suite...")
  local ok, test = pcall(require, "test.utf8_offsets")
  if not ok then
    notify.error("Test suite not found")
    return
  end

  vim.schedule(function()
    test.run_all()
  end)
end

--- Inspect current buffer for debugging
function M.inspect_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local info = {
    bufnr = bufnr,
    path = path,
    line_count = #lines,
    modified = vim.bo[bufnr].modified,
    filetype = vim.bo[bufnr].filetype,
    encoding = vim.bo[bufnr].fileencoding or "utf-8",
  }

  print("\n=== Buffer Inspection ===")
  print(vim.inspect(info))

  -- Show first few lines with byte offsets
  print("\n=== First 5 lines (with byte lengths) ===")
  for i = 1, math.min(5, #lines) do
    local line = lines[i]
    print(
      string.format("Line %d: len=%d bytes, %d chars: '%s'", i, #line, vim.fn.strchars(line), line)
    )
  end
  print("")
end

--- Analyze specific line for match issues
---@param lnum integer 1-based line number
---@param pattern string Pattern to find
function M.analyze_line(lnum, pattern)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)
  if not lines or #lines == 0 then
    notify.error("Line not found")
    return
  end

  local line = lines[1]
  print(string.format("\n=== Analyzing line %d ===", lnum))
  print(string.format("Pattern: '%s'", pattern))
  print(string.format("Line: '%s'", line))
  print(string.format("Byte length: %d", #line))
  print(string.format("Char length: %d", vim.fn.strchars(line)))

  -- Find all occurrences
  local pos = 1
  local count = 0
  print("\nOccurrences:")
  while true do
    local s, e = line:find(pattern, pos, true)
    if not s then
      break
    end
    count = count + 1

    local matched = line:sub(s, e)
    print(string.format(
      "  #%d: bytes [%d:%d] chars [%d:%d] text='%s'",
      count,
      s - 1,
      e - 1, -- 0-based byte offsets
      vim.str_utfindex(line, s - 1) or -1,
      vim.str_utfindex(line, e) or -1,
      matched
    ))

    pos = e + 1
    if pos > #line then
      break
    end
  end

  if count == 0 then
    print("  No occurrences found")
  end
  print("")
end

--- Register debug command
function M.register_command()
  usercmd.create("ReplaceDebug", function(opts)
    local arg = opts.args or ""
    local cmd = arg:lower()

    if cmd == "on" or cmd == "enable" then
      M.enable()
    elseif cmd == "off" or cmd == "disable" then
      M.disable()
    elseif cmd == "status" then
      M.status()
    elseif cmd == "test" then
      M.test()
    elseif cmd == "inspect" then
      M.inspect_buffer()
    elseif cmd:match("^analyze%s+") then
      local lnum, pattern = cmd:match("^analyze%s+(%d+)%s+(.+)$")
      local _lnum = tonumber(lnum)
      if _lnum and pattern then
        M.analyze_line(_lnum, pattern)
      else
        notify.error("Usage: :ReplaceDebug analyze <line> <pattern>")
      end
    else
      notify.info("Usage: :ReplaceDebug {on|off|status|test|inspect|analyze <line> <pattern>}")
    end
  end, {
    nargs = "*",
    complete = function()
      return { "on", "off", "status", "test", "inspect", "analyze" }
    end,
    desc = "Replacer debug utilities",
  })
end

return M
