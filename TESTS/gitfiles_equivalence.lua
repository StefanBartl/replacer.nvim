-- Headless test for replacer/gitfiles.lua: `--changed` must select exactly the
-- files git itself reports for each kind.
--
-- The oracle is raw git with `-z` (paths arrive unquoted), one command per
-- kind -- the three queries `gitfiles.list` used to run itself:
--   modified   git diff --name-only -z
--   staged     git diff --staged --name-only -z
--   untracked  git ls-files --others --exclude-standard -z
-- The fixture repos cover what an XY status code has to be mapped back onto:
-- unstaged/staged/both, added, deleted (both sides), renamed, untracked in
-- nested and space-named directories, ignored files, non-ASCII and
-- space-containing names, and unmerged (conflicted) paths.
-- Run:  nvim -l TESTS/gitfiles_equivalence.lua

vim.opt.runtimepath:append(vim.fn.getcwd())

-- lib.nvim lives outside this repo; see TESTS/init_dispatch.lua for why this
-- runs first and why it fails the whole suite when the dependency is missing.
local this_file = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local add_lib_nvim = dofile((this_file:match("^(.*)/[^/]+$") or ".") .. "/resolve_lib_nvim.lua")
if not add_lib_nvim() then
  print("FAIL  cannot locate lib.nvim (a runtime dependency of replacer.nvim).")
  print("      Set $LIB_NVIM_PATH, or check it out next to this repo.")
  os.exit(1)
end

if vim.fn.executable("git") ~= 1 then
  -- Not a skip: the suite exists to compare against git, so a machine without
  -- it cannot say anything about the result.
  print("FAIL  git is not on $PATH; this suite compares gitfiles against git itself.")
  os.exit(1)
end

local gitfiles = require("replacer.gitfiles")

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

-- Forward slashes throughout, as gitfiles reports them (tempname() has backslashes on Windows).
local tmp = (vim.fn.tempname():gsub("\\", "/"))
vim.fn.mkdir(tmp, "p")

local function write_file(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fh = assert(io.open(path, "w"))
  fh:write(content)
  fh:close()
end

---@param repo string
---@param args string[]
---@param allow_fail? boolean
---@return string stdout
local function git(repo, args, allow_fail)
  local cmd = { "git", "-C", repo }
  vim.list_extend(cmd, args)
  local res = vim.system(cmd, { text = true }):wait()
  if res.code ~= 0 and not allow_fail then
    error(("git %s failed: %s"):format(table.concat(args, " "), res.stderr or ""))
  end
  return res.stdout or ""
end

local function init_repo(name)
  local repo = tmp .. "/" .. name
  vim.fn.mkdir(repo, "p")
  git(repo, { "init", "-q" })
  git(repo, { "config", "user.email", "test@test.com" })
  git(repo, { "config", "user.name", "test" })
  git(repo, { "config", "core.autocrlf", "false" })
  return repo
end

---Raw `-z` output -> list of repo-relative paths, in git's order.
---@param out string
---@return string[]
local function nul_list(out)
  return vim.split(out, "\0", { plain = true, trimempty = true })
end

local KIND_ARGS = {
  modified = { "diff", "--name-only", "-z" },
  staged = { "diff", "--staged", "--name-only", "-z" },
  untracked = { "ls-files", "--others", "--exclude-standard", "-z" },
}
local KIND_ORDER = { "modified", "staged", "untracked" }

---What the old implementation computed: the requested kinds in the fixed order
---modified, staged, untracked, each in git's order, duplicates dropped, made
---absolute against the repo top-level.
---@param repo string
---@param kinds string[]
---@return string[]
local function oracle(repo, kinds)
  local want = {}
  for _, k in ipairs(kinds) do
    want[k] = true
  end
  local result, seen = {}, {}
  for _, kind in ipairs(KIND_ORDER) do
    if want[kind] then
      for _, rel in ipairs(nul_list(git(repo, KIND_ARGS[kind]))) do
        if not seen[rel] then
          seen[rel] = true
          result[#result + 1] = repo .. "/" .. rel
        end
      end
    end
  end
  return result
end

local function list_sync(dir, kinds)
  local files, top, failed, done
  gitfiles.list(dir, kinds, function(f, t, fk)
    files, top, failed, done = f, t, fk, true
  end)
  if not vim.wait(10000, function()
    return done
  end, 10) then
    error("gitfiles.list did not call back within 10s for " .. vim.inspect(kinds))
  end
  return files, top, failed
end

local KIND_SETS = {
  { "modified" },
  { "staged" },
  { "untracked" },
  { "modified", "staged" },
  { "modified", "untracked" },
  { "staged", "untracked" },
  { "modified", "staged", "untracked" },
}

---@param label string
---@param repo string
local function compare_all_kind_sets(label, repo)
  for _, kinds in ipairs(KIND_SETS) do
    local expected = oracle(repo, kinds)
    local got = list_sync(repo, kinds)
    check(
      ("%s: {%s} selects exactly what git reports"):format(label, table.concat(kinds, ",")),
      vim.deep_equal(got, expected),
      ("got %s, expected %s"):format(vim.inspect(got), vim.inspect(expected))
    )
  end
end

--------------------------------------------------------------------------------
-- Fixture 1: every change shape in one repo
--------------------------------------------------------------------------------
local repo = init_repo("changes")

write_file(repo .. "/.gitignore", "*.log\nbuild/\n")
write_file(repo .. "/keep.txt", "keep\n")
write_file(repo .. "/unstaged.txt", "one\n")
write_file(repo .. "/staged.txt", "one\n")
write_file(repo .. "/both.txt", "one\n")
write_file(repo .. "/gone-worktree.txt", "bye\n")
write_file(repo .. "/gone-index.txt", "bye\n")
write_file(repo .. "/rename-me.txt", "some content that git can match up after a rename\n")
write_file(repo .. "/sp ace.txt", "one\n")
write_file(repo .. "/ü-umlaut.txt", "one\n")
write_file(repo .. "/dir with space/inner.txt", "one\n")
-- Byte order, not locale order: "Z" < "a", and "-" (0x2d) < "/" (0x2f).
write_file(repo .. "/Zeta.txt", "one\n")
write_file(repo .. "/alpha.txt", "one\n")
write_file(repo .. "/dir with space-x.txt", "one\n")
git(repo, { "add", "-A" })
git(repo, { "commit", "-q", "-m", "init" })

-- unstaged modification
write_file(repo .. "/unstaged.txt", "one\ntwo\n")
-- staged modification
write_file(repo .. "/staged.txt", "one\ntwo\n")
git(repo, { "add", "staged.txt" })
-- staged, then modified again
write_file(repo .. "/both.txt", "one\ntwo\n")
git(repo, { "add", "both.txt" })
write_file(repo .. "/both.txt", "one\ntwo\nthree\n")
-- deleted in the working tree only / deleted from the index
os.remove(repo .. "/gone-worktree.txt")
git(repo, { "rm", "-q", "gone-index.txt" })
-- staged rename
git(repo, { "mv", "rename-me.txt", "renamed.txt" })
-- staged new file, and one that is also modified afterwards
write_file(repo .. "/added.txt", "new\n")
git(repo, { "add", "added.txt" })
write_file(repo .. "/added-then-edited.txt", "new\n")
git(repo, { "add", "added-then-edited.txt" })
write_file(repo .. "/added-then-edited.txt", "new\nedited\n")
-- names that git would C-quote without -z
write_file(repo .. "/sp ace.txt", "one\ntwo\n")
write_file(repo .. "/ü-umlaut.txt", "one\ntwo\n")
write_file(repo .. "/dir with space/inner.txt", "one\ntwo\n")
write_file(repo .. "/Zeta.txt", "one\ntwo\n")
write_file(repo .. "/alpha.txt", "one\ntwo\n")
write_file(repo .. "/dir with space-x.txt", "one\ntwo\n")
-- untracked: top level, nested, space-named, non-ASCII; and ignored files
write_file(repo .. "/untracked.txt", "u\n")
write_file(repo .. "/deep/er/nested.txt", "u\n")
write_file(repo .. "/new dir/un tracked.txt", "u\n")
write_file(repo .. "/ünïcode-untracked.txt", "u\n")
write_file(repo .. "/ignored.log", "x\n")
write_file(repo .. "/build/out.txt", "x\n")

compare_all_kind_sets("changes", repo)

do
  local files = list_sync(repo, { "modified", "staged", "untracked" })
  local set = {}
  for _, f in ipairs(files) do
    set[f] = true
  end
  -- Explicit, so a failure names what is missing instead of only "not equal".
  for _, rel in ipairs({
    "unstaged.txt",
    "staged.txt",
    "both.txt",
    "gone-worktree.txt",
    "gone-index.txt",
    "renamed.txt",
    "added.txt",
    "added-then-edited.txt",
    "sp ace.txt",
    "ü-umlaut.txt",
    "dir with space/inner.txt",
    "untracked.txt",
    "deep/er/nested.txt",
    "new dir/un tracked.txt",
    "ünïcode-untracked.txt",
  }) do
    check("changes: lists " .. rel, set[repo .. "/" .. rel] == true)
  end
  for _, rel in ipairs({ "keep.txt", "ignored.log", "build/out.txt", "rename-me.txt" }) do
    check("changes: does not list " .. rel, set[repo .. "/" .. rel] == nil)
  end
end

-- One process for all three kinds (it used to be one per kind).
do
  local spawned = {}
  local original_system = vim.system
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, ...)
    spawned[#spawned + 1] = cmd
    return original_system(cmd, ...)
  end
  local ok, err = pcall(list_sync, repo, { "modified", "staged", "untracked" })
  vim.system = original_system
  check("one git process serves all three kinds: call succeeded", ok, err)
  check(
    "one git process serves all three kinds: exactly one spawn, and it is `git status`",
    #spawned == 1 and vim.tbl_contains(spawned[1], "status"),
    vim.inspect(spawned)
  )
end

-- Started from a subdirectory: still resolves the repo top-level, and the
-- paths are still absolute against it.
do
  local expected = oracle(repo, { "modified", "untracked" })
  local got, top = list_sync(repo .. "/deep/er", { "modified", "untracked" })
  check("changes: from a subdirectory the top-level is the repo root", top == repo, top)
  check("changes: from a subdirectory the list is the same", vim.deep_equal(got, expected))
end

--------------------------------------------------------------------------------
-- Fixture 2: a merge in progress (unmerged paths)
--------------------------------------------------------------------------------
local conflict = init_repo("conflict")
write_file(conflict .. "/both-changed.txt", "base\n")
write_file(conflict .. "/deleted-there.txt", "base\n")
git(conflict, { "add", "-A" })
git(conflict, { "commit", "-q", "-m", "base" })
local base_branch = vim.trim(git(conflict, { "rev-parse", "--abbrev-ref", "HEAD" }))

git(conflict, { "checkout", "-q", "-b", "other" })
write_file(conflict .. "/both-changed.txt", "other\n")
git(conflict, { "rm", "-q", "deleted-there.txt" })
git(conflict, { "commit", "-q", "-am", "other side" })

git(conflict, { "checkout", "-q", base_branch })
write_file(conflict .. "/both-changed.txt", "ours\n")
write_file(conflict .. "/deleted-there.txt", "ours\n")
git(conflict, { "commit", "-q", "-am", "our side" })
git(conflict, { "merge", "other" }, true) -- conflicts; a non-zero exit is the point
write_file(conflict .. "/plain-untracked.txt", "u\n")

compare_all_kind_sets("conflict", conflict)

--------------------------------------------------------------------------------
-- Fixture 3: clean repo, nothing to report
--------------------------------------------------------------------------------
local clean = init_repo("clean")
write_file(clean .. "/a.txt", "a\n")
git(clean, { "add", "-A" })
git(clean, { "commit", "-q", "-m", "init" })
do
  local got, top, failed = list_sync(clean, { "modified", "staged", "untracked" })
  check("clean: no files, top resolved, no failure", #got == 0 and top == clean and failed == nil)
end

--------------------------------------------------------------------------------
-- Edges: no kinds, not a repo, a git query that fails
--------------------------------------------------------------------------------
do
  local got, top, failed = list_sync(repo, {})
  check("no kinds requested -> no files, no failure", #got == 0 and top == repo and failed == nil)
end

do
  local plain = tmp .. "/not-a-repo"
  vim.fn.mkdir(plain, "p")
  local got, top = list_sync(plain, { "modified" })
  check("outside a repository -> nil top, empty list", top == nil and #got == 0)
end

do
  -- An empty `.git` directory satisfies the top-level lookup but is not a
  -- repository: every git query fails, and that must be reported as a failure,
  -- not as "nothing changed".
  local broken = tmp .. "/broken"
  vim.fn.mkdir(broken .. "/.git", "p")
  local got, top, failed = list_sync(broken, { "modified", "staged", "untracked" })
  check("broken repo: top resolved, no files", top == broken and #got == 0, vim.inspect(got))
  check(
    "broken repo: every requested kind is reported as failed",
    vim.deep_equal(failed, { "modified", "staged", "untracked" }),
    vim.inspect(failed)
  )
  local _, _, failed_one = list_sync(broken, { "staged" })
  check(
    "broken repo: only the requested kind is reported",
    vim.deep_equal(failed_one, { "staged" }),
    vim.inspect(failed_one)
  )
end

print(string.format("\n=== %d passed, %d failed ===", pass, fail))
vim.fn.delete(tmp, "rf")
if fail > 0 then
  vim.cmd("cquit 1")
end
