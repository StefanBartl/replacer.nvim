-- Headless test for the option cheatsheet texts of the composer verbs
-- (:Replace, :Replacer, :Surround, :Wrap).
-- Run:  nvim -l TESTS/usrcmd_option_help.lua
--
-- composer's help float shows one line per flag / key=value pair. The line is
-- the `desc` of the FlagSpec (`--no-x` twins inherit "Off: <text of --x>").
-- `composer.help.undocumented(verb)` lists what has none; this suite pins that
-- list to empty, so a flag added to command.lua / surround.lua without a text
-- fails here instead of showing a bare option name in the float.

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
local add_ui_nvim = dofile((this_file:match("^(.*)/[^/]+$") or ".") .. "/resolve_ui_nvim.lua")
if not add_ui_nvim() then
  print("FAIL  cannot locate ui.nvim (a runtime dependency of replacer.nvim).")
  print("      Set $UI_NVIM_PATH, or check it out next to this repo.")
  os.exit(1)
end

local replacer = require("replacer")
local command = require("replacer.command")
local composer = require("lib.nvim.bindings.usercmd.composer")

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
-- 0) The API under test exists (an older lib.nvim checkout predates it)
--------------------------------------------------------------------------------
if type(composer.help) ~= "table" or type(composer.help.undocumented) ~= "function" then
  print("FAIL  lib.nvim has no composer.help.undocumented() -- update the lib.nvim checkout")
  os.exit(1)
end

--------------------------------------------------------------------------------
-- 1) Register the real verbs the way a session does
--------------------------------------------------------------------------------
replacer.setup({ search_engine = "vimgrep", confirm_all = false, write_changes = true })
vim.g.__replacer_cmd_registered = nil
vim.cmd("source " .. vim.fn.getcwd() .. "/plugin/replacer.lua")

local VERBS = { "Replace", "Replacer", "Surround", "Wrap" }
local registry = composer.registry()

--------------------------------------------------------------------------------
-- 2) Every flag / key=value of every verb shows a text
--------------------------------------------------------------------------------
for _, verb in ipairs(VERBS) do
  check("registered: " .. verb .. " is a composer verb", registry[verb] ~= nil)

  local missing = composer.help.undocumented(verb)
  local names = {}
  for _, m in ipairs(missing) do
    names[#names + 1] = m.kind .. ":" .. m.name
  end
  check(
    "undocumented(" .. verb .. ") is empty",
    #missing == 0,
    "no text for: " .. table.concat(names, ", ")
  )
end

--------------------------------------------------------------------------------
-- 3) The check is not vacuous, and the texts follow the house style
--------------------------------------------------------------------------------
do
  local with_desc, twins = 0, 0
  local bad = {}
  for _, spec in ipairs(command.FLAGS) do
    if spec.desc then
      with_desc = with_desc + 1
      local d = spec.desc
      if d:find("\n", 1, true) or #d > 70 or d:sub(-1) == "." then
        bad[#bad + 1] = spec.name
      end
    elseif spec.name:match("^no%-") then
      twins = twins + 1
    end
  end
  check("flags: the table is not empty", #command.FLAGS > 0 and with_desc > 0)
  check("flags: every one has a text or is a --no-x twin", with_desc + twins == #command.FLAGS)
  check("flags: texts are one line, <= 70 chars, no period", #bad == 0, table.concat(bad, ", "))
end

--------------------------------------------------------------------------------
-- 4) :Surround's own additions and corrections
--------------------------------------------------------------------------------
do
  local surround_spec = registry["Surround"]:spec().routes[1].flags
  local by_name = {}
  for _, spec in ipairs(surround_spec) do
    by_name[spec.name] = spec
  end
  local replace_by_name = {}
  for _, spec in ipairs(command.FLAGS) do
    replace_by_name[spec.name] = spec
  end

  check("surround: --nested has a text", by_name["nested"] and by_name["nested"].desc ~= nil)
  check(
    "surround: --allow-nested has a text",
    by_name["allow-nested"] and by_name["allow-nested"].desc ~= nil
  )
  check(
    "surround: --regex says it does nothing here",
    by_name["regex"].desc ~= replace_by_name["regex"].desc
      and by_name["regex"].desc:find("No effect", 1, true) ~= nil,
    by_name["regex"].desc
  )
  check(
    "surround: --no-literal says it does nothing here",
    by_name["no-literal"].desc:find("No effect", 1, true) ~= nil,
    by_name["no-literal"].desc
  )
  check(
    "replace: --regex keeps its own text (surround edits a copy)",
    replace_by_name["regex"].desc:find("No effect", 1, true) == nil,
    replace_by_name["regex"].desc
  )
end

--------------------------------------------------------------------------------
print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
