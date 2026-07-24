---@module 'replacer.tscode'
--- Best-effort Tree-sitter-aware classification, backing the --code-only
--- flag (skip matches inside string/comment nodes).
---
--- Deliberately fails OPEN: whenever a filetype/parser/language can't be
--- resolved, or parsing errors out for any reason, a match is reported as
--- NOT inside a string/comment (i.e. kept). This is a convenience filter on
--- top of plain text search, never a hard correctness gate — a match that
--- Tree-sitter can't classify should never silently disappear.

local M = {}

--- Any node type containing "string" or "comment" is treated as such —
--- covers the common grammar spellings (string, string_literal,
--- interpreted_string_literal, comment, line_comment, block_comment, …)
--- without needing a per-language type table.
---@param t string|nil
---@return boolean
local function is_string_or_comment_type(t)
  if not t then return false end
  return t:find("string", 1, true) ~= nil or t:find("comment", 1, true) ~= nil
end

--- Best-effort: true when the byte position (row0, col0) in `content` (the
--- full text of `path`) falls inside a string/comment Tree-sitter node.
---@param path string
---@param content string
---@param row0 integer
---@param col0 integer
---@return boolean
function M.is_in_string_or_comment(path, content, row0, col0)
  local ok, result = pcall(function()
    local ft = vim.filetype.match({ filename = path })
    if not ft or ft == "" then return false end

    local lang = ft
    if vim.treesitter.language.get_lang then
      lang = vim.treesitter.language.get_lang(ft) or ft
    end

    local ok_parser, parser = pcall(vim.treesitter.get_string_parser, content, lang)
    if not ok_parser or not parser then return false end

    local trees = parser:parse()
    local tree = trees and trees[1]
    if not tree then return false end

    local node = tree:root():named_descendant_for_range(row0, col0, row0, col0)
    while node do
      if is_string_or_comment_type(node:type()) then return true end
      node = node:parent()
    end
    return false
  end)
  if not ok then return false end
  return result == true
end

return M
