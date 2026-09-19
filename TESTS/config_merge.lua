-- Headless test for replacer.config's defaults/validation/merge logic.
-- Run:  nvim -l TESTS/config_merge.lua
-- Covers: replacer.config.DEFAULTS (pure data) and replacer.config's
-- coercers (as_bool/as_pos_int/as_engine/as_search_engine/as_progress_style/
-- as_string_list/as_keymaps), setup()/get()/resolve()'s merge semantics, and
-- the nested fzf/telescope deep-merge.

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

local DEFAULTS = require("replacer.config.DEFAULTS")
local config = require("replacer.config")

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
-- 1) DEFAULTS: pure data sanity
--------------------------------------------------------------------------------
do
  check("DEFAULTS: engine defaults to auto", DEFAULTS.engine == "auto")
  check("DEFAULTS: search_engine defaults to auto", DEFAULTS.search_engine == "auto")
  check("DEFAULTS: write_changes true", DEFAULTS.write_changes == true)
  check("DEFAULTS: confirm_all true", DEFAULTS.confirm_all == true)
  check("DEFAULTS: history_max_entries == 50", DEFAULTS.history_max_entries == 50)
  check(
    "DEFAULTS: keymaps.replace_and_reopen == <C-r>",
    DEFAULTS.keymaps.replace_and_reopen == "<C-r>"
  )
  check("DEFAULTS: fzf.winopts.width == 0.85", DEFAULTS.fzf.winopts.width == 0.85)
end

--------------------------------------------------------------------------------
-- 2) get(): both top-level fields and nested tables are copied, matching the
--    module's own docstring promise ("returns a deep copy to avoid accidental
--    mutation by callers").
--------------------------------------------------------------------------------
do
  config.setup({})
  local snap = config.get()
  snap.engine = "MUTATED"
  local snap2 = config.get()
  check("get(): top-level scalar fields are copied, not aliased", snap2.engine ~= "MUTATED")

  snap.keymaps.toggle_select = "MUTATED"
  local snap3 = config.get()
  check(
    "get(): nested tables are deep-copied, not aliased to internal state",
    snap3.keymaps.toggle_select ~= "MUTATED",
    snap3.keymaps.toggle_select
  )
end

--------------------------------------------------------------------------------
-- 3) as_bool / pick_bool: numeric/string truthy forms, and "unrecognized
--    value keeps the default" (not just "falsy value keeps the default" --
--    an explicit `false` must NOT be lost, see pick_bool's own guard comment).
--------------------------------------------------------------------------------
do
  local r1 = config.resolve({ write_changes = 0 })
  check("as_bool: 0 -> false", r1.write_changes == false)
  local r2 = config.resolve({ write_changes = "1" })
  check("as_bool: '1' -> true", r2.write_changes == true)
  local r3 = config.resolve({ write_changes = "false" })
  check("as_bool: 'false' string -> false", r3.write_changes == false)
  local r4 = config.resolve({ write_changes = "bogus" })
  check(
    "as_bool: unrecognized value keeps the current default rather than erroring",
    r4.write_changes == DEFAULTS.write_changes
  )
  -- pick_bool's own documented hazard: `false` must never be treated as "unset".
  local base = config.resolve({ confirm_all = false })
  check(
    "pick_bool: explicit false is honored, not coerced to the default",
    base.confirm_all == false
  )
end

--------------------------------------------------------------------------------
-- 4) as_pos_int: integers >= 0 accepted, negative/non-integer rejected
--    (falls back to the current value, not cleared).
--------------------------------------------------------------------------------
do
  local r1 = config.resolve({ preview_context = 7 })
  check("as_pos_int: valid integer accepted", r1.preview_context == 7)
  local r2 = config.resolve({ preview_context = -1 })
  check(
    "as_pos_int: negative value rejected, default kept",
    r2.preview_context == DEFAULTS.preview_context
  )
  local r3 = config.resolve({ preview_context = 2.5 })
  check(
    "as_pos_int: non-integer rejected, default kept",
    r3.preview_context == DEFAULTS.preview_context
  )
  -- 0 is a meaningful, honored value (Lua's `0 or default` is still 0 --
  -- 0 is truthy in Lua, unlike JS/Python -- this is why `as_pos_int(0) or x`
  -- correctly yields 0 rather than falling through to `x`).
  local r4 = config.resolve({ max_file_size = 0 })
  check("as_pos_int: 0 is a valid, honored value", r4.max_file_size == 0)
end

--------------------------------------------------------------------------------
-- 5) as_engine / as_search_engine: case/dash-insensitive normalization
--------------------------------------------------------------------------------
do
  local r1 = config.resolve({ engine = "FZF-LUA" })
  check("as_engine: 'FZF-LUA' normalizes to 'fzf'", r1.engine == "fzf")
  local r2 = config.resolve({ engine = "Telescope" })
  check("as_engine: case-insensitive 'telescope'", r2.engine == "telescope")
  local r3 = config.resolve({ engine = "bogus-engine" })
  check("as_engine: unknown value keeps the default", r3.engine == DEFAULTS.engine)

  local r4 = config.resolve({ search_engine = "RG" })
  check("as_search_engine: 'RG' normalizes to 'ripgrep'", r4.search_engine == "ripgrep")
  local r5 = config.resolve({ search_engine = "Native" })
  check("as_search_engine: 'Native' normalizes to 'vimgrep'", r5.search_engine == "vimgrep")
  local r6 = config.resolve({ search_engine = "carrier-pigeon" })
  check(
    "as_search_engine: unknown value keeps the default",
    r6.search_engine == DEFAULTS.search_engine
  )
end

--------------------------------------------------------------------------------
-- 6) as_progress_style: allow-list, unknown falls back
--------------------------------------------------------------------------------
do
  local r1 = config.resolve({ progress_style = "fidget" })
  check("as_progress_style: valid style accepted", r1.progress_style == "fidget")
  local r2 = config.resolve({ progress_style = "loud" })
  check(
    "as_progress_style: unknown style keeps the default",
    r2.progress_style == DEFAULTS.progress_style
  )
end

--------------------------------------------------------------------------------
-- 7) as_string_list: single string wraps, list filters non-strings/empties,
--    anything else -> empty list.
--------------------------------------------------------------------------------
do
  local r1 = config.resolve({ file_types = "lua" })
  check(
    "as_string_list: bare string wraps into a single-element list",
    #r1.file_types == 1 and r1.file_types[1] == "lua"
  )
  local r2 = config.resolve({ globs = { "*.lua", 5, "", "*.md" } })
  check(
    "as_string_list: non-strings and empties are dropped, order preserved",
    #r2.globs == 2 and r2.globs[1] == "*.lua" and r2.globs[2] == "*.md",
    vim.inspect(r2.globs)
  )
  local r3 = config.resolve({ exclude = "" })
  check('as_string_list: empty string -> empty list, not {""}', #r3.exclude == 0)
  local r4 = config.resolve({ exclude = 42 })
  check("as_string_list: a number input -> empty list", #r4.exclude == 0)
end

--------------------------------------------------------------------------------
-- 8) as_keymaps: per-key override, invalid values keep that key's default
--    (never disables the keymap outright).
--------------------------------------------------------------------------------
do
  local r1 = config.resolve({ keymaps = { toggle_select = "<C-n>" } })
  check(
    "as_keymaps: overriding one key leaves the rest at their defaults",
    r1.keymaps.toggle_select == "<C-n>" and r1.keymaps.quit == DEFAULTS.keymaps.quit
  )

  local r2 = config.resolve({ keymaps = { toggle_select = 5 } })
  check(
    "as_keymaps: a non-string value keeps that key's default",
    r2.keymaps.toggle_select == DEFAULTS.keymaps.toggle_select
  )
  local r3 = config.resolve({ keymaps = { toggle_select = "" } })
  check(
    "as_keymaps: an empty-string value keeps that key's default",
    r3.keymaps.toggle_select == DEFAULTS.keymaps.toggle_select
  )

  -- A typo'd keymaps key (e.g. `toggle_slect`) is a nested unknown key, the
  -- same failure mode sanitize_keys catches at the top level -- one level
  -- deeper. Before the fix it was silently dropped with zero diagnostic and
  -- the intended key silently kept its default (ERR-50). resolve() doesn't
  -- surface issues (see section 13's docstring), so exercise it via setup().
  config.setup({ keymaps = { toggle_slect = "<C-x>" } })
  local issues_km = config.issues()
  check(
    "as_keymaps: an unknown nested key is reported with a dotted-path 'did you mean' hint",
    #issues_km == 1
      and issues_km[1]:find("keymaps.toggle_slect", 1, true) ~= nil
      and issues_km[1]:find("keymaps.toggle_select", 1, true) ~= nil,
    vim.inspect(issues_km)
  )
  check(
    "as_keymaps: the typo'd key never reaches the merged state -- toggle_select keeps its default",
    config.get().keymaps.toggle_select == DEFAULTS.keymaps.toggle_select
  )
  -- restore for hygiene
  config.setup({ keymaps = DEFAULTS.keymaps })
end

--------------------------------------------------------------------------------
-- 9) Nested fzf/telescope tables: shallow-declared, deep-merged over defaults.
--------------------------------------------------------------------------------
do
  local r1 = config.resolve({ fzf = { winopts = { width = 0.5 } } })
  check(
    "fzf: overriding one nested field keeps its sibling default",
    r1.fzf.winopts.width == 0.5 and r1.fzf.winopts.height == DEFAULTS.fzf.winopts.height
  )
  local r2 = config.resolve({ telescope = { layout_config = { width = 0.4 } } })
  check(
    "telescope: overriding one nested field keeps its sibling default",
    r2.telescope.layout_config.width == 0.4
      and r2.telescope.layout_config.height == DEFAULTS.telescope.layout_config.height
  )
end

--------------------------------------------------------------------------------
-- 10) resolve() never mutates the persistent state -- two calls with
--     different partials must not see each other's overrides.
--------------------------------------------------------------------------------
do
  config.setup({ engine = "auto" })
  local before = config.get().engine
  local r1 = config.resolve({ engine = "telescope" })
  check("resolve(): honors its own override", r1.engine == "telescope")
  local after = config.get().engine
  check("resolve(): does not mutate persistent state", after == before, after)
end

--------------------------------------------------------------------------------
-- 11) setup() merges onto the CURRENT state, not back onto DEFAULTS --
--     calling setup({}) is a no-op merge, not a reset to factory defaults.
--     Documented behavior (not a bug): M.resolve()/M.get() are the tools for
--     a one-off override that doesn't persist; setup() is cumulative by
--     design, same as :Replace flags never wanting to force a config reset.
--------------------------------------------------------------------------------
do
  config.setup({ preview_context = 9 })
  check("setup(): override applied", config.get().preview_context == 9)
  config.setup({}) -- would reset to 3 if setup() re-based on DEFAULTS -- it doesn't
  check(
    "setup({}): accumulates onto current state rather than resetting to DEFAULTS",
    config.get().preview_context == 9,
    config.get().preview_context
  )
  -- restore for hygiene, in case any later suite run in the same process cares
  config.setup({ preview_context = DEFAULTS.preview_context })
end

--------------------------------------------------------------------------------
-- 12) hooks/messages: shallow-assigned tables (function-valued leaves), not
--     deep-copied -- a function value survives the round trip unchanged.
--------------------------------------------------------------------------------
do
  local fn = function() end
  local r1 = config.resolve({ hooks = { before_apply = fn } })
  check("hooks: function values pass through resolve() untouched", r1.hooks.before_apply == fn)
  local r2 = config.resolve({ messages = { no_matches = "keine Treffer" } })
  check(
    "messages: string template overrides pass through",
    r2.messages.no_matches == "keine Treffer"
  )
end

--------------------------------------------------------------------------------
-- 13) setup(): unknown top-level keys and invalid single values are
--     dropped/degraded BEFORE the merge (ERR-50) and recorded for
--     issues()/:checkhealth (ERR-22) -- previously both vanished into the
--     defaults with zero diagnostic trace.
--------------------------------------------------------------------------------
do
  config.setup({ smartcase = false }) -- typo for smart_case
  local issues1 = config.issues()
  check(
    "setup(): unknown top-level key is reported with a 'did you mean' hint",
    #issues1 == 1
      and issues1[1]:find("smartcase", 1, true) ~= nil
      and issues1[1]:find("smart_case", 1, true) ~= nil,
    vim.inspect(issues1)
  )
  check(
    "setup(): the typo'd key never reaches the merged state",
    config.get().smart_case == DEFAULTS.smart_case
  )

  config.setup({ engine = "telescpoe" }) -- known key, invalid value
  local issues2 = config.issues()
  check(
    "setup(): a present-but-invalid value is reported too (ERR-22)",
    #issues2 == 1 and issues2[1]:find("engine", 1, true) ~= nil,
    vim.inspect(issues2)
  )
  check("setup(): the invalid engine degrades to the default", config.get().engine == "auto")

  config.setup({ engine = "fzf" })
  check("setup(): a fully valid setup() call reports no issues", #config.issues() == 0)

  -- resolve() intentionally does NOT run the unknown-key check: the command
  -- layer's own override tables carry non-RP_Config keys on purpose
  -- (changed_only, also_rename_file) that would otherwise be flagged as
  -- typos on every single :Replace --changed invocation.
  local r = config.resolve({ changed_only = { "modified" } })
  check("resolve(): non-RP_Config override keys are silently dropped, not flagged", r ~= nil)

  -- restore for hygiene, in case any later suite run in the same process cares
  config.setup({ engine = DEFAULTS.engine, smart_case = DEFAULTS.smart_case })
end

print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
