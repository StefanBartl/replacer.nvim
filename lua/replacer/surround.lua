---@module 'replacer.surround'
--- Convenience layer over the replace engine: wrap every occurrence of a
--- pattern with a delimiter (backticks, quotes, markdown emphasis, brackets …).
---
--- `:Surround {pattern}` is exactly a literal `:Replace` where the replacement
--- is `<left><pattern><right>`, so it inherits the full pipeline for free:
--- scope resolution (%/cwd/./<path>), ripgrep matching, dry-run preview,
--- interactive picker, non-interactive --all, and confirmation prompts.
---
--- Grammar:
---   :[range]Surround[!] {pattern} [delim] [scope] [--flags...]
---
---   {pattern}  literal text to search for (regex is not supported here — the
---              replacement is a fixed string, so each spot must be identical)
---   [delim]    the wrapper: a literal char/string ( ` " ' * ** _ ), a named
---              alias (see ALIASES), or a bracket pair (( ) [ ] { } < >).
---              When omitted, you are prompted for it.
---   [scope]    %|buf · cwd|. · <file|dir>   (default: config.default_scope)
---
--- Flags are identical to :Replace (--all, --dry, --hidden, --type=, …), plus
--- one Surround-only flag:
---   --nested   also wrap matches that are ALREADY surrounded by this delimiter.
---              By default such matches are skipped, so re-running :Surround is
---              idempotent (`**test**` is left alone instead of becoming
---              `****test****`). Use --nested to force another layer.
--- The bang form (:Surround!) is shorthand for --all. Regex mode is force-disabled.
---
--- Examples:
---   :Surround word `            → `word`   in the current buffer
---   :Surround word b            → `word`   ("b" is an alias for backtick)
---   :Surround "foo bar" ** cwd  → **foo bar**  across the working directory
---   :Surround TODO ( .          → (TODO)  project-wide, all files
---   :Surround! name q %         → "name"  everywhere in the buffer, no picker
---   :Surround word ** --nested  → wrap even already-**bold** occurrences

local composer = require("lib.nvim.bindings.usercmd.composer")
local command = require("replacer.command")
local notify = require("replacer.util.notify")

local M = {}

--------------------------------------------------------------------------------
-- Delimiter resolution
--------------------------------------------------------------------------------

--- Named delimiters. A value is either a symmetric string (used on both sides)
--- or a { left, right } pair for asymmetric wrappers (brackets).
---@type table<string, string|string[]>
local ALIASES = {
  -- backtick
  b = "`",
  bt = "`",
  backtick = "`",
  tick = "`",
  code = "`",
  -- double quote
  q = '"',
  dq = '"',
  quote = '"',
  quotes = '"',
  -- single quote
  s = "'",
  sq = "'",
  single = "'",
  apos = "'",
  -- markdown emphasis
  star = "*",
  asterisk = "*",
  bold = "**",
  strong = "**",
  italic = "_",
  underscore = "_",
  us = "_",
  -- brackets / braces (asymmetric)
  paren = { "(", ")" },
  parens = { "(", ")" },
  round = { "(", ")" },
  bracket = { "[", "]" },
  brackets = { "[", "]" },
  square = { "[", "]" },
  brace = { "{", "}" },
  braces = { "{", "}" },
  curly = { "{", "}" },
  angle = { "<", ">" },
  angles = { "<", ">" },
}

--- Bare bracket openers → their matching close, so ":Surround x (" works.
---@type table<string, string>
local BRACKET_CLOSE = { ["("] = ")", ["["] = "]", ["{"] = "}", ["<"] = ">" }

--- Resolve a delimiter token into the left/right strings placed around a match.
---@param tok string
---@return string left, string right
local function resolve_delim(tok)
  local alias = ALIASES[tok:lower()]
  if type(alias) == "table" then
    return alias[1], alias[2]
  elseif type(alias) == "string" then
    return alias, alias
  end
  -- A lone opening bracket implies its matching close; otherwise symmetric.
  local close = BRACKET_CLOSE[tok]
  if close then
    return tok, close
  end
  return tok, tok
end

--------------------------------------------------------------------------------
-- Idempotency: skip already-surrounded matches
--------------------------------------------------------------------------------

--- Build a keep-predicate that drops matches already flanked by `left`/`right`.
--- A match at byte column `col0` on `line` is considered already surrounded when
--- the bytes immediately before it equal `left` AND those immediately after it
--- equal `right`. Such matches are removed so re-wrapping is idempotent
--- (`**test**` stays `**test**` instead of becoming `****test****`).
---@param left string
---@param right string
---@return fun(match: RP_Match): boolean
local function skip_surrounded_filter(left, right)
  local llen, rlen = #left, #right
  return function(m)
    local line = m.line or ""
    local s = m.col0 -- 0-based byte start of the match
    local mlen = #(m.old or "") -- matched text length (== pattern, literal)
    -- 1-based ranges: left occupies (s-llen+1 .. s); right occupies the bytes
    -- right after the match (s+mlen+1 .. s+mlen+rlen).
    local before = (s - llen >= 0) and line:sub(s - llen + 1, s) or ""
    local after = line:sub(s + mlen + 1, s + mlen + rlen)
    -- Keep only when NOT already wrapped by this exact delimiter.
    return not (before == left and after == right)
  end
end

---@internal
--- Keep-predicate for a single-line charwise range: without it, a range
--- restricts by LINE only (via req.line_range), so `:'<,'>Surround` would wrap
--- every match on the selected line, not just the ones inside the actual
--- selection. `col1`/`col2` are composer's ctx.range columns (1-based, from
--- the '<'/'> marks) — a match is kept only when its full span sits inside
--- that range.
---@param lnum integer
---@param col1 integer
---@param col2 integer
---@return fun(match: RP_Match): boolean
local function col_range_filter(lnum, col1, col2)
  if col2 < col1 then
    col1, col2 = col2, col1
  end
  return function(m)
    if m.lnum ~= lnum then
      return true -- a different line: req.line_range already excludes it
    end
    local mstart = m.col0 + 1
    local mend = m.col0 + #(m.old or "")
    return mstart >= col1 and mend <= col2
  end
end

---@internal
--- AND two match keep-predicates together.
---@param a fun(match: RP_Match): boolean
---@param b fun(match: RP_Match): boolean
---@return fun(match: RP_Match): boolean
local function and_filters(a, b)
  return function(m)
    return a(m) and b(m)
  end
end

--------------------------------------------------------------------------------
-- Request construction
--------------------------------------------------------------------------------

local USAGE = "Usage: :[range]Surround[!] {pattern} [delim] [scope] [--flags]   "
  .. "(delim aliases: b ` , q \", s ', star, bold, paren …)"

---@internal
--- Build the RP_Request for wrapping `pattern` with the resolved delimiter,
--- carrying over scope/flags and range. Search is forced to literal mode.
---@param pattern string
---@param delim string
---@param scope string
---@param req RP_Request        # already carries flags applied by apply_tokens
---@param line_range integer[]|nil
---@param nested boolean        # when true, also wrap already-surrounded matches
---@param col_filter (fun(match: RP_Match): boolean)|nil  # single-line charwise range narrowing, if any
---@return RP_Request
local function build_request(pattern, delim, scope, req, line_range, nested, col_filter)
  local left, right = resolve_delim(delim)
  req.old = pattern
  req.new = left .. pattern .. right
  req.scope = scope or ""
  req.line_range = line_range
  -- Regex would need per-match capture expansion, which the applier does not do;
  -- force literal so `new` is a valid fixed replacement for every spot.
  req.overrides.literal = true
  -- Idempotency: unless --nested was given, skip spots already wrapped by this
  -- delimiter so repeated :Surround runs don't stack extra layers.
  local skip_filter
  if not nested then
    skip_filter = skip_surrounded_filter(left, right)
    req.filter_empty_msg = string.format(
      "every match is already surrounded by %s…%s (use --nested to wrap again)",
      left,
      right
    )
  end
  if col_filter and skip_filter then
    req.filter = and_filters(col_filter, skip_filter)
  else
    req.filter = col_filter or skip_filter
  end
  return req
end

--------------------------------------------------------------------------------
-- Command handler
--------------------------------------------------------------------------------

---@internal
--- Parse args, resolve the delimiter (prompting when absent), then run.
---@param run_fun fun(request: RP_Request): nil
---@param opts table              # nvim user-command opts
---@param range Lib.UserCmd.Composer.RangeInfo|nil  # composer's ctx.range, for a charwise column narrowing
local function handle(run_fun, opts, range)
  local raw = (type(opts.args) == "string") and opts.args or ""
  local tokens, unterminated = command.tokenize(raw)
  if unterminated then
    vim.schedule(function()
      notify.error(
        "Surround: unterminated quote in argument list — every \" or ' must be closed "
          .. "(escape a literal quote with \\\" or \\', or use the other quote style around it).\n"
          .. USAGE
      )
    end)
    return
  end

  -- Pull the Surround-only --nested / --allow-nested flag out before handing the
  -- rest to the shared :Replace token parser (which would reject it as unknown).
  local nested = false
  do
    local kept = {}
    for _, t in ipairs(tokens) do
      local lc = t:lower()
      if lc == "--nested" or lc == "--allow-nested" then
        nested = true
      else
        kept[#kept + 1] = t
      end
    end
    tokens = kept
  end

  ---@type RP_Request
  local req = {
    old = "",
    new = "",
    scope = "",
    all = opts.bang and true or false,
    dry = false,
    export = nil,
    line_range = nil,
    overrides = {},
    filters = { file_types = {}, globs = {}, exclude = {} },
  }

  local positionals, err = command.apply_tokens(tokens, req)
  if not positionals then
    vim.schedule(function()
      notify.error(err or "replacer: could not parse the command arguments")
    end)
    return
  end

  if #positionals < 1 then
    vim.schedule(function()
      notify.error("Surround: missing {pattern}.\n" .. USAGE)
    end)
    return
  end
  if #positionals > 3 then
    vim.schedule(function()
      notify.error(
        string.format(
          "Surround: too many arguments — got %d; expected {pattern} [delim] [scope]. "
            .. 'Quote values with spaces, e.g. :Surround "foo bar" `.\n%s',
          #positionals,
          USAGE
        )
      )
    end)
    return
  end

  local pattern = positionals[1]
  local delim = positionals[2]
  local scope = positionals[3] or ""

  -- Range (e.g. :'<,'>Surround) restricts to the current buffer line span.
  local line_range
  local col_filter
  if type(opts.range) == "number" and opts.range > 0 then
    local l1, l2 = opts.line1 or 1, opts.line2 or (opts.line1 or 1)
    if l2 < l1 then
      l1, l2 = l2, l1
    end
    line_range = { l1, l2 }
    if scope == "" then
      scope = "%"
    end

    -- A single-line charwise selection carries real column bounds; anything
    -- else (linewise, blockwise, or a charwise span across several lines)
    -- keeps the pre-existing whole-line-span behavior — narrowing to columns
    -- only makes sense when there is exactly one line's worth of them.
    if range and range.mode == "v" and l1 == l2 and range.col1 and range.col2 then
      col_filter = col_range_filter(l1, range.col1, range.col2)
    end
  end

  local messages = require("replacer.messages")
  local cfg = require("replacer.config").get()

  local function finish(d)
    if not d or d == "" then
      messages.info(cfg, messages.fmt(cfg, "surround_cancelled"))
      return
    end
    run_fun(build_request(pattern, d, scope, req, line_range, nested, col_filter))
  end

  if delim == nil then
    -- Prompt asynchronously; :Surround word  → ask what to wrap with.
    require("lib.nvim.ui.kit").input({
      title = messages.fmt(cfg, "surround_prompt"),
      on_submit = function(input)
        finish(input and vim.trim(input) or nil)
      end,
      on_cancel = function()
        finish(nil)
      end,
    })
  else
    finish(delim)
  end
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

-- Delimiter aliases + Surround-only --nested/--allow-nested, for <Tab>
-- completion on the (unnamed, optional) `delim` positional slot.
local DELIM_VALUES = {
  "`",
  '"',
  "'",
  "*",
  "**",
  "_",
  "(",
  "[",
  "{",
  "<",
  "b",
  "q",
  "s",
  "star",
  "bold",
  "italic",
  "paren",
  "bracket",
  "brace",
  "angle",
}

local FLAGS = vim.deepcopy(command.FLAGS)
FLAGS[#FLAGS + 1] = { name = "nested", bool = true }
FLAGS[#FLAGS + 1] = { name = "allow-nested", bool = true }

--- Register :Surround (and :Wrap alias), built via lib.nvim.bindings.usercmd.composer.
--- Same design as :Replace/:Replacer in command.lua: the route's args/flags
--- exist only for <Tab> completion. Dispatch bypasses composer's own bound
--- ctx.args/ctx.flags and calls the ORIGINAL handle(run_fun, opts) with
--- ctx.raw, so tokenize/apply_tokens/the --nested pre-filter all run
--- unchanged.
---@param run_fun fun(request: RP_Request): nil
---@return nil
function M.register(run_fun)
  local spec = {
    desc = "Wrap every match of a pattern: :[range]Surround[!] {pattern} [delim] [scope] [--flags]",
    bang = true,
    routes = {
      {
        path = {},
        args = {
          { name = "pattern", type = "STRING" },
          { name = "delim", type = "STRING", optional = true, values = DELIM_VALUES },
          {
            name = "scope",
            type = "STRING",
            optional = true,
            values = { "%", "cwd", ".", "root" },
          },
        },
        flags = FLAGS,
        range = true,
        run = function(ctx)
          handle(run_fun, ctx.raw, ctx.range)
        end,
      },
    },
  }

  composer.verb("Surround", spec)
  composer.verb("Wrap", spec)
end

-- Exposed for tests.
M.resolve_delim = resolve_delim
M.skip_surrounded_filter = skip_surrounded_filter

return M
