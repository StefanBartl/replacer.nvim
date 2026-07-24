-- Headless smoke test for the replacer feature set.
-- Run:  nvim -l tests/feature_smoke.lua
-- Exercises engine-agnostic paths (no fzf-lua/telescope required):
--   request parsing, error messages, range, native (vimgrep) search,
--   multi-occurrence-per-line, pure edit computation, dry-run, export, real apply.

vim.opt.runtimepath:append(vim.fn.getcwd())

local ok_mod, replacer = pcall(require, "replacer")
assert(ok_mod, "failed to require replacer: " .. tostring(replacer))
local command = require("replacer.command")
local rg = require("replacer.rg")
local apply = require("replacer.apply")
local export = require("replacer.export")
local casing = require("replacer.casing")
local regex = require("replacer.regex")
local encoding = require("replacer.encoding")

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    print("PASS  " .. name)
  else
    fail = fail + 1
    print("FAIL  " .. name .. (extra and ("  -> " .. tostring(extra)) or ""))
  end
end

--------------------------------------------------------------------------------
-- 1) Request parsing & error messages
--------------------------------------------------------------------------------
do
  local ok, req = command.parse_request("foo bar")
  check("parse: basic positional", ok and req.old == "foo" and req.new == "bar" and req.scope == "")

  local ok2, _, err2 = command.parse_request("foo")
  check("parse: missing arg -> error", (not ok2) and err2:match("missing"), err2)

  local ok3, _, err3 = command.parse_request("a b c d")
  check("parse: too many -> error", (not ok3) and err3:match("too many"), err3)

  local ok4, _, err4 = command.parse_request("foo bar --bogus")
  check("parse: unknown flag -> error", (not ok4) and err4:match("unknown option"), err4)

  local ok5, req5 = command.parse_request(
    'foo bar % --regex --type=lua --glob=*.x --exclude=node --dry --export=plan.json')
  check("parse: flags collected", ok5
    and req5.overrides.literal == false
    and req5.dry == true
    and req5.export == "plan.json"
    and req5.filters.file_types[1] == "lua"
    and req5.filters.globs[1] == "*.x"
    and req5.filters.exclude[1] == "node",
    req5 and vim.inspect(req5.filters))

  local ok6, req6 = command.parse_request("foo bar --type lua")
  check("parse: space-separated value flag", ok6 and req6.filters.file_types[1] == "lua")

  local ok7, req7 = command.parse_request("foo bar", { range = 2, line1 = 5, line2 = 2 })
  check("parse: range normalizes + forces buffer scope",
    ok7 and req7.line_range[1] == 2 and req7.line_range[2] == 5 and req7.scope == "%")

  local ok8, req8 = command.parse_request("foo bar baz", { bang = true })
  check("parse: bang -> all", ok8 and req8.all == true and req8.scope == "baz")

  local ok9, _, err9 = command.parse_request('"foo bar')
  check("parse: unterminated quote -> specific error", (not ok9) and err9:match("unterminated quote"), err9)

  local ok10, _, err10 = command.parse_request("foo bar --dry=1")
  check("parse: bool flag with value -> specific error",
    (not ok10) and err10:match("does not take a value"), err10)
end

--------------------------------------------------------------------------------
-- 2) Native (vimgrep) search + multiple occurrences per line
--------------------------------------------------------------------------------
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local file_a = tmp .. "/a.txt"
do
  local fh = assert(io.open(file_a, "w"))
  fh:write("foo and foo and foo\nbar foo baz\nno match here\n")
  fh:close()
end

local cfg = { literal = true, search_engine = "vimgrep", hidden = true,
  file_types = {}, globs = {}, exclude = {} }
do
  local items = rg.collect("foo", { tmp }, cfg)
  check("search: 4 occurrences (3 on line1 + 1 on line2)", #items == 4, #items)
  local line1 = 0
  for _, it in ipairs(items) do if it.lnum == 1 then line1 = line1 + 1 end end
  check("search: line 1 yields 3 separate entries", line1 == 3, line1)
end

--------------------------------------------------------------------------------
-- 2b) word_boundary: only whole-word matches are kept
--------------------------------------------------------------------------------
do
  local file_b = tmp .. "/b.txt"
  local fh = assert(io.open(file_b, "w"))
  fh:write("foo foobar barfoo xfoox foo.bar\n")
  fh:close()

  local wcfg = { literal = true, search_engine = "vimgrep", hidden = true, word_boundary = true,
    file_types = {}, globs = {}, exclude = {} }
  local witems = rg.collect("foo", { file_b }, wcfg)
  check("word_boundary: only whole-word 'foo' occurrences kept", #witems == 2, #witems)

  local plain_items = rg.collect("foo", { file_b }, {
    literal = true, search_engine = "vimgrep", hidden = true,
    file_types = {}, globs = {}, exclude = {} })
  check("word_boundary: off by default finds every substring occurrence", #plain_items == 5, #plain_items)
end

--------------------------------------------------------------------------------
-- 2c) code_only (Tree-sitter, best-effort): fails open with no parser available
--------------------------------------------------------------------------------
do
  local tscode = require("replacer.tscode")
  local is_hit = tscode.is_in_string_or_comment("nonexistent.zzzUnknownExt", "foo", 0, 0)
  check("tscode: unresolvable filetype -> fails open (false)", is_hit == false)
end

--------------------------------------------------------------------------------
-- 2d) safe_mode: oversized/binary files are excluded from vimgrep scanning
--------------------------------------------------------------------------------
do
  local file_big = tmp .. "/big.txt"
  do
    local fh = assert(io.open(file_big, "w"))
    fh:write(string.rep("foo ", 100))
    fh:close()
  end
  local file_bin = tmp .. "/bin.dat"
  do
    local fh = assert(io.open(file_bin, "wb"))
    fh:write("foo\0bar")
    fh:close()
  end

  local safe_items = rg.collect("foo", { file_big, file_bin }, {
    literal = true, search_engine = "vimgrep", hidden = true, safe_mode = true,
    max_file_size = 50, skip_binary = true, file_types = {}, globs = {}, exclude = {} })
  check("safe_mode: oversized + binary files excluded", #safe_items == 0, #safe_items)

  local unsafe_items = rg.collect("foo", { file_big, file_bin }, {
    literal = true, search_engine = "vimgrep", hidden = true, safe_mode = false,
    file_types = {}, globs = {}, exclude = {} })
  check("safe_mode: off by default finds matches in both files", #unsafe_items > 0, #unsafe_items)
end

--------------------------------------------------------------------------------
-- 2e) encoding: BOM/CRLF-aware raw reads (vimgrep backend + export)
--------------------------------------------------------------------------------
do
  check("encoding: strip_bom removes leading BOM", encoding.strip_bom("\239\187\191foo") == "foo")
  check("encoding: strip_bom no-op without BOM", encoding.strip_bom("foo") == "foo")
  check("encoding: strip_cr removes trailing CR", encoding.strip_cr("foo\r") == "foo")
  check("encoding: strip_cr no-op without CR", encoding.strip_cr("foo") == "foo")
  check("encoding: detect_eol crlf", encoding.detect_eol("a\r\nb") == "crlf")
  check("encoding: detect_eol lf", encoding.detect_eol("a\nb") == "lf")

  local file_crlf = tmp .. "/crlf.txt"
  do
    local fh = assert(io.open(file_crlf, "wb"))
    fh:write("\239\187\191foo bar\r\nfoo baz\r\n")
    fh:close()
  end
  local crlf_items = rg.collect("foo", { file_crlf }, {
    literal = true, search_engine = "vimgrep", hidden = true,
    file_types = {}, globs = {}, exclude = {} })
  check("encoding: BOM stripped -> match on line 1 starts at col0 0",
    crlf_items[1] and crlf_items[1].col0 == 0, crlf_items[1] and crlf_items[1].col0)
  local has_cr = false
  for _, it in ipairs(crlf_items) do
    if it.line:find("\r", 1, true) then has_cr = true end
  end
  check("encoding: no stray \\r left in collected line text", not has_cr)
end

--------------------------------------------------------------------------------
-- 3) Pure edit computation
--------------------------------------------------------------------------------
do
  local items = rg.collect("foo", { file_a }, cfg)
  local by = {}
  for _, it in ipairs(items) do by[#by + 1] = it end
  local new_lines, spots, skipped = apply.compute_file_edits(
    { "foo and foo and foo", "bar foo baz", "no match here" }, by, "X")
  check("compute: spots == 4", spots == 4, spots)
  check("compute: no skips", skipped == 0, skipped)
  check("compute: line1 rewritten", new_lines[1] == "X and X and X", new_lines[1])
  check("compute: line2 rewritten", new_lines[2] == "bar X baz", new_lines[2])
end

--------------------------------------------------------------------------------
-- 3b) preserve_whitespace: replacement is sandwiched in the match's own ws
--------------------------------------------------------------------------------
do
  ---@diagnostic disable: missing-fields
  local matches = { { id = 1, path = "x", lnum = 1, col0 = 3, old = "  foo  ", line = "___  foo  ___" } }
  ---@diagnostic enable: missing-fields
  local new_lines, spots = apply.compute_file_edits(
    { "___  foo  ___" }, matches, "bar", { preserve_whitespace = true })
  check("preserve_whitespace: sandwiches replacement in original ws",
    spots == 1 and new_lines[1] == "___  bar  ___", new_lines[1])

  local new_lines2 = apply.compute_file_edits({ "___  foo  ___" }, matches, "bar", nil)
  check("preserve_whitespace: off by default (cfg=nil) -> plain replace",
    new_lines2[1] == "___bar___", new_lines2[1])
end

--------------------------------------------------------------------------------
-- 3c) case_preserve: casing.lua detection + application, and apply.lua wiring
--------------------------------------------------------------------------------
do
  check("casing: detect lower", casing.detect("foo") == "lower")
  check("casing: detect upper", casing.detect("FOO") == "upper")
  check("casing: detect title", casing.detect("Foo") == "title")
  check("casing: detect camel", casing.detect("fooBar") == "camel")
  check("casing: detect pascal", casing.detect("FooBar") == "pascal")
  check("casing: detect nil for non-letters", casing.detect("123") == nil)

  check("casing: apply lower", casing.apply("BAZ", "lower") == "baz")
  check("casing: apply upper", casing.apply("baz", "upper") == "BAZ")
  check("casing: apply title", casing.apply("baz qux", "title") == "Baz qux")
  check("casing: apply camel", casing.apply("baz_qux", "camel") == "bazQux")
  check("casing: apply pascal", casing.apply("baz_qux", "pascal") == "BazQux")

  ---@diagnostic disable: missing-fields
  local m_lower = { id = 1, path = "x", lnum = 1, col0 = 0, old = "foo", line = "foo foo" }
  local m_upper = { id = 2, path = "x", lnum = 1, col0 = 4, old = "FOO", line = "foo FOO" }
  ---@diagnostic enable: missing-fields
  local nl = apply.compute_file_edits({ "foo FOO" }, { m_lower }, "bar", { case_preserve = true })
  check("case_preserve: lower match -> lower replacement", nl[1] == "bar FOO", nl[1])
  local nl2 = apply.compute_file_edits({ "foo FOO" }, { m_upper }, "bar", { case_preserve = true })
  check("case_preserve: upper match -> upper replacement", nl2[1] == "foo BAR", nl2[1])
end

--------------------------------------------------------------------------------
-- 3d) regex helpers: escape + backreference expansion
--------------------------------------------------------------------------------
do
  local escaped = regex.escape("a.b*c[d]")
  check("regex: escape special chars", escaped == "a\\.b\\*c\\[d\\]", escaped)
  check("regex: has_backrefs true", regex.has_backrefs("\\1-\\2") == true)
  check("regex: has_backrefs false", regex.has_backrefs("plain") == false)

  local capture_pattern = "\\(\\w\\+\\)=\\(\\w\\+\\)"
  local expanded = regex.expand_backrefs("\\2_\\1", "foo=bar", capture_pattern)
  check("regex: backrefs expand from vim regex capture groups", expanded == "bar_foo", expanded)

  local unchanged = regex.expand_backrefs("plain", "foo=bar", capture_pattern)
  check("regex: no backrefs -> untouched fast path", unchanged == "plain")

  ---@diagnostic disable: missing-fields
  local m = { id = 1, path = "x", lnum = 1, col0 = 0, old = "foo=bar", line = "foo=bar" }
  ---@diagnostic enable: missing-fields
  local nl = apply.compute_file_edits(
    { "foo=bar" }, { m }, "\\2_\\1", { literal = false }, capture_pattern)
  check("regex: backrefs wired through compute_file_edits", nl[1] == "bar_foo", nl[1])
end

--------------------------------------------------------------------------------
-- 4) Dry-run plan + patch + JSON export
--------------------------------------------------------------------------------
do
  local items = rg.collect("foo", { file_a }, cfg)
  local results, totals = export.build_results(items, "X")
  check("plan: totals.spots == 4", totals.spots == 4, totals.spots)
  check("plan: totals.files == 1", totals.files == 1, totals.files)

  local patch = export.build_patch(results)
  check("patch: has unified headers", patch:match("%-%-%- a/") and patch:match("%+%+%+ b/"), patch)
  check("patch: contains an added line", patch:match("\n%+"), patch)

  local json = export.build_json(results, "X")
  local ok, decoded = pcall(vim.json.decode, json)
  check("json: decodes", ok and decoded.total_spots == 4, ok and decoded.total_spots)

  local jpath = tmp .. "/plan.json"
  local okw = export.write_export(jpath, results, "X")
  check("export: json file written", okw and vim.fn.filereadable(jpath) == 1)

  local ppath = tmp .. "/plan.patch"
  local okp = export.write_export(ppath, results, "X")
  check("export: patch file written", okp and vim.fn.filereadable(ppath) == 1)
end

--------------------------------------------------------------------------------
-- 5) Real apply via M.run (non-interactive ALL), files actually changed
--------------------------------------------------------------------------------
do
  replacer.setup({ search_engine = "vimgrep", confirm_all = false, write_changes = true })
  local request = {
    old = "foo", new = "XXX", scope = file_a, all = true, dry = false, export = nil,
    line_range = nil, overrides = {}, filters = { file_types = {}, globs = {}, exclude = {} },
  }
  replacer.run(request)

  -- read file back
  local fh = assert(io.open(file_a, "r"))
  local content = fh:read("*a"); fh:close()
  check("apply: all 'foo' replaced with 'XXX'", not content:match("foo") and content:match("XXX"), content)
end

--------------------------------------------------------------------------------
-- 6) Quickfix/loclist export
--------------------------------------------------------------------------------
do
  local file_qf = tmp .. "/qf.txt"
  do
    local fh = assert(io.open(file_qf, "w"))
    fh:write("foo one\nfoo two\n")
    fh:close()
  end

  local items = rg.collect("foo", { file_qf }, cfg)
  local entries = export.to_qf_entries(items)
  check("qf: entry count matches items", #entries == #items, #entries)
  check("qf: entry has filename/lnum/col/text", entries[1].filename == file_qf
    and type(entries[1].lnum) == "number" and type(entries[1].col) == "number"
    and type(entries[1].text) == "string")

  vim.fn.setqflist({}, "r")
  replacer.setup({ search_engine = "vimgrep", confirm_all = false, write_changes = true })
  local request = {
    old = "foo", new = "XXX", scope = file_qf, all = false, dry = false, export = nil,
    to_quickfix = true, line_range = nil, overrides = {},
    filters = { file_types = {}, globs = {}, exclude = {} },
  }
  replacer.run(request)
  vim.wait(200)
  local qf = vim.fn.getqflist()
  check("qf: :Replace --to-quickfix populates the quickfix list", #qf > 0, #qf)

  local fh2 = assert(io.open(file_qf, "r"))
  local content_after_qf = fh2:read("*a"); fh2:close()
  check("qf: --to-quickfix never writes", content_after_qf:match("foo") ~= nil, content_after_qf)
end

--------------------------------------------------------------------------------
print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then vim.cmd("cquit 1") end
