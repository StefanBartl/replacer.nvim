-- Headless test for the option cheatsheet texts of the composer verbs
-- (:Replace, :Replacer, :Surround, :Wrap).
-- Run:  nvim -l TESTS/usrcmd_option_help.lua
--
-- composer's help float shows one line per flag / key=value pair. The line is
-- the `desc` of the FlagSpec (`--no-x` twins inherit "Off: <text of --x>").
-- `composer.help.undocumented(verb)` lists what has none; this suite pins that
-- list to empty, so a flag added to command.lua / surround.lua without a text
-- fails here instead of showing a bare option name in the float.
--
-- The body runs under xpcall: under `nvim --headless -c "luafile ..." -c "qa"`
-- an uncaught error only prints and the process still exits 0, so a crash (for
-- example a verb that failed to register) would leave CI green. A crash is
-- reported as a FAIL with its traceback and ends in `cquit 1`.

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

local function main()
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

  ------------------------------------------------------------------------------
  -- 0) The API under test exists (an older lib.nvim checkout predates it)
  ------------------------------------------------------------------------------
  -- `composer.help` is a lazy proxy table, so `type(composer.help)` is "table"
  -- even when the help module is missing; the failure only shows on the first
  -- field access. Probe that access instead of the proxy.
  local ok_probe, undocumented = pcall(function()
    return composer.help.undocumented
  end)
  if not ok_probe or type(undocumented) ~= "function" then
    print("FAIL  lib.nvim has no composer.help.undocumented() -- update the lib.nvim checkout")
    if not ok_probe then
      print("      " .. tostring(undocumented))
    end
    os.exit(1)
  end

  ------------------------------------------------------------------------------
  -- 1) Register the real verbs the way a session does
  ------------------------------------------------------------------------------
  replacer.setup({ search_engine = "vimgrep", confirm_all = false, write_changes = true })
  vim.g.__replacer_cmd_registered = nil
  vim.cmd("source " .. vim.fn.getcwd() .. "/plugin/replacer.lua")

  local VERBS = { "Replace", "Replacer", "Surround", "Wrap" }
  local registry = composer.registry()

  -- The spec of a registered verb, or nil when it is not registered (that case
  -- is reported by the "registered:" check; the sections below skip it instead
  -- of crashing on an index of nil).
  ---@param verb string
  ---@return table|nil
  local function spec_of(verb)
    local entry = registry[verb]
    return entry and entry:spec() or nil
  end

  ------------------------------------------------------------------------------
  -- 2) Every flag / key=value of every verb shows a text
  ------------------------------------------------------------------------------
  for _, verb in ipairs(VERBS) do
    check("registered: " .. verb .. " is a composer verb", registry[verb] ~= nil)

    local missing = undocumented(verb)
    local names = {}
    for _, m in ipairs(missing) do
      names[#names + 1] = m.kind .. ":" .. m.name
    end
    check(
      "undocumented(" .. verb .. ") is empty",
      #missing == 0,
      "no text for: " .. table.concat(names, ", ")
    )

    -- The positional arguments ({old} {new} [scope] / {pattern} [delim] [scope])
    -- too: each one shows a line in the float for the slot you are typing.
    local missing_args = undocumented(verb, { args = true })
    local arg_names = {}
    for _, m in ipairs(missing_args) do
      arg_names[#arg_names + 1] = m.kind .. ":" .. m.name
    end
    check(
      "undocumented(" .. verb .. ", { args = true }) is empty",
      #missing_args == 0,
      "no text for: " .. table.concat(arg_names, ", ")
    )
  end

  ------------------------------------------------------------------------------
  -- 3) The check is not vacuous, and the texts follow the house style
  ------------------------------------------------------------------------------
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

  ------------------------------------------------------------------------------
  -- 3b) The positional-argument texts follow the same style
  ------------------------------------------------------------------------------
  do
    local bad, seen_args, seen_enum = {}, 0, 0
    local function style(label, text)
      if text:find("\n", 1, true) or #text > 70 or text:sub(-1) == "." or text == "" then
        bad[#bad + 1] = label
      end
    end
    for _, verb in ipairs(VERBS) do
      local spec = spec_of(verb)
      for _, route in ipairs(spec and spec.routes or {}) do
        for _, arg in ipairs(route.args or {}) do
          seen_args = seen_args + 1
          if arg.desc then
            style(verb .. "/" .. arg.name, arg.desc)
          end
          for value, text in pairs(arg.enum_desc or {}) do
            seen_enum = seen_enum + 1
            style(verb .. "/" .. arg.name .. "=" .. value, text)
          end
        end
      end
    end
    check("args: the check is not vacuous", seen_args >= 12 and seen_enum > 0)
    check("args: texts are one line, <= 70 chars, no period", #bad == 0, table.concat(bad, ", "))

    -- Every enum_desc key is a real value (a typo would describe nothing).
    local stray = {}
    for _, verb in ipairs(VERBS) do
      local spec = spec_of(verb)
      local route = spec and spec.routes and spec.routes[1]
      for _, arg in ipairs(route and route.args or {}) do
        local values = {}
        for _, v in ipairs(arg.enum or arg.values or {}) do
          values[v] = true
        end
        for value in pairs(arg.enum_desc or {}) do
          if not values[value] then
            stray[#stray + 1] = verb .. "/" .. arg.name .. "=" .. value
          end
        end
      end
    end
    check(
      "args: every enum_desc key is one of the arg's values",
      #stray == 0,
      table.concat(stray, ", ")
    )
  end

  ------------------------------------------------------------------------------
  -- 4) :Surround's own additions and corrections
  ------------------------------------------------------------------------------
  do
    local surround = spec_of("Surround")
    local surround_route = surround and surround.routes and surround.routes[1]
    check("surround: the verb has a route with flags", surround_route and surround_route.flags)

    local by_name = {}
    for _, spec in ipairs(surround_route and surround_route.flags or {}) do
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
      by_name["regex"]
        and by_name["regex"].desc ~= replace_by_name["regex"].desc
        and by_name["regex"].desc:find("No effect", 1, true) ~= nil,
      by_name["regex"] and by_name["regex"].desc
    )
    check(
      "surround: --no-literal says it does nothing here",
      by_name["no-literal"] and by_name["no-literal"].desc:find("No effect", 1, true) ~= nil,
      by_name["no-literal"] and by_name["no-literal"].desc
    )
    check(
      "replace: --regex keeps its own text (surround edits a copy)",
      replace_by_name["regex"].desc:find("No effect", 1, true) == nil,
      replace_by_name["regex"].desc
    )
  end
end

--------------------------------------------------------------------------------
local ok, err = xpcall(main, debug.traceback)
if not ok then
  fail = fail + 1
  print("FAIL  suite crashed before it finished")
  print(tostring(err))
end

print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
