-- Headless test for replacer.pickers.{fzf,telescope}'s real run() logic --
-- candidate/entry building, action-table wiring (default/apply-all/reopen/
-- filter), and the fzf-lua key-notation translator -- with the *actual*
-- picker backend stubbed at package.loaded instead of skipped outright.
-- Run:  nvim -l TESTS/pickers_backends.lua
--
-- Earlier rounds excluded both files entirely: "both run() functions
-- hard-require an actual picker backend (fzf-lua / telescope.nvim)" (see
-- refine_wiring.lua's header and TESTS/README.md). That premise doesn't
-- hold: `pcall(require, "fzf-lua")` / `pcall(require, "telescope")` only
-- need *something* truthy in package.loaded, not a real plugin, and the
-- one call each adapter makes into the actual rendering UI --
-- `fzf.fzf_exec(source, opts)` / `picker:find()` -- is the *last* thing
-- run() does. Everything before it (candidate/entry-maker construction,
-- id-tag mapping, the action closures apply_func actually gets called
-- through, the fzf key-notation translator, the telescope previewer's
-- highlight math) is this plugin's own logic, not telescope's/fzf-lua's,
-- and runs to completion once that one rendering call is replaced with a
-- capture stub -- no live floating window, no real keypress loop, nothing
-- that matches the campaign's "needs a live backend actually rendering"
-- carve-out.
--
-- ui.kit.confirm is stubbed too (answers synchronously via `answer_with`),
-- the same pattern TESTS/init_dispatch.lua's confirm_all section already
-- uses -- so this suite never needs ui.nvim's real confirm surface, only
-- lib.nvim (replacer.util.notify / lib.nvim.bindings.keymap / lib.nvim.window
-- are still real, hard, unstubbed dependencies of pickers/fzf.lua).

vim.opt.runtimepath:append(vim.fn.getcwd())

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

-- Stub ui.kit.confirm BEFORE the adapters are ever require()d: both bind it
-- to a local upvalue at load time (`local confirm = require("ui.kit.confirm")`),
-- so patching the real module's `.open` field afterward would never be seen.
local answer_with
package.loaded["ui.kit.confirm"] = {
  open = function(opts)
    opts.on_answer(answer_with)
  end,
}

-- Deliberately block pickers.refine so every filter action in this suite
-- exercises the "not installed" warning path (common.new_refine() returns
-- nil) -- deterministically, regardless of whether pickers.nvim happens to
-- be on the runtimepath. common.new_refine() re-resolves this via a fresh
-- pcall(require, ...) on every call (not a load-time upvalue), so this can't
-- be set once and forgotten the way ui.kit.confirm above is -- but it also
-- means blocking it here is enough; no per-call re-stubbing needed. Without
-- this, running this suite with pickers.nvim actually on rtp (a real sibling
-- checkout, same as CI's own pickers.nvim job) would make refine_h non-nil,
-- and the filter action would call the real (unstubbed) vim.ui.select,
-- which blocks on stdin forever in headless mode -- refine_wiring.lua is
-- the suite that covers the "present" path, with vim.ui stubbed for it.
package.loaded["pickers.refine"] = nil
package.preload["pickers.refine"] = function()
  error("pickers.refine deliberately blocked in TESTS/pickers_backends.lua")
end

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

local function write_file(path, content)
  local fh = assert(io.open(path, "w"))
  fh:write(content)
  fh:close()
end

--------------------------------------------------------------------------------
-- 1) replacer.pickers.fzf: candidate lines, id mapping, actions wiring
--------------------------------------------------------------------------------
do
  local fzf_calls = {}
  package.loaded["fzf-lua"] = {
    fzf_exec = function(source, opts)
      fzf_calls[#fzf_calls + 1] = { source = source, opts = opts }
    end,
  }
  -- Deliberately NOT stubbing fzf-lua.previewer / .providers.grep / .utils:
  -- their absence is a real scenario (fzf-lua's core module without those
  -- exact submodules on the path) and exercises run()'s own "optional
  -- enhancement missing" fallback (ctor/grep_fn stay nil, last_query stays
  -- unescaped).
  package.loaded["fzf-lua.previewer"] = nil
  package.loaded["fzf-lua.providers.grep"] = nil
  package.loaded["fzf-lua.utils"] = nil

  local fzfp = require("replacer.pickers.fzf")

  local file_a = tmp .. "/a.txt"
  local items = {
    { id = 1, path = file_a, lnum = 1, col0 = 0, old = "foo", line = "foo bar" },
    { id = 2, path = file_a, lnum = 2, col0 = 4, old = "foo", line = "baz foo" },
  }

  local applied = {}
  local function apply_func(chosen, new_text, write_changes, on_result)
    applied[#applied + 1] = { chosen = chosen, new_text = new_text, write_changes = write_changes }
    if on_result then
      on_result(1, #chosen)
    end
  end

  local base_cfg = { keymaps = {}, write_changes = true, literal = true, confirm_all = false }

  fzfp.run("foo", items, "bar", base_cfg, apply_func)
  check("fzf.run: calls fzf_exec exactly once", #fzf_calls == 1, #fzf_calls)

  local call1 = fzf_calls[1]
  check(
    "fzf.run: candidate line carries path:line:col + text",
    call1.source[1]:find(":1:1: foo bar", 1, true) ~= nil,
    call1.source[1]
  )
  check(
    "fzf.run: candidate carries a hidden \\tIDn tag",
    call1.source[1]:find("\tID1", 1, true) ~= nil
      and call1.source[2]:find("\tID2", 1, true) ~= nil,
    vim.inspect(call1.source)
  )
  check(
    "fzf.run: winopts.preview.hidden defaults to false (visible)",
    call1.opts.winopts.preview.hidden == false
  )

  -- default action: single selection resolves through idmap -> apply_func
  call1.opts.actions["default"]({ call1.source[1] })
  check(
    "fzf.actions.default: single selection applies the matching item",
    #applied == 1 and #applied[1].chosen == 1 and applied[1].chosen[1].id == 1,
    vim.inspect(applied)
  )

  -- default action: multi-selection resolves both
  call1.opts.actions["default"]({ call1.source[1], call1.source[2] })
  check(
    "fzf.actions.default: multi-selection applies every matching item",
    #applied == 2 and #applied[2].chosen == 2,
    vim.inspect(applied)
  )

  -- default action: an unresolvable id is silently skipped, no spurious call
  call1.opts.actions["default"]({ "nothing\tIDoes-not-exist" })
  check("fzf.actions.default: unresolvable id -> no apply_func call", #applied == 2)

  -- apply_all ("<C-a>" -> "ctrl-a" via to_fzf_key), confirm_all = false
  check("fzf.actions: ctrl-a key present (to_fzf_key translated <C-a>)", call1.opts.actions["ctrl-a"] ~= nil)
  call1.opts.actions["ctrl-a"]()
  check(
    "fzf.actions.apply_all (confirm_all=false): applies every item directly",
    #applied == 3 and #applied[3].chosen == 2,
    vim.inspect(applied[3])
  )

  -- replace_and_reopen ("<C-r>" -> "ctrl-r"): applies the one item, then
  -- schedules a fresh run() with the rest.
  call1.opts.actions["ctrl-r"]({ call1.source[1] })
  check(
    "fzf.actions.reopen: applies the single selected item",
    #applied == 4 and applied[4].chosen[1].id == 1
  )
  vim.wait(200, function()
    return #fzf_calls >= 2
  end, 10)
  check("fzf.actions.reopen: schedules a fresh fzf_exec call", #fzf_calls == 2, #fzf_calls)
  if #fzf_calls == 2 then
    check(
      "fzf.actions.reopen: the reopened call carries only the remaining item",
      #fzf_calls[2].source == 1 and fzf_calls[2].source[1]:find("\tID2", 1, true) ~= nil,
      vim.inspect(fzf_calls[2].source)
    )
  end
end

--------------------------------------------------------------------------------
-- 2) replacer.pickers.fzf: apply_all with confirm_all = true (real
--    ui.kit.confirm stub, both No and Yes), and the filter guard when
--    pickers.nvim is not on the runtimepath (deliberately not resolved in
--    this suite -- refine_wiring.lua already covers the present case).
--------------------------------------------------------------------------------
do
  local fzf_calls = {}
  package.loaded["fzf-lua"] = {
    fzf_exec = function(source, opts)
      fzf_calls[#fzf_calls + 1] = { source = source, opts = opts }
    end,
  }
  local fzfp = require("replacer.pickers.fzf")

  local items = {
    { id = 1, path = tmp .. "/a.txt", lnum = 1, col0 = 0, old = "foo", line = "foo bar" },
  }
  local applied = {}
  local function apply_func(chosen)
    applied[#applied + 1] = chosen
  end

  fzfp.run("foo", items, "bar", { keymaps = {}, write_changes = true, confirm_all = true }, apply_func)
  local call = fzf_calls[#fzf_calls]

  answer_with = false
  call.opts.actions["ctrl-a"]()
  check("fzf.actions.apply_all (confirm_all=true, answer=No): does not apply", #applied == 0)

  answer_with = true
  call.opts.actions["ctrl-a"]()
  check(
    "fzf.actions.apply_all (confirm_all=true, answer=Yes): applies through the real confirm flow",
    #applied == 1 and #applied[1] == 1
  )

  -- filter: pickers.nvim absent in this suite -> refine_h is nil -> warns
  -- instead of erroring.
  local notify = require("replacer.util.notify")
  local warnings = {}
  local orig_warn = notify.warn
  notify.warn = function(msg)
    warnings[#warnings + 1] = msg
  end
  call.opts.actions["ctrl-f"]()
  notify.warn = orig_warn
  check(
    "fzf.actions.filter: warns (not errors) when pickers.nvim is unavailable",
    #warnings == 1 and warnings[1]:find("pickers.nvim", 1, true) ~= nil,
    vim.inspect(warnings)
  )
end

--------------------------------------------------------------------------------
-- 3) replacer.pickers.fzf: to_fzf_key translation via custom keymaps, and
--    winopts.preview.hidden is preserved (not clobbered) when cfg.fzf sets it.
--------------------------------------------------------------------------------
do
  local fzf_calls = {}
  package.loaded["fzf-lua"] = {
    fzf_exec = function(source, opts)
      fzf_calls[#fzf_calls + 1] = { source = source, opts = opts }
    end,
  }
  local fzfp = require("replacer.pickers.fzf")

  local items = { { id = 1, path = tmp .. "/a.txt", lnum = 1, col0 = 0, old = "x", line = "x" } }
  local cfg = {
    keymaps = { apply_all = "<M-a>", replace_and_reopen = "<CR>" },
    write_changes = true,
    fzf = { winopts = { preview = { hidden = true } } },
  }
  fzfp.run("x", items, "y", cfg, function() end)
  local call = fzf_calls[#fzf_calls]

  check("to_fzf_key: <M-a> -> alt-a", call.opts.actions["alt-a"] ~= nil)
  check(
    "to_fzf_key: bare <CR> hits the 'cr' -> 'enter' special case, not the generic gsub",
    call.opts.actions["enter"] ~= nil
  )
  check(
    "fzf.run: cfg.fzf.winopts.preview.hidden overrides the default (stays true)",
    call.opts.winopts.preview.hidden == true
  )

  -- on_create: real wiring (terminal-mode <Esc>, nice_quit, which-key labels)
  -- against the actual current window/buffer -- no floating window of its
  -- own, so this is safe to run for real rather than stub away.
  local ok_create = pcall(call.opts.winopts.on_create)
  check("fzf.run: winopts.on_create runs against the real current window without error", ok_create)
end

--------------------------------------------------------------------------------
-- 4) replacer.pickers.telescope: entry_maker, previewer highlight math,
--    and every attach_mappings action -- with telescope's own submodules
--    stubbed (this plugin's wiring, not telescope's rendering, is under
--    test) instead of a live floating picker.
--------------------------------------------------------------------------------
do
  local picker_calls = {}
  local action_counts = { closed = 0, toggled = 0, moved_next = 0, moved_prev = 0 }
  local captured_default_action

  package.loaded["telescope"] = {}
  package.loaded["telescope.pickers"] = {
    new = function(_theme_opts, spec)
      local picker_obj = {
        __spec = spec,
        prompt_border = { change_title = function() end },
      }
      picker_obj.find = function(self)
        local maps = {}
        local map = function(mode, key, fn)
          maps[key] = maps[key] or {}
          maps[key][mode] = fn
        end
        spec.attach_mappings(9999, map)
        self.__maps = maps
      end
      picker_calls[#picker_calls + 1] = picker_obj
      return picker_obj
    end,
  }
  package.loaded["telescope.finders"] = {
    new_table = function(o)
      return { __results = o.results, __entry_maker = o.entry_maker }
    end,
  }
  local preview_buf = vim.api.nvim_create_buf(false, true)
  package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function(o)
      return { state = { bufnr = preview_buf }, define_preview = o.define_preview }
    end,
  }
  package.loaded["telescope.config"] = {
    values = {
      generic_sorter = function()
        return {}
      end,
    },
  }
  package.loaded["telescope.actions"] = {
    select_default = {
      replace = function(_, fn)
        captured_default_action = fn
      end,
    },
    close = function()
      action_counts.closed = action_counts.closed + 1
    end,
    toggle_selection = function()
      action_counts.toggled = action_counts.toggled + 1
    end,
    move_selection_next = function()
      action_counts.moved_next = action_counts.moved_next + 1
    end,
    move_selection_previous = function()
      action_counts.moved_prev = action_counts.moved_prev + 1
    end,
  }
  local fake_selected_entry, fake_current_picker
  package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
      return fake_selected_entry
    end,
    get_current_picker = function()
      return fake_current_picker
    end,
  }

  local telescopep = require("replacer.pickers.telescope")

  local preview_file = tmp .. "/preview.txt"
  write_file(preview_file, "line 1\nline 2\nline 3\n")

  local item1 = { id = 1, path = preview_file, lnum = 2, col0 = 0, old = "line", line = "line 2" }
  local item2 = { id = 2, path = preview_file, lnum = 3, col0 = 0, old = "line", line = "line 3" }
  local items = { item1, item2 }

  local applied = {}
  local function apply_func(chosen)
    applied[#applied + 1] = chosen
  end

  telescopep.run(items, "new", { keymaps = {}, write_changes = true, _old_len = 4 }, apply_func)
  check("telescope.run: creates exactly one picker", #picker_calls == 1, #picker_calls)
  local p1 = picker_calls[1]

  -- entry_maker
  local entry = p1.__spec.finder.__entry_maker(item1)
  check(
    "telescope.entry_maker: display/ordinal/value are populated",
    entry.value == item1
      and entry.display:find("line 2", 1, true) ~= nil
      and entry.ordinal:find(item1.path, 1, true) ~= nil,
    vim.inspect(entry)
  )

  -- previewer: no selection
  local prev = p1.__spec.previewer
  prev.define_preview(prev, nil)
  local lines_nosel = vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false)
  check(
    "telescope.previewer: no selection -> '[no selection]'",
    lines_nosel[1] == "[no selection]"
  )

  -- previewer: real selection, cfg._old_len > 0 -> extmark highlight
  local pns = vim.api.nvim_create_namespace("replacer_preview")
  prev.define_preview(prev, { value = item1 })
  local marks = vim.api.nvim_buf_get_extmarks(preview_buf, pns, 0, -1, {})
  check(
    "telescope.previewer: cfg._old_len > 0 -> highlight extmark is set",
    #marks == 1,
    vim.inspect(marks)
  )

  -- apply_selected_or_one: no selection -> no-op
  fake_selected_entry = nil
  captured_default_action()
  check("telescope.apply_selected_or_one: nil selection -> no apply_func call", #applied == 0)

  -- apply_selected_or_one: single selection (empty multi-selection)
  fake_selected_entry = { value = item1 }
  fake_current_picker = {
    get_multi_selection = function()
      return {}
    end,
  }
  captured_default_action()
  check(
    "telescope.apply_selected_or_one: single selection applies exactly that item",
    #applied == 1 and #applied[1] == 1 and applied[1][1].id == 1,
    vim.inspect(applied)
  )

  -- apply_selected_or_one: multi-selection applies every selected entry
  fake_current_picker = {
    get_multi_selection = function()
      return { { value = item1 }, { value = item2 } }
    end,
  }
  captured_default_action()
  check(
    "telescope.apply_selected_or_one: multi-selection applies every selected item",
    #applied == 2 and #applied[2] == 2,
    vim.inspect(applied[2])
  )

  -- toggle_select / toggle_select_prev (default <Tab>/<S-Tab>)
  p1.__maps["<Tab>"]["i"]()
  check(
    "telescope.toggle_select: toggles and moves to next",
    action_counts.toggled == 1 and action_counts.moved_next == 1
  )
  p1.__maps["<S-Tab>"]["i"]()
  check(
    "telescope.toggle_select_prev: toggles and moves to previous",
    action_counts.toggled == 2 and action_counts.moved_prev == 1
  )

  -- apply_all (<C-a>): confirm_all falsy -> applies directly
  p1.__maps["<C-a>"]["i"]()
  check(
    "telescope.apply_all (confirm_all unset): applies every item directly",
    #applied == 3 and #applied[3] == 2
  )

  -- filter (<C-f>): pickers.nvim absent in this suite -> warns
  local notify = require("replacer.util.notify")
  local warnings = {}
  local orig_warn = notify.warn
  notify.warn = function(msg)
    warnings[#warnings + 1] = msg
  end
  p1.__maps["<C-f>"]["i"]()
  notify.warn = orig_warn
  check(
    "telescope.filter: warns (not errors) when pickers.nvim is unavailable",
    #warnings == 1 and warnings[1]:find("pickers.nvim", 1, true) ~= nil,
    vim.inspect(warnings)
  )

  -- replace_and_reopen (<C-r>): applies the selected item, then schedules a
  -- fresh run() (a fresh picker) with the rest.
  fake_selected_entry = { value = item1 }
  p1.__maps["<C-r>"]["i"]()
  check(
    "telescope.replace_and_reopen: applies the single selected item",
    #applied == 4 and #applied[4] == 1 and applied[4][1].id == 1
  )
  vim.wait(200, function()
    return #picker_calls >= 2
  end, 10)
  check("telescope.replace_and_reopen: schedules a fresh picker", #picker_calls == 2, #picker_calls)
  if #picker_calls == 2 then
    check(
      "telescope.replace_and_reopen: the reopened picker carries only the remaining item",
      #picker_calls[2].__spec.finder.__results == 1
        and picker_calls[2].__spec.finder.__results[1].id == 2,
      vim.inspect(picker_calls[2].__spec.finder.__results)
    )
  end
end

--------------------------------------------------------------------------------
-- 5) replacer.pickers.telescope: apply_all with confirm_all = true (the
--    real ui.kit.confirm stub, both No and Yes) -- isolated from section 4
--    so its picker/action counters stay simple.
--------------------------------------------------------------------------------
do
  local picker_calls = {}
  package.loaded["telescope"] = {}
  package.loaded["telescope.pickers"] = {
    new = function(_theme_opts, spec)
      local picker_obj = { __spec = spec, prompt_border = { change_title = function() end } }
      picker_obj.find = function(self)
        local maps = {}
        spec.attach_mappings(9999, function(mode, key, fn)
          maps[key] = maps[key] or {}
          maps[key][mode] = fn
        end)
        self.__maps = maps
      end
      picker_calls[#picker_calls + 1] = picker_obj
      return picker_obj
    end,
  }
  package.loaded["telescope.finders"] = {
    new_table = function(o)
      return { __results = o.results, __entry_maker = o.entry_maker }
    end,
  }
  package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function(o)
      return { state = { bufnr = vim.api.nvim_create_buf(false, true) }, define_preview = o.define_preview }
    end,
  }
  package.loaded["telescope.config"] = {
    values = {
      generic_sorter = function()
        return {}
      end,
    },
  }
  package.loaded["telescope.actions"] = {
    select_default = { replace = function() end },
    close = function() end,
    toggle_selection = function() end,
    move_selection_next = function() end,
    move_selection_previous = function() end,
  }
  package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
      return nil
    end,
    get_current_picker = function()
      return nil
    end,
  }

  -- Already require()d in section 4 -- run() re-resolves telescope.pickers
  -- etc. via pcall(require, ...) on every call, so the fresh stubs set above
  -- take effect without needing to reload this module itself.
  local telescopep = require("replacer.pickers.telescope")

  local items = { { id = 1, path = tmp .. "/a.txt", lnum = 1, col0 = 0, old = "x", line = "x" } }
  local applied = {}
  telescopep.run(items, "y", { keymaps = {}, write_changes = true, confirm_all = true }, function(chosen)
    applied[#applied + 1] = chosen
  end)
  local p1 = picker_calls[1]

  answer_with = false
  p1.__maps["<C-a>"]["i"]()
  check("telescope.apply_all (confirm_all=true, answer=No): does not apply", #applied == 0)

  answer_with = true
  p1.__maps["<C-a>"]["i"]()
  check(
    "telescope.apply_all (confirm_all=true, answer=Yes): applies through the real confirm flow",
    #applied == 1 and #applied[1] == 1
  )
end

print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
