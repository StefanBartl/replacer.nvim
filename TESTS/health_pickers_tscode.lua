-- Headless test for replacer.health, the picker-engine-agnostic halves of
-- replacer.pickers.common / replacer.pickers.utils, replacer.tscode's real
-- Tree-sitter classification, and a smoke check of replacer.util.notify.
-- Run:  nvim -l TESTS/health_pickers_tscode.lua
--
-- replacer.pickers.{fzf,telescope}.run() themselves are NOT exercised here:
-- both hard-require an actual picker backend (fzf-lua / telescope.nvim),
-- neither of which is a CI sibling checkout (only lib.nvim/ui.nvim/
-- pickers.nvim are, per .github/workflows/ci.yml) -- same deliberate
-- exclusion other rounds of this campaign gave equivalent adapters in
-- recommender.nvim/language.nvim (their ui.kit-gated modules).

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
local common = require("replacer.pickers.common")
local putils = require("replacer.pickers.utils")
local tscode = require("replacer.tscode")

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

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

--------------------------------------------------------------------------------
-- 1) replacer.util.notify: real (unstubbed) smoke check -- the module is a
--    one-line factory (`lib.nvim.notify.create("[replacer]")`), so what is
--    worth checking is that it actually returns a working notifier and a
--    real call does not error, not any branching (it has none of its own).
--------------------------------------------------------------------------------
do
  local notify = require("replacer.util.notify")
  check(
    "notify: create() returns info/warn/error/debug functions",
    type(notify.info) == "function"
      and type(notify.warn) == "function"
      and type(notify.error) == "function"
      and type(notify.debug) == "function"
  )
  local ok = pcall(notify.info, "TESTS/health_pickers_tscode.lua smoke message")
  check("notify: a real call does not error", ok)
end

--------------------------------------------------------------------------------
-- 2) replacer.pickers.utils: pure helpers, no picker backend needed
--------------------------------------------------------------------------------
do
  check(
    "utils.byte_to_display_col: ASCII prefix -> byte count",
    putils.byte_to_display_col("hello world", 5) == 5
  )
  check("utils.byte_to_display_col: nil line -> 0", putils.byte_to_display_col(nil, 3) == 0)
  check("utils.byte_to_display_col: zero offset -> 0", putils.byte_to_display_col("hello", 0) == 0)

  local ns1 = putils.get_ns()
  local ns2 = putils.get_ns()
  check(
    "utils.get_ns: stable namespace id across calls (same name)",
    type(ns1) == "number" and ns1 == ns2
  )

  local ok_off = putils.setup_highlight_groups(nil)
  check("utils.setup_highlight_groups: nil cfg -> no-op, no error", ok_off == nil)
  local ok_disabled = putils.setup_highlight_groups({ enabled = false })
  check("utils.setup_highlight_groups: enabled=false -> no-op", ok_disabled == nil)

  local ok_on = putils.setup_highlight_groups({
    enabled = true,
    old_bg = "#440000",
    old_fg = "#ffffff",
    strikethrough = true,
    new_fg = "#00ff00",
  })
  check("utils.setup_highlight_groups: enabled -> returns ok", ok_on == true)
  local hl_old = vim.api.nvim_get_hl(0, { name = "ReplacerOld" })
  check("utils.setup_highlight_groups: ReplacerOld group defined", next(hl_old) ~= nil)
  local hl_strike = vim.api.nvim_get_hl(0, { name = "ReplacerOldStrikethrough" })
  check(
    "utils.setup_highlight_groups: strikethrough=true also defines the strike group",
    hl_strike.strikethrough == true,
    vim.inspect(hl_strike)
  )

  local old_ansi, new_ansi = putils.ansi_snippets({}, "foo", "bar")
  check(
    "utils.ansi_snippets: default codes wrap old/new text",
    old_ansi:find("foo", 1, true) ~= nil
      and new_ansi:find("bar", 1, true) ~= nil
      and old_ansi:find("\27[", 1, true) ~= nil,
    old_ansi
  )
  local old_ansi2 = putils.ansi_snippets({ ansi_old_bg = "44" }, "x", "y")
  check(
    "utils.ansi_snippets: cfg overrides the ANSI code used",
    old_ansi2:find("44", 1, true) ~= nil,
    old_ansi2
  )
end

--------------------------------------------------------------------------------
-- 3) replacer.pickers.common: format_display / preview_lines_with_pos /
--    notify_result / register_which_key (new_refine()/without() are already
--    covered end-to-end by TESTS/refine_wiring.lua).
--------------------------------------------------------------------------------
do
  ---@diagnostic disable: missing-fields
  local it = { path = tmp .. "/sub/file.txt", lnum = 3, col0 = 2, line = "  foo bar" }
  ---@diagnostic enable: missing-fields
  local disp = common.format_display(it)
  check(
    "common.format_display: path:line:col — text",
    disp:find(":3:3", 1, true) ~= nil and disp:find("foo bar", 1, true) ~= nil,
    disp
  )

  -- preview_lines_with_pos against a real multi-line file
  local pv_file = tmp .. "/preview.txt"
  do
    local fh = assert(io.open(pv_file, "w"))
    for i = 1, 10 do
      fh:write(string.format("line %d\n", i))
    end
    fh:close()
  end
  ---@diagnostic disable: missing-fields
  local mid = { path = pv_file, lnum = 5, col0 = 2 }
  ---@diagnostic enable: missing-fields
  local lines, row0, col0 = common.preview_lines_with_pos(mid, 2)
  check("preview: window is ctx*2+1 lines (lines 3..7)", #lines == 5, #lines)
  check("preview: hit line carries the ▶ marker", lines[row0 + 1]:find("▶", 1, true) ~= nil)
  check(
    "preview: target_col0 accounts for the rendered prefix + original col0",
    col0 == (#"▶ " + #"     5" + #"  ") + 2,
    col0
  )

  -- Clamped at the start of the file.
  ---@diagnostic disable: missing-fields
  local first = { path = pv_file, lnum = 1, col0 = 0 }
  ---@diagnostic enable: missing-fields
  local lines_first, row0_first = common.preview_lines_with_pos(first, 2)
  check(
    "preview: clamps at the top of the file (no negative lines)",
    #lines_first == 3,
    #lines_first
  )
  check("preview: hit row is first row when clamped at the top", row0_first == 0)

  -- Unreadable path -> graceful fallback, not an error.
  local lines_bad =
    common.preview_lines_with_pos({ path = tmp .. "/does_not_exist.txt", lnum = 1, col0 = 0 }, 2)
  check("preview: unreadable path -> single '[unreadable]' line", lines_bad[1] == "[unreadable]")

  -- notify_result: honors cfg.quiet / cfg.messages via replacer.messages
  local infos = {}
  local notify = require("replacer.util.notify")
  local orig_info = notify.info
  notify.info = function(msg)
    infos[#infos + 1] = msg
  end
  common.notify_result(2, 5, nil)
  check("common.notify_result: default template", infos[1] == "5 spot(s) in 2 file(s)", infos[1])
  common.notify_result(2, 5, { quiet = true })
  check("common.notify_result: cfg.quiet suppresses it", #infos == 1)
  notify.info = orig_info

  -- register_which_key: no-op (not an error) when which-key.nvim is absent.
  local buf = vim.api.nvim_create_buf(false, true)
  local ok_wk = pcall(common.register_which_key, buf, {
    { lhs = "<Esc>", desc = "close" },
  })
  check("common.register_which_key: no-op without which-key.nvim installed", ok_wk)

  -- Inject a fake which-key to exercise the real translation branch.
  local captured_spec
  package.loaded["which-key"] = {
    add = function(spec)
      captured_spec = spec
    end,
  }
  common.register_which_key(buf, {
    { lhs = "<C-a>", desc = "apply all", modes = { "n", "i" } },
  })
  check(
    "common.register_which_key: expands one entry per declared mode",
    captured_spec ~= nil and #captured_spec == 2,
    vim.inspect(captured_spec)
  )
  check(
    "common.register_which_key: each spec item carries lhs/desc/mode/buffer",
    captured_spec[1][1] == "<C-a>"
      and captured_spec[1].desc == "apply all"
      and captured_spec[1].buffer == buf
  )
  package.loaded["which-key"] = nil
end

--------------------------------------------------------------------------------
-- 4) replacer.tscode: real Tree-sitter classification (skipped gracefully
--    if this Neovim build has no bundled Lua parser).
--------------------------------------------------------------------------------
do
  local has_lua_parser = pcall(vim.treesitter.get_string_parser, "local x = 1", "lua")
  if not has_lua_parser then
    print("SKIP  tscode real-classification tests (no Tree-sitter Lua parser in this Neovim build)")
  else
    local content = 'local x = "hello world" -- a comment\nlocal y = 1\n'
    -- byte offset of a char inside the string literal "hello world"
    local str_col0 = content:find("hello", 1, true) - 1
    check(
      "tscode: byte inside a string literal -> true",
      tscode.is_in_string_or_comment("probe.lua", content, 0, str_col0) == true
    )

    local comment_col0 = content:find("a comment", 1, true) - 1
    check(
      "tscode: byte inside a line comment -> true",
      tscode.is_in_string_or_comment("probe.lua", content, 0, comment_col0) == true
    )

    check(
      "tscode: byte inside real code (not string/comment) -> false",
      tscode.is_in_string_or_comment("probe.lua", content, 1, 0) == false
    )
  end

  -- Already-known fails-open path (kept here alongside its positive
  -- counterparts above rather than duplicated -- feature_smoke.lua also
  -- checks this once).
  check(
    "tscode: unresolvable filetype -> fails open (false)",
    tscode.is_in_string_or_comment("nonexistent.zzzUnknownExt", "foo", 0, 0) == false
  )
end

--------------------------------------------------------------------------------
-- 5) replacer.health: stub vim.health to capture the report without
--    depending on which optional tools (rg/telescope/fzf-lua/which-key)
--    happen to be installed on the machine running the suite.
--------------------------------------------------------------------------------
do
  replacer.setup({ engine = "auto", search_engine = "auto" })
  -- Make sure the composer verbs health.check() pre-flights actually exist,
  -- same as a real session (plugin/replacer.lua does this at startup).
  vim.g.__replacer_cmd_registered = nil
  pcall(require, "replacer.bindings")
  package.loaded["replacer.bindings"] = nil
  require("replacer.bindings").setup()

  local health_mod = require("replacer.health")

  local calls = {}
  local fake_health = {
    start = function(name)
      calls[#calls + 1] = { kind = "start", name = name }
    end,
    ok = function(msg)
      calls[#calls + 1] = { kind = "ok", msg = msg }
    end,
    warn = function(msg, advice)
      calls[#calls + 1] = { kind = "warn", msg = msg, advice = advice }
    end,
    error = function(msg, advice)
      calls[#calls + 1] = { kind = "error", msg = msg, advice = advice }
    end,
    info = function(msg)
      calls[#calls + 1] = { kind = "info", msg = msg }
    end,
  }
  local orig_health = vim.health
  vim.health = fake_health --[[@as table]]

  local ok_check, check_err = pcall(health_mod.check)

  vim.health = orig_health

  check("health.check(): runs to completion without error", ok_check, check_err)

  local starts = {}
  for _, c in ipairs(calls) do
    if c.kind == "start" then
      starts[#starts + 1] = c.name
    end
  end
  local function has_start(name)
    for _, s in ipairs(starts) do
      if s == name then
        return true
      end
    end
    return false
  end
  check("health.check(): reports a Neovim section", has_start("Neovim"))
  check("health.check(): reports a lib.nvim section", has_start("lib.nvim"))
  check("health.check(): reports a ripgrep section", has_start("ripgrep"))
  check("health.check(): reports a Pickers section", has_start("Pickers"))
  check("health.check(): reports a Configuration section", has_start("Configuration"))
  check("health.check(): reports a UTF-8 Support section", has_start("UTF-8 Support"))
  check(
    "health.check(): reports an Optional integrations section",
    has_start("Optional integrations")
  )
  check("health.check(): reports a Summary section", has_start("Summary"))
  check("health.check(): at least one 'ok' entry was reported", #vim.tbl_filter(function(c)
    return c.kind == "ok"
  end, calls) > 0)
end

--------------------------------------------------------------------------------
-- 6) BUG (pinned, not fixed -- see TESTS/README.md): check_lib_nvim() already
--    reports + degrades gracefully when
--    lib.nvim.bindings.usercmd.composer is missing, but M.check() itself
--    then unconditionally requires that exact module again a few lines
--    later for the "composer route pre-flight" (:Replace/:Surround
--    checkhealth), with no pcall guard. Simulated via package.preload so the
--    require genuinely fails (lib.nvim is otherwise present and required for
--    this whole suite -- only this one submodule is made to look missing,
--    e.g. an older lib.nvim checkout without it), rather than swapping in a
--    fake table that would just mask the real crash.
--------------------------------------------------------------------------------
do
  local health_mod = require("replacer.health")
  local mod_name = "lib.nvim.bindings.usercmd.composer"
  local real_mod = package.loaded[mod_name]
  package.loaded[mod_name] = nil
  package.preload[mod_name] = function()
    error("simulated: " .. mod_name .. " unavailable (e.g. an older lib.nvim checkout)")
  end

  local calls2 = {}
  local fake_health2 = {
    start = function(name)
      calls2[#calls2 + 1] = { kind = "start", name = name }
    end,
    ok = function(msg)
      calls2[#calls2 + 1] = { kind = "ok", msg = msg }
    end,
    warn = function(msg, advice)
      calls2[#calls2 + 1] = { kind = "warn", msg = msg, advice = advice }
    end,
    error = function(msg, advice)
      calls2[#calls2 + 1] = { kind = "error", msg = msg, advice = advice }
    end,
    info = function(msg)
      calls2[#calls2 + 1] = { kind = "info", msg = msg }
    end,
  }
  local orig_health2 = vim.health
  vim.health = fake_health2 --[[@as table]]

  local ok_check2, err2 = pcall(health_mod.check)

  vim.health = orig_health2
  package.preload[mod_name] = nil
  package.loaded[mod_name] = real_mod

  local reported_missing = false
  for _, c in ipairs(calls2) do
    if c.kind == "error" and c.msg and c.msg:find("lib.nvim not found", 1, true) then
      reported_missing = true
    end
  end
  check(
    "BUG setup: check_lib_nvim() reports the missing submodule via health.error()",
    reported_missing,
    vim.inspect(calls2)
  )
  check(
    "BUG: health.check() then crashes on the SAME missing dependency instead of "
      .. "degrading to the warning check_lib_nvim() already issued -- the composer "
      .. "pre-flight calls at the end of M.check() are unconditional, with no pcall",
    ok_check2 == false,
    err2
  )
end

print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
