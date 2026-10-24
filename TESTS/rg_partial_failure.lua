-- Headless test: ripgrep exit 2 caused solely by unreadable paths (e.g. broken
-- symlinks) must not abort the search; real errors (bad regex) still must.
-- Run:  nvim -l TESTS/rg_partial_failure.lua

vim.opt.runtimepath:append(vim.fn.getcwd())

local this_file = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local dir = this_file:match("^(.*)/[^/]+$") or "."
if not dofile(dir .. "/resolve_lib_nvim.lua")() then
  print("FAIL  cannot locate lib.nvim (a runtime dependency of replacer.nvim).")
  os.exit(1)
end
if not dofile(dir .. "/resolve_ui_nvim.lua")() then
  print("FAIL  cannot locate ui.nvim (a runtime dependency of replacer.nvim).")
  os.exit(1)
end

local rg = require("replacer.rg")

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

local cfg = {
  literal = true,
  search_engine = "ripgrep",
  hidden = true,
  file_types = {},
  globs = {},
  exclude = {},
}

local MATCH = vim.json.encode({
  type = "match",
  data = {
    path = { text = "C:/x/ok.txt" },
    lines = { text = "foo here\n" },
    line_number = 1,
    absolute_offset = 0,
    submatches = { { match = { text = "foo" }, start = 0, ["end"] = 3 } },
  },
}) .. "\n"

local PARTIAL = "rg: C:\\x\\dead.md: Das System kann die angegebene Datei nicht finden. (os error 2)\n"
  .. "rg: C:\\x\\dead2.md: Das System kann den angegebenen Pfad nicht finden. (os error 3)\n"
local REGEX_ERR = "rg: regex parse error:\n    (foo\n    ^\nerror: unclosed group\n"

local real_system = vim.system
local function stub(stdout, stderr)
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(_, opts, cb)
    local obj = { code = 2, stdout = stdout, stderr = stderr }
    if cb then
      if opts and opts.stdout then
        opts.stdout(nil, stdout)
      end
      vim.schedule(function()
        cb(obj)
      end)
      return { kill = function() end }
    end
    return {
      wait = function()
        return obj
      end,
    }
  end
end

local function run_async()
  local done, got = false, nil
  rg.collect_async("foo", { "." }, cfg, function(items, err)
    got = { items = items, err = err }
    done = true
  end)
  vim.wait(5000, function()
    return done
  end, 20)
  return got
end

-- Partial failure: matches are kept, no error.
stub(MATCH, PARTIAL)
local items, err = rg.collect("foo", { "." }, cfg)
check("sync: unreadable paths -> no error", err == nil, err and err.message)
check("sync: unreadable paths -> matches kept", items and #items == 1, items and #items)
local got = run_async()
check(
  "async: unreadable paths -> no error",
  got and got.err == nil,
  got and got.err and got.err.message
)
check("async: unreadable paths -> matches kept", got and got.items and #got.items == 1)

-- Partial failure without any match is still a (empty) success.
stub("", PARTIAL)
items, err = rg.collect("foo", { "." }, cfg)
check(
  "sync: only unreadable paths, no match -> empty success",
  err == nil and items and #items == 0
)

-- Real errors still fail.
stub("", REGEX_ERR)
err = select(2, rg.collect("(foo", { "." }, cfg))
check("sync: regex error still fails", err ~= nil and err.type == "SearchError")
got = run_async()
check("async: regex error still fails", got and got.err ~= nil and got.err.type == "SearchError")

stub("", PARTIAL .. REGEX_ERR)
err = select(2, rg.collect("foo", { "." }, cfg))
check("sync: mixed path + regex error still fails", err ~= nil)

vim.system = real_system

print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
