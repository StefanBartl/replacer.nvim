---@module 'replacer.batch'
--- Batch replaces: run multiple {old -> new} pairs in one invocation,
--- imported from a file, the clipboard/unnamed register, or the quickfix
--- list.
---   :ReplaceBatch[!] {source} [scope] [--flags]
---
--- {source} is a file path, or one of: clipboard/+ (the "+" register),
--- unnamed/" (the unnamed register), qf/quickfix (quickfix list `text`
--- fields).
---
--- Pair format, auto-detected:
---   - line-oriented (default): one "old => new" per line; blank lines and
---     "#"-prefixed comments are ignored.
---   - JSON: a `[{"old": "...", "new": "..."}, ...]` array, used when the
---     (trimmed) content starts with "[".
---
--- Each pair is dispatched as its own full :Replace run (search + apply),
--- sequentially and non-interactively (the bang form / --all semantics) --
--- this reuses the exact same pipeline (dry-run, filters, checkpoints,
--- hooks, history, …) rather than reimplementing search-and-apply, so every
--- pair gets its own result notification exactly like a normal :Replace!
--- would produce.

local notify = require("replacer.util.notify")

local M = {}

--------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------

---@class RP_BatchPair
---@field old string
---@field new string

---@internal
--- Parse the line-oriented "old => new" format.
---@param content string
---@return RP_BatchPair[]|nil pairs, string|nil err
local function parse_lines(content)
  local out = {}
  local lnum = 0
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    lnum = lnum + 1
    local trimmed = vim.trim(line)
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      local old, new = trimmed:match("^(.-)%s=>%s(.*)$")
      if not old then
        return nil, string.format("batch line %d: expected 'old => new', got: %s", lnum, line)
      end
      out[#out + 1] = { old = old, new = new }
    end
  end
  return out, nil
end

---@internal
--- Parse a JSON array of {old, new}.
---@param content string
---@return RP_BatchPair[]|nil pairs, string|nil err
local function parse_json(content)
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    return nil, "batch: invalid JSON"
  end
  local out = {}
  for i, entry in ipairs(data) do
    if type(entry) ~= "table" or type(entry.old) ~= "string" or type(entry.new) ~= "string" then
      return nil, string.format("batch: JSON entry #%d missing string old/new", i)
    end
    out[#out + 1] = { old = entry.old, new = entry.new }
  end
  return out, nil
end

--- Parse batch content, auto-detecting JSON (leading "[") vs the line format.
---@param content string
---@return RP_BatchPair[]|nil pairs, string|nil err
function M.parse(content)
  local trimmed = vim.trim(content or "")
  if trimmed == "" then return nil, "batch: empty input" end
  if trimmed:sub(1, 1) == "[" then
    return parse_json(trimmed)
  end
  return parse_lines(content)
end

--------------------------------------------------------------------------------
-- Sources
--------------------------------------------------------------------------------

---@internal
--- Resolve {source} into raw text content.
---@param source string
---@return string|nil content, string|nil err
local function read_source(source)
  local lc = source:lower()
  if lc == "clipboard" or source == "+" then
    return vim.fn.getreg("+"), nil
  end
  if source == '"' or lc == "unnamed" then
    return vim.fn.getreg('"'), nil
  end
  if lc == "qf" or lc == "quickfix" then
    local qf = vim.fn.getqflist()
    local lines = {}
    for _, e in ipairs(qf) do lines[#lines + 1] = e.text end
    return table.concat(lines, "\n"), nil
  end
  if vim.fn.filereadable(source) == 1 then
    local ok, lines = pcall(vim.fn.readfile, source)
    if not ok then return nil, "batch: failed to read " .. source end
    return table.concat(lines, "\n"), nil
  end
  return nil, "batch: source not found — expected a file path, 'clipboard'/'+', " ..
    "'unnamed'/'\"', or 'qf'/'quickfix', got: " .. source
end

--------------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------------

--- Run every pair, sequentially dispatching one :Replace-equivalent request
--- per pair via `run_fun` (search + apply, or plan-only when req_template.dry
--- is set). Each pair's own result is reported by the normal apply pipeline.
---@param source string
---@param scope string
---@param req_template RP_Request     # carries dry/all/overrides/filters from the command line
---@param run_fun fun(request: RP_Request): nil
---@return nil
function M.run(source, scope, req_template, run_fun)
  local content, err = read_source(source)
  if not content then
    notify.error(err)
    return
  end

  local pairs_list, perr = M.parse(content)
  if not pairs_list then
    notify.error(perr)
    return
  end
  if #pairs_list == 0 then
    notify.info("batch: no pairs found")
    return
  end

  for _, pair in ipairs(pairs_list) do
    ---@type RP_Request
    local req = vim.deepcopy(req_template)
    req.old, req.new, req.scope = pair.old, pair.new, scope
    -- Batch is inherently non-interactive (a picker per pair makes no
    -- sense); dispatch() ignores `all` entirely on the --dry/plan path
    -- anyway, so this is a no-op when req.dry is set.
    req.all = true
    run_fun(req)
  end

  notify.info(string.format("batch: dispatched %d pair(s) from %s", #pairs_list, source))
end

--------------------------------------------------------------------------------
-- :ReplaceBatch
--------------------------------------------------------------------------------

local USAGE = "Usage: :ReplaceBatch[!] {source} [scope] [--flags]   " ..
  "(source: file path, clipboard/+, unnamed/\", or qf/quickfix)"

--- Register :ReplaceBatch.
---@param run_fun fun(request: RP_Request): nil
---@return nil
function M.register(run_fun)
  local usercmd = require("lib.nvim.usercmd")
  local command = require("replacer.command")

  usercmd.create("ReplaceBatch", function(opts)
    local raw = (type(opts.args) == "string") and opts.args or ""
    local tokens, unterminated = command.tokenize(raw)
    if unterminated then
      notify.error("ReplaceBatch: unterminated quote in argument list.\n" .. USAGE)
      return
    end

    ---@type RP_Request
    local req = {
      old = "", new = "", scope = "",
      all = opts.bang and true or false,
      dry = false, export = nil, line_range = nil,
      overrides = {}, filters = { file_types = {}, globs = {}, exclude = {} },
    }
    local positionals, err = command.apply_tokens(tokens, req)
    if not positionals then
      notify.error("ReplaceBatch: " .. err)
      return
    end
    if #positionals < 1 or #positionals > 2 then
      notify.error(USAGE)
      return
    end

    M.run(positionals[1], positionals[2] or "", req, run_fun)
  end, { nargs = "+", bang = true, desc = USAGE })
end

return M
