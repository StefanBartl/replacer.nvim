---@module 'replacer.encoding'
--- BOM/CRLF/LF awareness for the raw (non-buffer) file-reading paths, so
--- their offsets/content line up with what a Neovim buffer shows for the
--- same file. Neovim itself strips a UTF-8 BOM and normalizes CRLF -> LF
--- when loading a buffer (tracking both via 'bomb'/'fileformat' instead of
--- leaving them in the line text), so the buffer-backed apply path already
--- gets this for free. Only the raw io.open readers (the native vimgrep
--- scanner, and export.lua's dry-run fallback read) need to replicate it
--- explicitly -- otherwise a stray trailing \r (matched by Lua's `%s`) can
--- leak into a captured match on CRLF files and cause a spurious
--- "skipped: content changed" when the real edit later runs against the
--- \r-free buffer line.

local M = {}

local UTF8_BOM = "\239\187\191"

--- Strip a leading UTF-8 BOM from `content`, if present.
---@param content string
---@return string content, boolean had_bom
function M.strip_bom(content)
  if content:sub(1, 3) == UTF8_BOM then
    return content:sub(4), true
  end
  return content, false
end

--- Strip a single trailing \r from `line` (CRLF -> LF normalization for a
--- line already split on \n by e.g. io's `:lines()`).
---@param line string
---@return string
function M.strip_cr(line)
  if line:sub(-1) == "\r" then return line:sub(1, -2) end
  return line
end

--- Detect the dominant line-ending style of `content` from its first
--- newline. Purely informational (:checkhealth, debugging) -- the actual
--- read paths always normalize to LF regardless of what this reports.
---@param content string
---@return "crlf"|"lf"|"cr"|"none"
function M.detect_eol(content)
  local nl = content:find("\n", 1, true)
  if not nl then
    return content:find("\r", 1, true) and "cr" or "none"
  end
  if nl > 1 and content:sub(nl - 1, nl - 1) == "\r" then return "crlf" end
  return "lf"
end

return M
