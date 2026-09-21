---@module 'replacer.gitfiles'
--- Changed-files-only mode: resolve the git-modified/staged/untracked file
--- list, backing --changed[=modified,staged,untracked].

local M = {}

-- The order the kinds are reported in, whatever order the caller listed them.
local KIND_ORDER = { "modified", "staged", "untracked" }

---@internal
--- Which `--changed` kinds one path belongs to, from its two-character XY
--- status code (X = index vs HEAD, Y = working tree vs index).
---
--- This is the same partition the three queries this module used to run
--- (`git diff --name-only`, `git diff --staged --name-only`,
--- `git ls-files --others --exclude-standard`) produced, read off one
--- `git status` instead: staged is "X set", modified is "Y set", untracked is
--- `??`. Ignored paths (`!!`) belong to none. An unmerged path (`UU`, `AA`,
--- `DD`, `AU`, `UA`, `DU`, `UD`) has both columns set, so it lands in both
--- lists, exactly as it shows up in both diffs.
---@param code string
---@return boolean modified
---@return boolean staged
---@return boolean untracked
local function classify(code)
  if code == "??" then
    return false, false, true
  end
  if code == "!!" then
    return false, false, false
  end
  return code:sub(2, 2) ~= " ", code:sub(1, 1) ~= " ", false
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
--- `start_dir` isn't inside a git repository. `failed_kinds` names every
--- requested kind ("modified"/"staged"/"untracked") when the git query itself
--- failed (git missing, locked/corrupt index, permission error) -- distinct
--- from that kind legitimately contributing zero files.
---
--- One `git status` (via `lib.nvim.git.status_porcelain_async`, NUL-separated,
--- so a path with a space or a non-ASCII byte arrives exactly as on disk)
--- answers all requested kinds; the result is the requested kinds in the order
--- modified, staged, untracked, each sorted by path.
---@param start_dir string
---@param kinds string[]
---@param on_done fun(files: string[], top: string|nil, failed_kinds: string[]|nil)
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
  local wanted = {}
  for _, kind in ipairs(KIND_ORDER) do
    if set[kind] then
      wanted[#wanted + 1] = kind
    end
  end
  if #wanted == 0 then
    return on_done({}, top)
  end

  require("lib.nvim.git").status_porcelain_async({ dir = top }, function(map)
    -- ERR-11: an empty result can mean "nothing changed" or "the git query
    -- failed" (git missing, locked/corrupt index, permission error) -- report
    -- the failure so the caller can tell those apart instead of announcing a
    -- silent, possibly-incomplete "no changed files".
    if not map then
      return on_done({}, top, wanted)
    end

    ---@type table<string, string[]>
    local by_kind = { modified = {}, staged = {}, untracked = {} }
    for path, entry in pairs(map) do
      local modified, staged, untracked = classify(entry.code)
      if modified then
        by_kind.modified[#by_kind.modified + 1] = path
      end
      if staged then
        by_kind.staged[#by_kind.staged + 1] = path
      end
      if untracked then
        by_kind.untracked[#by_kind.untracked + 1] = path
      end
    end

    -- `pairs` order is unspecified; the result is order sensitive (it is what
    -- the caller's scope filter walks), so each kind is sorted by path bytes,
    -- which is the order git itself lists them in.
    local abs, seen = {}, {}
    for _, kind in ipairs(wanted) do
      table.sort(by_kind[kind])
      for _, rel in ipairs(by_kind[kind]) do
        if not seen[rel] then
          seen[rel] = true
          abs[#abs + 1] = top .. "/" .. rel
        end
      end
    end
    on_done(abs, top, nil)
  end)
end

return M
