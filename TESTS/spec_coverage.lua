-- Headless test: every script under TESTS/ is either picked up by the
-- testing.nvim runner (a `spec_pattern` of `.testing.lua` matches it) or is
-- a known non-test helper. The scripts carry no `_spec` suffix, so a new one
-- is silently never run unless it is added to `spec_pattern`; this script
-- turns that into a red run.
-- Run:  nvim -l TESTS/spec_coverage.lua

-- absolute: `nvim -l TESTS/x.lua` reports a relative source
local this_file = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"):gsub("\\", "/")
local dir = vim.fn.fnamemodify(this_file, ":h")
local root = vim.fn.fnamemodify(dir, ":h")

-- Files under TESTS/ that are not test scripts (see TESTS/README.md,
-- "Present but not run by CI").
local NOT_SPECS = {
  ["minimal_init.lua"] = true,
  ["resolve_lib_nvim.lua"] = true,
  ["resolve_ui_nvim.lua"] = true,
  ["health_debug.lua"] = true,
}

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

local ok, conf = pcall(dofile, root .. "/.testing.lua")
check(".testing.lua loads", ok and type(conf) == "table", not ok and conf or nil)
local patterns = (ok and type(conf) == "table" and conf.spec_pattern) or {}
if type(patterns) == "string" then
  patterns = { patterns }
end
check("spec_pattern is a non-empty list", type(patterns) == "table" and #patterns > 0)

local function is_spec(rel)
  for _, pat in ipairs(patterns) do
    if rel:match(pat) then
      return true
    end
  end
  return false
end

local names = {}
for name, kind in vim.fs.dir(dir) do
  if kind == "file" and name:match("%.lua$") then
    names[#names + 1] = name
  end
end
table.sort(names)
check("TESTS/ has scripts", #names > 0)

for _, name in ipairs(names) do
  local rel = "TESTS/" .. name
  if NOT_SPECS[name] then
    check(rel .. " is a helper and not run as a spec", not is_spec(rel))
  else
    check(rel .. " is matched by spec_pattern", is_spec(rel))
  end
end

-- a helper listed above that no longer exists is a stale entry
for name in pairs(NOT_SPECS) do
  check("helper TESTS/" .. name .. " exists", vim.fn.filereadable(dir .. "/" .. name) == 1)
end

print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
