---@module 'replacer.command'
--- Shell-like argument parser and user-command registration for :Replace.
---
--- Grammar:
---   :[range]Replace[!] {old} {new} [scope] [--flags...]
---
--- Positional tokens (quotes preserve spaces, backslash escapes work):
---   {old}    pattern to search (literal or regex per config/flags)
---   {new}    replacement text ("" deletes the match)
---   [scope]  %|buf (current buffer) · cwd|. (working dir) · <path> (file/dir)
---
--- Flags (may appear anywhere; a lone "--" stops flag parsing):
---   --literal | --no-literal | --regex     toggle literal vs regex search
---   --smart-case | --no-smart-case         toggle ripgrep smart-case
---   --hidden | --no-hidden                 include/exclude dotfiles
---   --ignore | --no-ignore                 respect/ignore .gitignore
---   --type=<ft>      (repeatable)          restrict to a filetype (ripgrep --type)
---   --glob=<pat>     (repeatable)          include glob pattern
---   --exclude=<pat>  (repeatable)          exclude path/glob pattern
---   --engine=<fzf|telescope>               override picker for this run
---   --context=<n>                          preview context lines
---   --dry                                  plan only; show stats, no writes
---   --export=<path>                        write diff (or .json) of the planned edits
---   --all                                  non-interactive: apply to every match
---
---   The bang form (:Replace!) is shorthand for --all.
---   A [range] (e.g. :'<,'>Replace) restricts matching to the selected lines of
---   the current buffer.
---
--- Exported:
---   M.register(run_fun)     register :Replace / :Replacer; run_fun(request)
---   M.resolve_scope(scope)  resolve a scope token -> roots, single_file
---   M.parse_request(raw, o) parse a raw arg string -> ok, request, err (testable)
local uv = vim.uv or vim.loop
local notify = require("replacer.util.notify")
local composer = require("lib.nvim.usercmd.composer")

local M = {}

--------------------------------------------------------------------------------
-- Tokenizer
--------------------------------------------------------------------------------

--- Split a raw argument string into tokens, honoring single/double quotes and
--- backslash escapes (inside and outside quotes).
--- The second return value is true when a quote was opened but never closed
--- (e.g. `:Replace "foo bar`) — callers that need a friendly diagnostic for
--- that case (parse_request) check it; plain tokenizer consumers (M.tokenize)
--- may ignore it, same as before this was added.
---@param s string|nil
---@return string[] tokens, boolean unterminated_quote
local function parse_args(s)
  if s == nil then return {}, false end
  if type(s) ~= "string" then
    if type(s) == "table" then
      s = table.concat(s, " ")
    else
      return {}, false
    end
  end
  if s == "" then return {}, false end

  local out = {} ---@type string[]
  local unterminated = false
  local i, n = 1, #s
  while i <= n do
    while i <= n and s:sub(i, i):match("%s") do i = i + 1 end
    if i > n then break end

    local c = s:sub(i, i)
    if c == '"' or c == "'" then
      local q = c
      i = i + 1
      local closed = false
      local buf = {} ---@type string[]
      while i <= n do
        local ch = s:sub(i, i)
        if ch == "\\" and i < n and s:sub(i + 1, i + 1):match([=[["'\%s]]=]) then
          -- escape only quotes/backslash/space; keep "\" before path chars (Windows)
          buf[#buf + 1] = s:sub(i + 1, i + 1)
          i = i + 2
        elseif ch == q then
          i = i + 1
          closed = true
          break
        else
          buf[#buf + 1] = ch
          i = i + 1
        end
      end
      if not closed then unterminated = true end
      out[#out + 1] = table.concat(buf)
    else
      local j = i
      local buf = {} ---@type string[]
      while j <= n and not s:sub(j, j):match("%s") do
        local ch = s:sub(j, j)
        if ch == "\\" and j < n and s:sub(j + 1, j + 1):match([=[["'\%s]]=]) then
          -- escape only quotes/backslash/space; keep "\" before path chars (Windows)
          buf[#buf + 1] = s:sub(j + 1, j + 1)
          j = j + 2
        else
          buf[#buf + 1] = ch
          j = j + 1
        end
      end
      out[#out + 1] = table.concat(buf)
      i = j
    end
  end

  return out, unterminated
end

--------------------------------------------------------------------------------
-- Flag specification
--------------------------------------------------------------------------------

-- Boolean flags: name -> function(req) applying the effect.
---@type table<string, fun(req: RP_Request)>
local BOOL_FLAGS = {
  ["dry"]           = function(r) r.dry = true end,
  ["all"]           = function(r) r.all = true end,
  ["literal"]       = function(r) r.overrides.literal = true end,
  ["no-literal"]    = function(r) r.overrides.literal = false end,
  ["regex"]         = function(r) r.overrides.literal = false end,
  ["smart-case"]    = function(r) r.overrides.smart_case = true end,
  ["no-smart-case"] = function(r) r.overrides.smart_case = false end,
  ["hidden"]        = function(r) r.overrides.hidden = true end,
  ["no-hidden"]     = function(r) r.overrides.hidden = false end,
  ["ignore"]        = function(r) r.overrides.git_ignore = true end,
  ["no-ignore"]     = function(r) r.overrides.git_ignore = false end,
}

-- Value flags: name -> true. Applied via apply_value_flag below.
---@type table<string, true>
local VALUE_FLAGS = {
  ["type"]    = true,
  ["glob"]    = true,
  ["exclude"] = true,
  ["engine"]  = true,
  ["context"] = true,
  ["export"]  = true,
}

--- Apply a value flag to the request; returns nil on success or an error string.
---@param req RP_Request
---@param key string
---@param val string
---@return string|nil err
local function apply_value_flag(req, key, val)
  if val == "" then
    return string.format("option '--%s' requires a value (e.g. --%s=...)", key, key)
  end
  if key == "type" then
    req.filters.file_types[#req.filters.file_types + 1] = val
  elseif key == "glob" then
    req.filters.globs[#req.filters.globs + 1] = val
  elseif key == "exclude" then
    req.filters.exclude[#req.filters.exclude + 1] = val
  elseif key == "engine" then
    local e = val:lower()
    if e ~= "fzf" and e ~= "telescope" then
      return string.format("invalid --engine '%s' (use fzf|telescope)", val)
    end
    req.overrides.engine = e
  elseif key == "context" then
    local n = tonumber(val)
    if not n or n < 0 or n ~= math.floor(n) then
      return string.format("invalid --context '%s' (expected a non-negative integer)", val)
    end
    req.overrides.preview_context = n
  elseif key == "export" then
    req.export = val
  end
  return nil
end

local USAGE = "Usage: :[range]Replace[!] {old} {new} [scope] [--flags]   (:h replacer-commands)"

--- Consume `tokens`, applying flags to `req` and collecting positionals.
--- Shared by :Replace and :Surround so both honor the exact same flag grammar.
---@param tokens string[]
---@param req RP_Request
---@return string[]|nil positionals   # nil on error
---@return string|nil err
local function apply_tokens(tokens, req)
  local positionals = {} ---@type string[]
  local flags_done = false

  local k = 1
  while k <= #tokens do
    local t = tokens[k]

    if not flags_done and t == "--" then
      flags_done = true
    elseif not flags_done and t:sub(1, 2) == "--" then
      local body = t:sub(3)
      local eq = body:find("=", 1, true)
      local key = eq and body:sub(1, eq - 1) or body
      local inline_val = eq and body:sub(eq + 1) or nil

      if BOOL_FLAGS[key] and not inline_val then
        BOOL_FLAGS[key](req)
      elseif BOOL_FLAGS[key] and inline_val then
        return nil, string.format(
          "Replace: option '--%s' does not take a value (got '%s'). Use '--%s' on its own.",
          key, t, key)
      elseif VALUE_FLAGS[key] then
        local val = inline_val
        if val == nil then
          -- support space-separated form: --type lua
          local nxt = tokens[k + 1]
          if nxt and not (not flags_done and nxt:sub(1, 2) == "--") then
            val = nxt
            k = k + 1
          else
            val = ""
          end
        end
        local err = apply_value_flag(req, key, val)
        if err then return nil, "Replace: " .. err end
      else
        return nil, string.format(
          "Replace: unknown option '%s'. See :h replacer-commands for valid flags.", t)
      end
    else
      positionals[#positionals + 1] = t
    end
    k = k + 1
  end

  return positionals
end

--------------------------------------------------------------------------------
-- Request parser
--------------------------------------------------------------------------------

--- Parse a raw argument string (plus command opts) into a structured request.
--- Pure and side-effect free → unit-testable.
---@param raw string|nil          # opts.args
---@param cmd_opts table|nil      # { bang?:boolean, range?:integer, line1?:integer, line2?:integer }
---@return boolean ok
---@return RP_Request|nil request
---@return string|nil err          # human-readable error when ok=false
function M.parse_request(raw, cmd_opts)
  cmd_opts = cmd_opts or {}
  local tokens, unterminated = parse_args(raw)
  if unterminated then
    return false, nil, string.format(
      "Replace: unterminated quote in argument list — every \" or ' must be closed " ..
      "(escape a literal quote with \\\" or \\', or use the other quote style around it).\n%s",
      USAGE)
  end

  ---@type RP_Request
  local req = {
    old = "",
    new = "",
    scope = "",
    all = cmd_opts.bang and true or false,
    dry = false,
    export = nil,
    line_range = nil,
    overrides = {},
    filters = { file_types = {}, globs = {}, exclude = {} },
  }

  local positionals, err = apply_tokens(tokens, req)
  if not positionals then
    return false, nil, err
  end

  -- Validate positional count with explicit, user-facing messages.
  if #positionals < 2 then
    local missing = (#positionals == 0) and "{old} and {new}" or "{new}"
    return false, nil, string.format(
      "Replace: missing argument(s) — expected %s.\n%s", missing, USAGE)
  end
  if #positionals > 3 then
    return false, nil, string.format(
      "Replace: too many arguments — got %d positional values; expected {old} {new} [scope]. " ..
      "Quote values that contain spaces, e.g. :Replace \"foo bar\" baz.\n%s",
      #positionals, USAGE)
  end

  req.old = positionals[1]
  req.new = positionals[2]
  req.scope = positionals[3] or ""

  -- Range (e.g. :'<,'>Replace) restricts to current-buffer line span.
  if type(cmd_opts.range) == "number" and cmd_opts.range > 0 then
    local l1 = cmd_opts.line1 or 1
    local l2 = cmd_opts.line2 or l1
    if l2 < l1 then l1, l2 = l2, l1 end
    req.line_range = { l1, l2 }
    if req.scope == "" then req.scope = "%" end
  end

  return true, req, nil
end

--------------------------------------------------------------------------------
-- Scope resolver
--------------------------------------------------------------------------------

---@param scope RP_Scope
---@return string[] roots, boolean single_file
local function resolve_scope(scope)
  scope = require("lib.nvim.cross.fs.expand_path")(scope or "")
  local scope_lc = scope:lower()

  if scope_lc == "%" or scope_lc == "buf" then
    local f = vim.api.nvim_buf_get_name(0)
    if f == "" then
      notify.error("current buffer has no file path")
      return {}, false
    end
    return { f }, true
  end

  -- If Neovim expanded '%' into the current file path before we saw it,
  -- detect that and treat as buffer scope.
  local cur = vim.api.nvim_buf_get_name(0)
  if cur ~= "" and scope ~= "" then
    local provided = vim.fn.fnamemodify(scope, ":p")
    local curp = vim.fn.fnamemodify(cur, ":p")
    if provided == curp then
      return { cur }, true
    end
  end

  if scope == "" or scope_lc == "cwd" or scope_lc == "." then
    local ok, cwd = pcall(function() return uv.cwd() end)
    if not ok or not cwd then
      notify.warn("failed to determine cwd")
      return {}, false
    end
    return { cwd }, false
  end

  local p = vim.fn.fnamemodify(scope, ":p")
  local is_dir = vim.fn.isdirectory(p) ~= 0
  return { p }, not is_dir
end

--------------------------------------------------------------------------------
-- Command registration
--------------------------------------------------------------------------------

-- Shared FlagSpec list for both :Replace and :Surround's composer routes
-- (mirrors BOOL_FLAGS/VALUE_FLAGS above) -- drives <Tab> completion only.
-- Dispatch never reads ctx.flags: see the `run` comment below for why.
---@type table[]
M.FLAGS = {
  { name = "dry", bool = true },
  { name = "all", bool = true },
  { name = "literal", bool = true },
  { name = "no-literal", bool = true },
  { name = "regex", bool = true },
  { name = "smart-case", bool = true },
  { name = "no-smart-case", bool = true },
  { name = "hidden", bool = true },
  { name = "no-hidden", bool = true },
  { name = "ignore", bool = true },
  { name = "no-ignore", bool = true },
  { name = "type", type = "STRING", repeatable = true },
  { name = "glob", type = "STRING", repeatable = true },
  { name = "exclude", type = "STRING", repeatable = true },
  { name = "engine", type = "STRING", enum = { "fzf", "telescope" } },
  { name = "context", type = "INT" },
  { name = "export", type = "STRING" },
}

--- Register :Replace and :Replacer user commands, built via
--- lib.nvim.usercmd.composer. The route declares `args`/`flags` purely to
--- drive <Tab> completion; dispatch bypasses composer's own bound
--- ctx.args/ctx.flags entirely and calls the ORIGINAL handler(opts) with
--- ctx.raw (composer's untouched nvim-callback opts table -- same .args
--- string, .bang, .range/.line1/.line2 shape as before this migration), so
--- parse_request/apply_tokens/BOOL_FLAGS/VALUE_FLAGS run byte-for-byte
--- unchanged. This is a `path = {}` root route: it matches with zero
--- literal subcommand tokens, reproducing the flat
--- `:Replace {old} {new} [scope] [--flags]` grammar verbatim.
---@param run_fun fun(request: RP_Request): nil
---@return nil
function M.register(run_fun)
  local function handler(opts)
    local raw = (type(opts.args) == "string") and opts.args or ""
    local ok, request, err = M.parse_request(raw, {
      bang  = opts.bang,
      range = opts.range,
      line1 = opts.line1,
      line2 = opts.line2,
    })
    if not ok or not request then
      -- Defer so the message shows as a clean notification instead of bubbling
      -- up as a raw "Vim:Replace:" command error.
      local msg = err or "Replace: invalid arguments"
      vim.schedule(function() notify.error(msg) end)
      return
    end
    run_fun(request)
  end

  local spec = {
    desc = "Interactive replace: :[range]Replace[!] {old} {new} [scope] [--flags]",
    bang = true,
    routes = {
      { path = {},
        args = {
          { name = "old", type = "STRING" },
          { name = "new", type = "STRING" },
          { name = "scope", type = "STRING", optional = true, values = { "%", "cwd", "." } },
        },
        flags = M.FLAGS,
        range = true,
        run = function(ctx) handler(ctx.raw) end },
    },
  }

  composer.verb("Replace", spec)
  composer.verb("Replacer", spec)
end

M.resolve_scope = resolve_scope
M.tokenize      = parse_args   -- quote/escape-aware tokenizer (shared with :Surround)
M.apply_tokens  = apply_tokens -- flag+positional splitter (shared with :Surround)

return M
