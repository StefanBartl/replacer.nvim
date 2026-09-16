-- Headless test for replacer.bindings.{init,usrcmds,keymaps,autocmds} and the
-- :ReplaceTest live panel (replacer.regex.open_test_panel) they wire up.
-- Run:  nvim -l TESTS/bindings_wiring.lua

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
local usrcmds = require("replacer.bindings.usrcmds")
local keymaps = require("replacer.bindings.keymaps")
local autocmds = require("replacer.bindings.autocmds")
local regex = require("replacer.regex")

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
-- 1) usrcmds.REGISTRY / names(): the "who owns what" table
--------------------------------------------------------------------------------
do
  local names = usrcmds.names()
  check("usrcmds.names(): thirteen commands, per the module's own header", #names == 13, #names)

  local set = {}
  for _, n in ipairs(names) do
    set[n] = true
  end
  for _, expect in ipairs({
    "Replace",
    "Replacer",
    "Surround",
    "Wrap",
    "ReplaceEscape",
    "ReplaceTest",
    "ReplaceRoot",
    "ReplaceUndo",
    "ReplaceHistory",
    "ReplacePreset",
    "ReplaceSavePreset",
    "ReplaceBatch",
    "ReplaceFNames",
  }) do
    check("usrcmds.names(): includes " .. expect, set[expect] == true)
  end

  -- ReplaceDebug is deliberately absent -- registered lazily by replacer.debug
  -- on first use, per the module's own header comment.
  check("usrcmds.names(): ReplaceDebug is deliberately absent", set["ReplaceDebug"] == nil)

  local needs_run_modules, no_run_modules = 0, 0
  for _, entry in ipairs(usrcmds.REGISTRY) do
    if entry.needs_run then
      needs_run_modules = needs_run_modules + 1
    else
      no_run_modules = no_run_modules + 1
    end
  end
  check(
    "usrcmds.REGISTRY: some entries need run(), some don't",
    needs_run_modules > 0 and no_run_modules > 0
  )
end

--------------------------------------------------------------------------------
-- 2) bindings.setup(): end-to-end registration through replacer.bindings
--------------------------------------------------------------------------------
do
  -- Undo plugin/replacer.lua's idempotency guard so this actually registers
  -- (the real entry point already ran it once via TESTS' own boilerplate
  -- resolving replacer -- calling setup() again must be safe/idempotent too).
  local registered = require("replacer.bindings").setup()
  check("bindings.setup(): returns every registered command name", #registered == #usrcmds.names())

  for _, cmd in ipairs({ "Replace", "Surround", "ReplaceUndo", "ReplaceHistory", "ReplaceFNames" }) do
    check("bindings.setup(): :" .. cmd .. " actually exists", vim.fn.exists(":" .. cmd) == 2)
  end
end

--------------------------------------------------------------------------------
-- 3) bindings.keymaps.attach_test_panel: both close keys invoke `close`
--------------------------------------------------------------------------------
do
  local buf1 = vim.api.nvim_create_buf(false, true)
  local closed1 = 0
  keymaps.attach_test_panel(buf1, function()
    closed1 = closed1 + 1
  end)
  vim.api.nvim_set_current_buf(buf1)

  local m_esc = vim.fn.maparg("<Esc>", "n", false, true)
  check(
    "keymaps: <Esc> is bound buffer-locally with a callback",
    type(m_esc) == "table" and m_esc.buffer == 1 and type(m_esc.callback) == "function",
    vim.inspect(m_esc)
  )
  if type(m_esc) == "table" and type(m_esc.callback) == "function" then
    m_esc.callback()
  end
  check("keymaps: invoking the <Esc> binding calls close()", closed1 == 1)

  local m_q = vim.fn.maparg("q", "n", false, true)
  check(
    "keymaps: q is bound buffer-locally with a callback",
    type(m_q) == "table" and type(m_q.callback) == "function"
  )
  if type(m_q) == "table" and type(m_q.callback) == "function" then
    m_q.callback()
  end
  check("keymaps: invoking the q binding also calls close()", closed1 == 2)
end

--------------------------------------------------------------------------------
-- 4) bindings.autocmds.attach_test_panel: TextChanged/TextChangedI re-highlight
--------------------------------------------------------------------------------
do
  local buf2 = vim.api.nvim_create_buf(false, true)
  local seen = {}
  autocmds.attach_test_panel(buf2, function(b)
    seen[#seen + 1] = b
  end)

  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf2 })
  check(
    "autocmds: TextChanged fires the callback with the panel's buffer",
    #seen == 1 and seen[1] == buf2,
    vim.inspect(seen)
  )

  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf2 })
  check("autocmds: TextChangedI also fires it", #seen == 2)

  -- Buffer-local: an unrelated buffer must never trigger it.
  local buf3 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf3 })
  check("autocmds: a different buffer does not trigger the callback", #seen == 2)
end

--------------------------------------------------------------------------------
-- 5) End-to-end: replacer.regex.open_test_panel() wires both hooks for real
--    (the actual :ReplaceTest float, not a stand-in buffer).
--------------------------------------------------------------------------------
do
  replacer.setup({})
  regex.register()
  check("regex: :ReplaceTest registered", vim.fn.exists(":ReplaceTest") == 2)

  vim.cmd("ReplaceTest foo foobar")
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 2, false)
  check(
    "ReplaceTest: panel seeds pattern/sample from the command args",
    lines[1] == "foo" and lines[2] == "foobar",
    vim.inspect(lines)
  )

  local ns = vim.api.nvim_create_namespace("replacer_regex_test")
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  check("ReplaceTest: initial highlight already ran (pattern matches the sample)", #marks >= 1)

  -- Edit line 2 (sample) and fire the autocmd manually -- TextChanged only
  -- fires on a real buffer-changing edit path in Neovim, which headless
  -- `nvim_buf_set_lines` alone does not always dispatch reliably; the panel's
  -- own wiring (tested above in isolation) is what matters here, so trigger
  -- it explicitly to prove the *panel* is the one actually connected to it.
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "no match here" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  local marks2 = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  check(
    "ReplaceTest: re-highlight clears stale marks when the sample no longer matches",
    #marks2 == 0
  )

  -- q closes the float.
  local win = vim.api.nvim_get_current_win()
  local m_q = vim.fn.maparg("q", "n", false, true)
  check("ReplaceTest: q is bound in the panel buffer", type(m_q.callback) == "function")
  if type(m_q.callback) == "function" then
    m_q.callback()
  end
  check("ReplaceTest: q actually closed the float window", vim.api.nvim_win_is_valid(win) == false)
end

print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
