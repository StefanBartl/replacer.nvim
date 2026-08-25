---@module 'replacer.gitfiles'
--- Changed-files-only mode: resolve the git-modified/staged/untracked file
--- list, backing --changed[=modified,staged,untracked].

local spawn_env = require("lib.nvim.cross.run.env")

local M = {}

---@internal
--- Run a git subcommand and hand its stdout to `cb` as trimmed, non-empty
--- lines.
---
--- Asynchronous. `M.list` fires up to three of these plus a top-level lookup,
--- and all of them used to run through `vim.system(...):wait()` -- four
--- blocking spawns before `--changed` had even started collecting matches,
--- which is itself already asynchronous. Now nothing on that path blocks.
---@param cwd string
---@param args string[]
---@param cb fun(lines: string[], ok: boolean)  invoked on the main loop
---@return nil
local function git_lines(cwd, args, cb)
  local cmd = { "git", "-C", cwd }
  vim.list_extend(cmd, args)

  if not vim.system then
    local ok, out = require("lib.nvim.cross.run_argv").run_blocking_captured(cmd)
    if not ok then
      return cb({}, false)
    end
    return cb(vim.split(out or "", "\n", { trimempty = true }), true)
  end

  vim.system(cmd, spawn_env.apply({ text = true }), function(obj)
    -- vim.system callbacks run off the main loop; the caller goes on to
    -- vim.fn.fnamemodify and notify.
    vim.schedule(function()
      if not obj or obj.code ~= 0 then
        return cb({}, false)
      end
      cb(vim.split(obj.stdout or "", "\n", { trimempty = true }), true)
    end)
  end)
end

---@internal
--- Resolve the git top-level directory containing `start_dir`.
---
--- A plain upward filesystem search rather than `git rev-parse
--- --show-toplevel`: it answers the same question with stat() calls instead of
--- a process spawn. `.git` is matched as directory *and* file, so worktrees and
--- submodules (where it is a gitfile) resolve correctly. git reports
--- forward-slash paths, and the caller compares against normalised prefixes,
--- so the result is normalised here too.
---@param start_dir string
---@return string|nil
local function toplevel(start_dir)
  local found = vim.fs.find(".git", { path = start_dir, upward = true, limit = 1 })
  if not (found and found[1]) then
    return nil
  end
  local dir = vim.fs.dirname(found[1])
  if not dir or dir == "" then
    return nil
  end
  return (dir:gsub("\\", "/"):gsub("/+$", ""))
end

--- List files matching the requested change kinds (subset of "modified",
--- "staged", "untracked") as absolute paths, deduplicated.
---
--- Asynchronous: the result arrives through `on_done`. `top` is nil there when
--- `start_dir` isn't inside a git repository.
---@param start_dir string
---@param kinds string[]
---@param on_done fun(files: string[], top: string|nil)
---@return nil
function M.list(start_dir, kinds, on_done)
  -- `list` is asynchronous and returns nothing: without this guard a caller
  -- still using the old synchronous two-return form gets a bare nil back and
  -- only notices several frames later, where it indexes it. Fail here, at the
  -- call site that is actually wrong.
  if type(on_done) ~= "function" then
    local msg = "replacer.gitfiles.list: on_done must be a function, got " .. type(on_done)
    error(msg, 2)
  end

  local top = toplevel(start_dir)
  if not top then
    return on_done({}, nil)
  end

  local set = {}
  for _, k in ipairs(kinds) do
    set[k] = true
  end

  local rel, seen = {}, {}
  local function add_all(lines)
    for _, l in ipairs(lines) do
      if l ~= "" and not seen[l] then
        seen[l] = true
        rel[#rel + 1] = l
      end
    end
  end

  -- The kind queries are chained rather than run in parallel: `rel` is order
  -- sensitive (it is what the caller's scope filter walks) and three git
  -- invocations against the same repository serialise on the index anyway.
  local steps = {}
  if set.modified then
    steps[#steps + 1] = { "diff", "--name-only" }
  end
  if set.staged then
    steps[#steps + 1] = { "diff", "--staged", "--name-only" }
  end
  if set.untracked then
    steps[#steps + 1] = { "ls-files", "--others", "--exclude-standard" }
  end

  local i = 0
  local function step()
    i = i + 1
    if i > #steps then
      local abs = {}
      for n, r in ipairs(rel) do
        abs[n] = top .. "/" .. r
      end
      on_done(abs, top)
      return
    end
    git_lines(top, steps[i], function(lines)
      add_all(lines)
      step()
    end)
  end
  step()
end

return M
