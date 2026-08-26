-- Headless smoke test for the :Surround convenience layer.
-- Run:  nvim -l TESTS/surround_smoke.lua
-- Covers delimiter resolution, the shared tokenizer/flag helpers, the real
-- :Surround user command, and an end-to-end wrap across buffer/dir scopes.

vim.opt.runtimepath:append(vim.fn.getcwd())

-- lib.nvim lives outside this repo, so `nvim -l TESTS/<suite>.lua` starts
-- without it on the path and every require of replacer.* dies on
-- "module 'lib.nvim.notify' not found". Resolve it first. Pattern A from
-- lib.nvim/templates/README.md (hard dependency: replacer.notify and
-- replacer.gitfiles require lib.nvim unconditionally, so nothing loads
-- without it) -- fail the whole suite rather than reporting phantom passes.
local this_file = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local add_lib_nvim = dofile((this_file:match("^(.*)/[^/]+$") or ".") .. "/resolve_lib_nvim.lua")
if not add_lib_nvim() then
  print("FAIL  cannot locate lib.nvim (a runtime dependency of replacer.nvim).")
  print("      Set $LIB_NVIM_PATH, or check it out next to this repo.")
  os.exit(1)
end

local replacer = require("replacer")
local command = require("replacer.command")
local surround = require("replacer.surround")

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
-- 1) Delimiter resolution (literal chars, aliases, bracket pairs)
--------------------------------------------------------------------------------
local function delim(tok)
  return surround.resolve_delim(tok)
end
do
  local l, r = delim("`")
  check("delim: backtick literal", l == "`" and r == "`")
  l, r = delim("b")
  check("delim: alias b -> backtick", l == "`" and r == "`")
  l, r = delim("q")
  check("delim: alias q -> dquote", l == '"' and r == '"')
  l, r = delim("s")
  check("delim: alias s -> squote", l == "'" and r == "'")
  l, r = delim("**")
  check("delim: ** symmetric", l == "**" and r == "**")
  l, r = delim("bold")
  check("delim: alias bold -> **", l == "**" and r == "**")
  l, r = delim("(")
  check("delim: bare ( -> ( )", l == "(" and r == ")")
  l, r = delim("paren")
  check("delim: alias paren -> ( )", l == "(" and r == ")")
  l, r = delim("@@")
  check("delim: unknown -> symmetric literal", l == "@@" and r == "@@")
end

--------------------------------------------------------------------------------
-- 2) Shared command helpers are exported and behave
--------------------------------------------------------------------------------
do
  local toks = command.tokenize('"foo bar" b cwd --all')
  check("tokenize: quote-aware split", #toks == 4 and toks[1] == "foo bar" and toks[2] == "b")

  local req = {
    old = "",
    new = "",
    scope = "",
    all = false,
    dry = false,
    export = nil,
    line_range = nil,
    overrides = {},
    filters = { file_types = {}, globs = {}, exclude = {} },
  }
  local pos = command.apply_tokens(toks, req)
  check(
    "apply_tokens: positionals + flag applied",
    pos and #pos == 3 and req.all == true,
    pos and #pos
  )

  local _, err = command.apply_tokens(command.tokenize("x --bogus"), {
    old = "",
    new = "",
    scope = "",
    all = false,
    dry = false,
    overrides = {},
    filters = { file_types = {}, globs = {}, exclude = {} },
  })
  check("apply_tokens: unknown flag -> error", err and err:match("unknown option"), err)
end

--------------------------------------------------------------------------------
-- 3) Real :Surround user command (bang = --all, alias delimiter, file scope)
--------------------------------------------------------------------------------
replacer.setup({ search_engine = "vimgrep", confirm_all = false, write_changes = true })
vim.g.__replacer_cmd_registered = nil
vim.cmd("source " .. vim.fn.getcwd() .. "/plugin/replacer.lua")
check("register: :Surround exists", vim.fn.exists(":Surround") == 2)
check("register: :Wrap exists", vim.fn.exists(":Wrap") == 2)

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
do
  local fa = tmp .. "/c.txt"
  local fh = assert(io.open(fa, "w"))
  fh:write("alpha beta alpha\nalpha\n")
  fh:close()
  vim.cmd(string.format("Surround! alpha b %s", fa))
  vim.wait(300)
  local c = assert(io.open(fa, "r")):read("*a")
  check("cmd: word -> `word` (3x)", select(2, c:gsub("`alpha`", "")) == 3, c)
  check("cmd: no bare word remains", not c:match("[^`]alpha[^`]") and not c:match("^alpha[^`]"), c)
end

--------------------------------------------------------------------------------
-- 4) Directory-scope wrap with a multi-char delimiter (markdown bold)
--------------------------------------------------------------------------------
do
  local fb = tmp .. "/b.md"
  local fh = assert(io.open(fb, "w"))
  fh:write("TODO and TODO\n")
  fh:close()
  vim.cmd(string.format("Surround! TODO bold %s", tmp))
  vim.wait(300)
  local c = assert(io.open(fb, "r")):read("*a")
  check("cmd: dir scope TODO -> **TODO** (2x)", select(2, c:gsub("%*%*TODO%*%*", "")) == 2, c)
end

--------------------------------------------------------------------------------
-- 5) skip_surrounded_filter: idempotency predicate (unit)
--------------------------------------------------------------------------------
do
  ---@diagnostic disable: missing-fields
  -- Partial RP_Match doubles: the filter only reads col0/old/line.
  local keep = surround.skip_surrounded_filter("**", "**")
  -- "**test**": "test" starts at byte col 2 (0-based); flanked by ** on both sides.
  check(
    "filter: already **wrapped** is skipped",
    keep({ col0 = 2, old = "test", line = "**test**" }) == false
  )
  -- Bare "test": not wrapped -> kept.
  check("filter: bare match is kept", keep({ col0 = 0, old = "test", line = "test" }) == true)
  -- "*test*": flanked by single * (not the ** delimiter) -> kept.
  check(
    "filter: partial/other delimiter is kept",
    keep({ col0 = 1, old = "test", line = "*test*" }) == true
  )

  local keepp = surround.skip_surrounded_filter("(", ")")
  check(
    "filter: already (wrapped) is skipped",
    keepp({ col0 = 1, old = "x", line = "(x)" }) == false
  )
  ---@diagnostic enable: missing-fields
end

--------------------------------------------------------------------------------
-- 5b) :Surround with no delimiter arg asks kit.input, not a raw vim.ui.input
--------------------------------------------------------------------------------
do
  local nodelim_dir = vim.fn.tempname()
  vim.fn.mkdir(nodelim_dir, "p")
  local fc = nodelim_dir .. "/d.txt"
  local fh = assert(io.open(fc, "w"))
  fh:write("gamma delta gamma\n")
  fh:close()

  local captured_title
  package.loaded["lib.nvim.ui.kit"] = {
    input = function(opts)
      captured_title = opts.title
      opts.on_submit("_")
    end,
  }

  vim.cmd("edit " .. vim.fn.fnameescape(fc))
  vim.cmd("Surround! gamma")
  vim.wait(300)

  check(
    "no-delim: kit.input was asked for the delimiter",
    captured_title ~= nil,
    tostring(captured_title)
  )
  local c = assert(io.open(fc, "r")):read("*a")
  check("no-delim: submitted '_' wraps the matches", select(2, c:gsub("_gamma_", "")) == 2, c)

  package.loaded["lib.nvim.ui.kit"] = nil
end

--------------------------------------------------------------------------------
-- 6) End-to-end idempotency: re-running :Surround does not stack layers,
--    and --nested forces another wrap.
--------------------------------------------------------------------------------
do
  local fc = tmp .. "/idem.md"
  local fh = assert(io.open(fc, "w"))
  fh:write("test\n")
  fh:close()

  vim.cmd(string.format("Surround! test bold %s", fc))
  vim.wait(300)
  local c1 = assert(io.open(fc, "r")):read("*a")
  check("idem: first wrap -> **test**", c1:match("^%*%*test%*%*") ~= nil, c1)

  -- Second run must be a no-op (default skips already-surrounded).
  vim.cmd(string.format("Surround! test bold %s", fc))
  vim.wait(300)
  local c2 = assert(io.open(fc, "r")):read("*a")
  check("idem: re-run leaves **test** unchanged", c2 == c1, c2)

  -- --nested opts in to another layer -> ****test****.
  vim.cmd(string.format("Surround! test bold %s --nested", fc))
  vim.wait(300)
  local c3 = assert(io.open(fc, "r")):read("*a")
  check("idem: --nested adds a layer -> ****test****", c3:match("^%*%*%*%*test%*%*%*%*") ~= nil, c3)
end

--------------------------------------------------------------------------------
print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
