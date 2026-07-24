---@module 'replacer.root'
--- Monorepo/project root detection: walk up from a starting directory
--- looking for common project markers (.git, package.json, go.mod, …), so
--- :Replace can target "the project" without spelling out a path.
---
--- Two ways to use it:
---   - scope token "root" (command.lua) — synchronous, deterministic: picks
---     the outermost candidate that has .git (the "true" project root),
---     falling back to the nearest marker match. No prompt.
---   - :ReplaceRoot {old} {new} [--flags] (this module) — when detection
---     finds more than one candidate, prompts with vim.ui.select instead of
---     guessing, then runs :Replace with the chosen directory as scope.

local M = {}

---@type string[]
local MARKERS = {
  ".git", ".hg", ".svn",
  "package.json", "go.mod", "Cargo.toml", "pyproject.toml", "setup.py",
  "pom.xml", "build.gradle", "build.gradle.kts",
}

--- Walk up from `start_dir`, collecting every directory containing at least
--- one marker, nearest-first (index 1 = closest to start_dir).
---@param start_dir string
---@return string[] candidates
function M.detect(start_dir)
  local dir = vim.fn.fnamemodify(start_dir, ":p"):gsub("[/\\]+$", "")
  if dir == "" then return {} end

  local candidates, seen = {}, {}
  local guard = 0
  while dir ~= "" and not seen[dir] do
    seen[dir] = true
    guard = guard + 1
    if guard > 200 then break end -- pathological path safety valve

    for _, marker in ipairs(MARKERS) do
      local p = dir .. "/" .. marker
      if vim.fn.isdirectory(p) == 1 or vim.fn.filereadable(p) == 1 then
        candidates[#candidates + 1] = dir
        break
      end
    end

    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then break end
    dir = parent
  end
  return candidates
end

--- Best single guess, without prompting: prefer the outermost candidate
--- that has .git (the conventional "true" project root); otherwise the
--- nearest candidate.
---@param start_dir string
---@return string|nil root, string[] candidates
function M.detect_best(start_dir)
  local candidates = M.detect(start_dir)
  if #candidates == 0 then return nil, candidates end
  for i = #candidates, 1, -1 do
    if vim.fn.isdirectory(candidates[i] .. "/.git") == 1 then
      return candidates[i], candidates
    end
  end
  return candidates[1], candidates
end

--- Resolve a starting directory: the current buffer's directory when it has
--- a file-backed name, else cwd.
---@return string|nil
local function default_start_dir()
  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name ~= "" then
    return vim.fn.fnamemodify(buf_name, ":h")
  end
  local uv = vim.uv or vim.loop
  local ok, cwd = pcall(function() return uv.cwd() end)
  return ok and cwd or nil
end

--- Detect candidates from the current buffer's directory (or cwd) and call
--- `on_pick(chosen)` with the result: nil when nothing was found, the
--- single candidate directly when there is only one, or the user's choice
--- from a vim.ui.select prompt when there is more than one.
---@param on_pick fun(path: string|nil)
function M.pick(on_pick)
  local start_dir = default_start_dir()
  if not start_dir then
    on_pick(nil)
    return
  end
  local candidates = M.detect(start_dir)
  if #candidates == 0 then
    on_pick(nil)
  elseif #candidates == 1 then
    on_pick(candidates[1])
  else
    vim.ui.select(candidates, { prompt = "Multiple project roots found:" }, on_pick)
  end
end

--------------------------------------------------------------------------------
-- :ReplaceRoot
--------------------------------------------------------------------------------

local USAGE = "Usage: :ReplaceRoot[!] {old} {new} [--flags]   (scope is auto-detected)"

--- Register :ReplaceRoot: like :Replace, but the scope is an auto-detected
--- project root instead of a positional argument. Prompts when detection
--- finds more than one candidate.
---@param run_fun fun(request: RP_Request): nil
---@return nil
function M.register(run_fun)
  local usercmd = require("lib.nvim.usercmd")
  local command = require("replacer.command")
  local notify = require("replacer.util.notify")

  usercmd.create("ReplaceRoot", function(opts)
    local raw = (type(opts.args) == "string") and opts.args or ""
    local tokens, unterminated = command.tokenize(raw)
    if unterminated then
      vim.schedule(function()
        notify.error("ReplaceRoot: unterminated quote in argument list.\n" .. USAGE)
      end)
      return
    end

    ---@type RP_Request
    local req = {
      old = "", new = "", scope = "",
      all = opts.bang and true or false,
      dry = false, export = nil, line_range = nil,
      overrides = {},
      filters = { file_types = {}, globs = {}, exclude = {} },
    }

    local positionals, err = command.apply_tokens(tokens, req)
    if not positionals then
      vim.schedule(function() notify.error(err) end)
      return
    end
    if #positionals ~= 2 then
      vim.schedule(function()
        notify.error(string.format(
          "ReplaceRoot: expected {old} {new} — got %d positional value(s).\n%s",
          #positionals, USAGE))
      end)
      return
    end
    req.old, req.new = positionals[1], positionals[2]

    M.pick(function(chosen)
      if not chosen then
        notify.error("ReplaceRoot: no project root markers found (.git, package.json, go.mod, …)")
        return
      end
      req.scope = chosen
      run_fun(req)
    end)
  end, {
    nargs = "+",
    bang = true,
    desc = "Replace with an auto-detected project root as scope: :ReplaceRoot[!] {old} {new} [--flags]",
  })
end

return M
