-- Headless test for replacer/init.lua's orchestration: the legacy positional
-- run() form, the dry-run/export "plan" path, the interactive picker's
-- "no picker available" fallback, the post-collection `request.filter` hook,
-- the real (non-stubbed-apply) confirm-before-ALL flow, and dispatch's own
-- checkpoint/confirm-per-file wiring (as opposed to the unit-level checks of
-- those two modules already in TESTS/feature_smoke.lua, which drive them
-- with a fake apply_func rather than through replacer.run()).
-- Run:  nvim -l TESTS/init_dispatch.lua
--
-- Every sub-test calls replacer.setup({...}) with every field this file
-- cares about spelled out explicitly (never relying on a prior sub-test's
-- value): replacer.config.setup() merges onto the CURRENT config state
-- rather than resetting to DEFAULTS each call (see TESTS/config_merge.lua),
-- so leaving a field unset here would silently inherit whatever an earlier
-- sub-test left behind.

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
local checkpoint = require("replacer.checkpoint")
local notify = require("replacer.util.notify")

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

local function read_file(path)
  local fh = assert(io.open(path, "r"))
  local c = fh:read("*a")
  fh:close()
  return c
end

---@return RP_Request
local function base_request()
  return {
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
end

--------------------------------------------------------------------------------
-- 1) Legacy positional run(old, new_text, scope, all)
--------------------------------------------------------------------------------
do
  replacer.setup({
    search_engine = "vimgrep",
    confirm_all = false,
    confirm_wide_scope = false,
    confirm_per_file = false,
    checkpoint = false,
    write_changes = true,
  })
  local f = tmp .. "/legacy.txt"
  write_file(f, "legacyold here\n")
  replacer.run("legacyold", "LEGACYNEW", f, true)
  vim.wait(300)
  local c = read_file(f)
  check(
    "run(): legacy positional form (old,new,scope,all) still applies",
    c:match("LEGACYNEW") ~= nil and not c:match("legacyold"),
    c
  )
end

--------------------------------------------------------------------------------
-- 2) Dry-run: plan() never writes, and opens a "[replacer-plan]" diff scratch
--------------------------------------------------------------------------------
do
  replacer.setup({
    search_engine = "vimgrep",
    confirm_all = false,
    confirm_wide_scope = false,
    confirm_per_file = false,
    checkpoint = false,
    write_changes = true,
  })
  local f = tmp .. "/dry.txt"
  write_file(f, "dryword one\ndryword two\n")
  local req = base_request()
  req.old, req.new, req.scope, req.all, req.dry = "dryword", "DRYNEW", f, true, true

  local scratch_before = vim.fn.bufnr("[replacer-plan]")
  replacer.run(req)
  vim.wait(500, function()
    return vim.fn.bufnr("[replacer-plan]") ~= -1
  end, 10)

  check(
    "dry-run: file content is NOT modified",
    read_file(f):match("dryword") ~= nil and not read_file(f):match("DRYNEW"),
    read_file(f)
  )
  local scratch_buf = vim.fn.bufnr("[replacer-plan]")
  check(
    "dry-run: opens a [replacer-plan] scratch buffer",
    scratch_buf ~= -1 and scratch_buf ~= scratch_before
  )
  if scratch_buf ~= -1 then
    check(
      "dry-run: scratch buffer is a read-only nofile/diff buffer",
      vim.bo[scratch_buf].buftype == "nofile"
        and vim.bo[scratch_buf].filetype == "diff"
        and vim.bo[scratch_buf].modifiable == false
    )
    local plan_lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
    local plan_text = table.concat(plan_lines, "\n")
    check(
      "dry-run: patch content mentions the replaced word",
      plan_text:find("dryword", 1, true) ~= nil,
      plan_text
    )
  end
end

--------------------------------------------------------------------------------
-- 3) request.export (no dry flag) still routes through plan(), never applies
--------------------------------------------------------------------------------
do
  replacer.setup({
    search_engine = "vimgrep",
    confirm_all = false,
    confirm_wide_scope = false,
    confirm_per_file = false,
    checkpoint = false,
    write_changes = true,
  })
  local f = tmp .. "/export_only.txt"
  write_file(f, "exportword here\n")
  local out = tmp .. "/export_only.json"
  local req = base_request()
  req.old, req.new, req.scope, req.all = "exportword", "EXPORTNEW", f, true
  req.export = out

  replacer.run(req)
  vim.wait(500, function()
    return vim.fn.filereadable(out) == 1
  end, 10)

  check("export-only: export file was written", vim.fn.filereadable(out) == 1)
  check(
    "export-only: source file was never modified (dry semantics via request.export)",
    read_file(f):match("exportword") ~= nil and not read_file(f):match("EXPORTNEW"),
    read_file(f)
  )
end

--------------------------------------------------------------------------------
-- 4) request.filter: post-collection filter hook, including the
--    "everything got filtered out" empty-result message
--------------------------------------------------------------------------------
do
  replacer.setup({
    search_engine = "vimgrep",
    confirm_all = false,
    confirm_wide_scope = false,
    confirm_per_file = false,
    checkpoint = false,
    write_changes = true,
  })
  local f = tmp .. "/filtered.txt"
  write_file(f, "keepme one\nkeepme two\n")

  -- A filter that only keeps line 1's match: proves `dispatch` really only
  -- sees the filtered set (the surviving line is edited, the dropped one is not).
  local req = base_request()
  req.old, req.new, req.scope, req.all = "keepme", "KEPT", f, true
  req.filter = function(it)
    return it.lnum == 1
  end
  replacer.run(req)
  vim.wait(300)
  local lines = vim.split(read_file(f), "\n", { plain = true })
  check("request.filter: kept match (line 1) was applied", lines[1] == "KEPT one", lines[1])
  check(
    "request.filter: filtered-out match (line 2) was left alone",
    lines[2] == "keepme two",
    lines[2]
  )

  -- A filter that rejects everything -> the documented default message.
  local infos = {}
  local orig_info = notify.info
  notify.info = function(msg)
    infos[#infos + 1] = msg
  end
  local req2 = base_request()
  req2.old, req2.new, req2.scope, req2.all = "KEPT", "X", f, true
  req2.filter = function()
    return false
  end
  replacer.run(req2)
  vim.wait(300)
  notify.info = orig_info
  check(
    "request.filter: filtering out everything reports the default empty message",
    #infos >= 1 and infos[#infos] == "no matches left after filtering",
    vim.inspect(infos)
  )
end

--------------------------------------------------------------------------------
-- 5) Interactive path (request.all=false) with no picker installed:
--    dispatch's pick_picker() finds neither fzf-lua nor telescope.nvim on
--    this runtimepath (only lib.nvim/ui.nvim/pickers.nvim are CI siblings),
--    so engine="auto" must report the documented error instead of hanging
--    or silently doing nothing.
--------------------------------------------------------------------------------
do
  local has_fzf = pcall(require, "fzf-lua")
  local has_telescope = pcall(require, "telescope")
  if has_fzf or has_telescope then
    print("SKIP  no-picker-available test (a real picker backend is on this runtimepath)")
  else
    replacer.setup({
      search_engine = "vimgrep",
      engine = "auto",
      confirm_all = false,
      confirm_wide_scope = false,
      confirm_per_file = false,
      checkpoint = false,
      write_changes = true,
    })
    local f = tmp .. "/nopicker.txt"
    write_file(f, "pickme here\n")
    local errors = {}
    local orig_error = notify.error
    notify.error = function(msg)
      errors[#errors + 1] = msg
    end
    local req = base_request()
    req.old, req.new, req.scope, req.all = "pickme", "X", f, false -- interactive, no --all
    replacer.run(req)
    vim.wait(300)
    notify.error = orig_error
    check(
      "no-picker: reports 'no picker available' instead of hanging or erroring",
      #errors >= 1 and errors[#errors]:find("no picker available", 1, true) ~= nil,
      vim.inspect(errors)
    )
    check(
      "no-picker: file is untouched (never reached an apply)",
      read_file(f):match("pickme") ~= nil
    )
  end
end

--------------------------------------------------------------------------------
-- 6) confirm_all: the REAL confirm.open() -> apply_func flow (as opposed to
--    feature_smoke.lua's perfile-only stubbing) -- both No (cancels, no
--    write) and Yes (applies for real) answers.
--------------------------------------------------------------------------------
do
  local f = tmp .. "/confirm_all.txt"
  write_file(f, "confirmword here\n")

  local answer_with
  package.loaded["ui.kit.confirm"] = {
    open = function(opts)
      opts.on_answer(answer_with)
    end,
  }
  package.loaded["replacer"] = nil
  local replacer_stubbed = require("replacer")

  replacer_stubbed.setup({
    search_engine = "vimgrep",
    engine = "auto",
    confirm_all = true,
    confirm_wide_scope = false,
    confirm_per_file = false,
    checkpoint = false,
    write_changes = true,
  })
  local req_no = base_request()
  req_no.old, req_no.new, req_no.scope, req_no.all = "confirmword", "NO", f, true
  answer_with = false
  replacer_stubbed.run(req_no)
  vim.wait(300)
  check(
    "confirm_all: answering No leaves the file untouched",
    read_file(f):match("confirmword") ~= nil,
    read_file(f)
  )

  local req_yes = base_request()
  req_yes.old, req_yes.new, req_yes.scope, req_yes.all = "confirmword", "YESAPPLIED", f, true
  answer_with = true
  replacer_stubbed.run(req_yes)
  vim.wait(300)
  check(
    "confirm_all: answering Yes actually applies through the real apply_func",
    read_file(f):match("YESAPPLIED") ~= nil,
    read_file(f)
  )

  -- `replacer` (the outer module) is re-fetched once, after section 7 also
  -- resets the stub -- reassigning it here too would just be overwritten
  -- there before ever being read.
  package.loaded["ui.kit.confirm"] = nil
  package.loaded["replacer"] = nil
end

--------------------------------------------------------------------------------
-- 7) confirm_wide_scope vs single-file scope: only a non-single-file scope
--    is gated by confirm_wide_scope; a single explicit file never is, even
--    with confirm_wide_scope=true and confirm_all=false.
--------------------------------------------------------------------------------
do
  local answer_with = true
  local confirm_calls
  package.loaded["ui.kit.confirm"] = {
    open = function(opts)
      confirm_calls = (confirm_calls or 0) + 1
      opts.on_answer(answer_with)
    end,
  }
  package.loaded["replacer"] = nil
  local replacer_stubbed = require("replacer")

  -- Single-file scope: confirm_wide_scope must NOT trigger a confirm.
  local f_single = tmp .. "/wide_single.txt"
  write_file(f_single, "wideword here\n")
  replacer_stubbed.setup({
    search_engine = "vimgrep",
    engine = "auto",
    confirm_all = false,
    confirm_wide_scope = true,
    confirm_per_file = false,
    checkpoint = false,
    write_changes = true,
  })
  confirm_calls = 0
  local req_single = base_request()
  req_single.old, req_single.new, req_single.scope, req_single.all = "wideword", "X", f_single, true
  replacer_stubbed.run(req_single)
  vim.wait(300)
  check(
    "confirm_wide_scope: a single explicit file scope never triggers a confirm",
    confirm_calls == 0 and read_file(f_single):match("X") ~= nil,
    confirm_calls
  )

  -- Directory scope: confirm_wide_scope=true must trigger a confirm.
  local wide_dir = tmp .. "/wide_dir"
  vim.fn.mkdir(wide_dir, "p")
  write_file(wide_dir .. "/a.txt", "wideword2 here\n")
  confirm_calls = 0
  local req_dir = base_request()
  req_dir.old, req_dir.new, req_dir.scope, req_dir.all = "wideword2", "Y", wide_dir, true
  replacer_stubbed.run(req_dir)
  vim.wait(300)
  check(
    "confirm_wide_scope: a directory (non-single-file) scope triggers a confirm",
    confirm_calls == 1 and read_file(wide_dir .. "/a.txt"):match("Y") ~= nil,
    confirm_calls
  )

  package.loaded["ui.kit.confirm"] = nil
  package.loaded["replacer"] = nil
  replacer = require("replacer")
end

--------------------------------------------------------------------------------
-- 8) cfg.checkpoint, wired through dispatch (not called directly like
--    feature_smoke.lua's checkpoint.create()/undo() unit test): a real
--    :Replace! --checkpoint run snapshots the file(s) before applying, and
--    :ReplaceUndo (checkpoint.undo) restores the pre-apply content.
--------------------------------------------------------------------------------
do
  replacer.setup({
    search_engine = "vimgrep",
    engine = "auto",
    confirm_all = false,
    confirm_wide_scope = false,
    confirm_per_file = false,
    checkpoint = true,
    write_changes = true,
  })
  local f = tmp .. "/checkpoint_dispatch.txt"
  local original = "cpword one\ncpword two\n"
  write_file(f, original)

  local infos = {}
  local orig_info = notify.info
  notify.info = function(msg)
    infos[#infos + 1] = msg
  end
  local before_ids = {}
  for _, id in ipairs(checkpoint.list()) do
    before_ids[id] = true
  end

  local req = base_request()
  req.old, req.new, req.scope, req.all = "cpword", "CPNEW", f, true
  replacer.run(req)
  vim.wait(300)
  notify.info = orig_info

  check(
    "cfg.checkpoint: dispatch announces the created checkpoint",
    #infos >= 1 and infos[1]:find("checkpoint '", 1, true) ~= nil,
    vim.inspect(infos)
  )
  check("cfg.checkpoint: the apply itself still happened", read_file(f):match("CPNEW") ~= nil)

  local new_id
  for _, id in ipairs(checkpoint.list()) do
    if not before_ids[id] then
      new_id = id
    end
  end
  check("cfg.checkpoint: a new checkpoint id shows up in checkpoint.list()", new_id ~= nil)

  if new_id then
    local restored = checkpoint.undo(new_id)
    check("cfg.checkpoint: :ReplaceUndo restores the pre-apply content", restored == 1)
    check(
      "cfg.checkpoint: restored content matches byte-exact",
      read_file(f) == original,
      read_file(f)
    )
  end
end

--------------------------------------------------------------------------------
-- 9) cfg.confirm_per_file, wired through dispatch's REAL apply_func (history
--    recording included) -- feature_smoke.lua's own perfile test exercises
--    perfile.run() directly with a fake apply_func; this drives it from
--    replacer.run() so the two are proven to actually agree.
--------------------------------------------------------------------------------
do
  local answers = { "All" }
  local call_n = 0
  package.loaded["ui.kit.confirm"] = {
    open = function(opts)
      call_n = call_n + 1
      opts.on_answer(answers[call_n])
    end,
  }
  package.loaded["replacer"] = nil
  local replacer_stubbed = require("replacer")

  replacer_stubbed.setup({
    search_engine = "vimgrep",
    engine = "auto",
    confirm_all = false,
    confirm_wide_scope = false,
    confirm_per_file = true,
    checkpoint = false,
    write_changes = true,
  })
  local f = tmp .. "/perfile_dispatch.txt"
  write_file(f, "pfword here\n")

  local before = #require("replacer.history").load()
  local req = base_request()
  req.old, req.new, req.scope, req.all = "pfword", "PFNEW", f, true
  replacer_stubbed.run(req)
  vim.wait(300)

  check(
    "confirm_per_file: 'All' answer applies the only file",
    read_file(f):match("PFNEW") ~= nil,
    read_file(f)
  )
  local after = #require("replacer.history").load()
  check(
    "confirm_per_file: dispatch's real apply_func still records history",
    after == before + 1 or (after == 50 and before >= 50)
  )

  -- Last section -- no need to restore the outer `replacer` local, nothing
  -- after this point reads it.
  package.loaded["ui.kit.confirm"] = nil
  package.loaded["replacer"] = nil
end

print(string.format("\n=== %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end
