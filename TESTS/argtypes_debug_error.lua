-- Headless test for replacer.argtypes, replacer.debug, and replacer.error.
-- Run:  nvim -l TESTS/argtypes_debug_error.lua

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

local argtypes = require("replacer.argtypes")
local error_mod = require("replacer.error")

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
-- 1) replacer.error: structured errors + safe_call envelope
--------------------------------------------------------------------------------
do
  local e1 = error_mod.new("CustomError", "boom", { detail = 1 })
  check(
    "error.new: shape",
    e1.type == "CustomError" and e1.message == "boom" and e1.cause.detail == 1
  )

  local e2 = error_mod.invalid_scope("bad scope")
  check("error.invalid_scope: typed", e2.type == "InvalidScopeError" and e2.message == "bad scope")

  local e3 = error_mod.write_error("write failed", "disk full")
  check("error.write_error: typed + cause", e3.type == "WriteError" and e3.cause == "disk full")

  local e4 = error_mod.search_error("search failed")
  check("error.search_error: typed", e4.type == "SearchError")

  local ok_env = error_mod.safe_call(function(a, b)
    return a + b
  end, 2, 3)
  check("safe_call: ok envelope", ok_env.ok == true and ok_env.result == 5 and ok_env.err == nil)

  local err_env = error_mod.safe_call(function()
    error("kaboom")
  end)
  check(
    "safe_call: error envelope catches the throw",
    err_env.ok == false and err_env.err ~= nil and err_env.err.type == "RuntimeError",
    vim.inspect(err_env)
  )
  check(
    "safe_call: error envelope preserves the original message as .cause",
    tostring(err_env.err.cause):find("kaboom", 1, true) ~= nil
  )

  check(
    "error.format: table error -> '[Type] message'",
    error_mod.format(e2) == "[InvalidScopeError] bad scope",
    error_mod.format(e2)
  )
  check(
    "error.format: non-table falls back to tostring",
    error_mod.format("plain string") == "plain string"
  )
  check("error.format: missing type/message still renders", error_mod.format({}) == "[Error] ")
end

--------------------------------------------------------------------------------
-- 2) replacer.argtypes: registers RP_RG_TYPE / RP_CHANGED_KINDS with
--    composer's own argtype registry -- fetched back via
--    lib.nvim.bindings.usercmd.composer.argtypes.get() so the completion
--    callbacks (otherwise local to argtypes.lua) are reachable.
--------------------------------------------------------------------------------
do
  argtypes._reset_cache()
  argtypes.register()
  local composer_argtypes = require("lib.nvim.bindings.usercmd.composer.argtypes")

  local rg_type = composer_argtypes.get("RP_RG_TYPE")
  check("argtypes: RP_RG_TYPE registered", rg_type ~= nil)
  local ok_v, val = rg_type.validate("anything-goes")
  check("argtypes: RP_RG_TYPE.validate always accepts", ok_v == true and val == "anything-goes")

  if vim.fn.executable("rg") == 1 then
    local cands = rg_type.complete("l")
    check(
      "argtypes: RP_RG_TYPE.complete filters rg's real --type-list by prefix",
      type(cands) == "table",
      vim.inspect(cands)
    )
    for _, c in ipairs(cands) do
      if c:sub(1, 1) ~= "l" then
        check("argtypes: every candidate actually starts with the prefix", false, c)
      end
    end
    -- second call must hit the cache (same table shape), not re-spawn rg.
    local cands2 = rg_type.complete("l")
    check("argtypes: cached type list is stable across calls", #cands == #cands2)
  else
    print("SKIP  RP_RG_TYPE.complete (rg not on PATH)")
  end

  local changed_type = composer_argtypes.get("RP_CHANGED_KINDS")
  check("argtypes: RP_CHANGED_KINDS registered", changed_type ~= nil)

  local c1 = changed_type.complete("mod")
  check(
    "argtypes: RP_CHANGED_KINDS completes a bare prefix",
    #c1 == 1 and c1[1] == "modified",
    vim.inspect(c1)
  )

  local c2 = changed_type.complete("modified,st")
  check(
    "argtypes: RP_CHANGED_KINDS continues an in-progress comma list",
    #c2 == 1 and c2[1] == "modified,staged",
    vim.inspect(c2)
  )

  local c3 = changed_type.complete("modified,")
  table.sort(c3)
  check(
    "argtypes: RP_CHANGED_KINDS after a trailing comma offers the remaining kinds",
    #c3 == 2 and c3[1] == "modified,staged" and c3[2] == "modified,untracked",
    vim.inspect(c3)
  )

  local c4 = changed_type.complete("modified,staged,")
  check(
    "argtypes: RP_CHANGED_KINDS never re-offers an already-committed kind",
    #c4 == 1 and c4[1] == "modified,staged,untracked",
    vim.inspect(c4)
  )
end

--------------------------------------------------------------------------------
-- 3) replacer.debug: enable/disable/status, analyze_line, inspect_buffer,
--    and :ReplaceDebug dispatch.
--------------------------------------------------------------------------------
do
  package.loaded["replacer.debug"] = nil
  local dbg = require("replacer.debug")

  local infos = {}
  local errors = {}
  local notify = require("replacer.util.notify")
  local orig_info, orig_error = notify.info, notify.error
  notify.info = function(msg)
    infos[#infos + 1] = msg
  end
  notify.error = function(msg)
    errors[#errors + 1] = msg
  end

  dbg.enable()
  check("debug: enable() sets the module-local flag", dbg.status() == true)
  check("debug: status() reports ON when enabled", infos[#infos] == "Debug: ON", infos[#infos])

  dbg.disable()
  check("debug: disable() clears the flag", dbg.status() == false)
  check("debug: status() reports OFF when disabled", infos[#infos] == "Debug: OFF", infos[#infos])

  infos, errors = {}, {}
  dbg.test()
  vim.wait(50, function()
    return false
  end)
  check(
    "debug: :ReplaceDebug test finds and runs the real suite at TESTS/utf8_offsets.lua",
    #errors == 0 and infos[#infos] == "Running test suite...",
    vim.inspect({ infos = infos, errors = errors })
  )

  -- inspect_buffer / analyze_line are mostly `print`, but must never error --
  -- this exercises the buffer/line reads and (indirectly, since it is local)
  -- the char_index() byte->char helper's 0.11 signature probe.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello Müller world", "second line" })
  vim.api.nvim_set_current_buf(buf)
  local ok1 = pcall(dbg.inspect_buffer)
  check("debug: inspect_buffer() runs without error on a real buffer", ok1)

  local ok2 = pcall(dbg.analyze_line, 1, "Müller")
  check("debug: analyze_line() runs without error on a UTF-8 line with a match", ok2)
  local ok3 = pcall(dbg.analyze_line, 1, "nonexistent")
  check("debug: analyze_line() runs without error when nothing matches", ok3)
  local ok4 = pcall(dbg.analyze_line, 99, "x")
  check("debug: analyze_line() on an out-of-range line reports via notify.error, not a crash", ok4)

  notify.info = orig_info
  notify.error = orig_error

  -- :ReplaceDebug dispatch, end-to-end through the real user command.
  dbg.register_command()
  check("debug: :ReplaceDebug registered", vim.fn.exists(":ReplaceDebug") == 2)

  vim.cmd("ReplaceDebug on")
  check("debug: :ReplaceDebug on enables", dbg.status() == true)
  vim.cmd("ReplaceDebug off")
  check("debug: :ReplaceDebug off disables", dbg.status() == false)

  local usage_infos = {}
  notify.info = function(msg)
    usage_infos[#usage_infos + 1] = msg
  end
  vim.cmd("ReplaceDebug")
  check(
    "debug: :ReplaceDebug with no argument prints usage",
    #usage_infos == 1 and usage_infos[1]:find("Usage:", 1, true) ~= nil,
    vim.inspect(usage_infos)
  )
  notify.info = orig_info

  local analyze_errors = {}
  notify.error = function(msg)
    analyze_errors[#analyze_errors + 1] = msg
  end
  vim.cmd("ReplaceDebug analyze notanumber x")
  check(
    "debug: :ReplaceDebug analyze with a non-numeric line reports usage",
    #analyze_errors == 1 and analyze_errors[1]:find("Usage: :ReplaceDebug analyze", 1, true) ~= nil,
    vim.inspect(analyze_errors)
  )
  notify.error = orig_error

  -- PRIN-25: the pattern payload must keep its original case -- the verb is
  -- lowercased for dispatch, but that lowercased copy used to leak into the
  -- literal, case-sensitive line:find() search too, so an uppercase pattern
  -- like an identifier never matched.
  local case_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(case_buf, 0, -1, false, { "the answer is FooBar here" })
  vim.api.nvim_set_current_buf(case_buf)

  local printed = {}
  local orig_print = print
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(i, ...))
    end
    printed[#printed + 1] = table.concat(parts, "\t")
  end
  vim.cmd("ReplaceDebug analyze 1 FooBar")
  _G.print = orig_print

  local reported_none = false
  for _, line in ipairs(printed) do
    if line:find("No occurrences found", 1, true) then
      reported_none = true
    end
  end
  check(
    "debug: :ReplaceDebug analyze finds a mixed-case pattern (case preserved)",
    not reported_none,
    vim.inspect(printed)
  )
end

print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
