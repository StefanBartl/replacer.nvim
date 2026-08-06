---@module 'replacer.gitfiles'
--- Changed-files-only mode: resolve the git-modified/staged/untracked file
--- list, backing --changed[=modified,staged,untracked].

local M = {}

---@internal
--- Run a git subcommand and return its stdout as trimmed, non-empty lines.
---@param cwd string
---@param args string[]
---@return string[] lines, boolean ok
local function git_lines(cwd, args)
  local cmd = { "git", "-C", cwd }
  vim.list_extend(cmd, args)
  if vim.system then
    local obj = vim.system(cmd, { text = true }):wait()
    if not obj or obj.code ~= 0 then
      return {}, false
    end
    return vim.split(obj.stdout or "", "\n", { trimempty = true }), true
  end
  local ok, out = require("lib.nvim.cross.run_argv").run_blocking_captured(cmd)
  if not ok then
    return {}, false
  end
  return vim.split(out or "", "\n", { trimempty = true }), true
end

---@internal
--- Resolve the git top-level directory containing `start_dir`.
---@param start_dir string
---@return string|nil
local function toplevel(start_dir)
  local lines, ok = git_lines(start_dir, { "rev-parse", "--show-toplevel" })
  if not ok or #lines == 0 then
    return nil
  end
  return lines[1]
end

--- List files matching the requested change kinds (subset of "modified",
--- "staged", "untracked") as absolute paths, deduplicated. Returns nil for
--- `top` when `start_dir` isn't inside a git repository.
---@param start_dir string
---@param kinds string[]
---@return string[] files, string|nil top
function M.list(start_dir, kinds)
  local top = toplevel(start_dir)
  if not top then
    return {}, nil
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

  if set.modified then
    add_all((git_lines(top, { "diff", "--name-only" })))
  end
  if set.staged then
    add_all((git_lines(top, { "diff", "--staged", "--name-only" })))
  end
  if set.untracked then
    add_all((git_lines(top, { "ls-files", "--others", "--exclude-standard" })))
  end

  local abs = {}
  for i, r in ipairs(rel) do
    abs[i] = top .. "/" .. r
  end
  return abs, top
end

return M
