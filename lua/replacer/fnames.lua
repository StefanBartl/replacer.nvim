---@module 'replacer.fnames'
--- :ReplaceFNames — extend replace to file/directory NAMES (not contents):
--- rename every file/directory under a scope whose basename contains a
--- literal pattern.
---
--- Renames are computed from a single snapshot of the directory tree taken
--- BEFORE anything is touched. When a matching entry is nested inside
--- another matching entry, only the OUTER one is renamed this run (the
--- inner one moves along for free since renaming a directory moves its
--- whole subtree); re-run to catch it on its own if its basename still
--- matches after the move — the same idempotent, skip-and-rerun shape as
--- :Surround's --nested handling.
---
--- Does NOT follow the rename through source references (imports/requires/
--- etc across the project) — out of scope for this module; see
--- --also-rename-file (replacer.rename_assist) for the narrower, single-
--- file "rename the file to match a content replace" case.

local notify = require("replacer.util.notify")

local M = {}

--------------------------------------------------------------------------------
-- Collection
--------------------------------------------------------------------------------

---@class RP_FNameMatch
---@field old_path string
---@field new_path string
---@field is_dir boolean

--- Replace every literal occurrence of `old` in `text` with `new`.
---@param text string
---@param old string
---@param new string
---@return string
local function replace_all_literal(text, old, new)
  if old == "" then return text end
  local parts, i = {}, 1
  while true do
    local s, e = text:find(old, i, true)
    if not s then
      parts[#parts + 1] = text:sub(i)
      break
    end
    parts[#parts + 1] = text:sub(i, s - 1)
    parts[#parts + 1] = new
    i = e + 1
  end
  return table.concat(parts)
end

--- Recursively collect every file/directory path under `root` (root itself
--- excluded — callers add it separately when relevant).
---@param root string
---@param acc { path: string, is_dir: boolean }[]
local function list_all(root, acc)
  local ok, iter = pcall(vim.fs.dir, root, { depth = 32 })
  if not ok or not iter then return end
  for name, typ in iter do
    if typ == "file" or typ == "directory" then
      acc[#acc + 1] = { path = root .. "/" .. name, is_dir = (typ == "directory") }
    end
  end
end

--- Collect rename candidates under `scope` (a file or directory) whose
--- basename contains `pattern` (literal substring match).
---@param pattern string
---@param replacement string
---@param scope string
---@param cfg RP_Config|nil    -- honors hidden / exclude_git_dir like the content search
---@return RP_FNameMatch[]
function M.collect(pattern, replacement, scope, cfg)
  cfg = cfg or {}
  if pattern == "" then return {} end

  local p = vim.fn.fnamemodify(scope, ":p"):gsub("[/\\]+$", "")
  ---@type { path: string, is_dir: boolean }[]
  local entries = {}

  if vim.fn.isdirectory(p) == 1 then
    list_all(p, entries)
  elseif vim.fn.filereadable(p) == 1 then
    entries = { { path = p, is_dir = false } }
  else
    return {}
  end

  ---@type RP_FNameMatch[]
  local matches = {}
  for _, e in ipairs(entries) do
    local name = vim.fn.fnamemodify(e.path, ":t")
    local hidden_excluded = cfg.hidden == false and name:sub(1, 1) == "."
    local git_excluded = cfg.exclude_git_dir ~= false and e.path:find("[/\\]%.git[/\\]") ~= nil
    if not hidden_excluded and not git_excluded and name:find(pattern, 1, true) then
      local dir = vim.fn.fnamemodify(e.path, ":h")
      local new_name = replace_all_literal(name, pattern, replacement)
      if new_name ~= name then
        matches[#matches + 1] = { old_path = e.path, new_path = dir .. "/" .. new_name, is_dir = e.is_dir }
      end
    end
  end
  return matches
end

--- True when `path` is a strict descendant of `ancestor`.
---@param path string
---@param ancestor string
---@return boolean
local function is_descendant_of(path, ancestor)
  return path:sub(1, #ancestor + 1) == (ancestor .. "/")
end

--- Drop any match nested inside another match (see module docstring). The
--- outer rename carries the inner path along for free.
---@param matches RP_FNameMatch[]
---@return RP_FNameMatch[] kept, integer skipped
function M.filter_nested(matches)
  local kept, skipped = {}, 0
  for _, m in ipairs(matches) do
    local nested = false
    for _, other in ipairs(matches) do
      if other ~= m and is_descendant_of(m.old_path, other.old_path) then
        nested = true
        break
      end
    end
    if nested then
      skipped = skipped + 1
    else
      kept[#kept + 1] = m
    end
  end
  return kept, skipped
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

--- Perform the renames. A renamed file's own loaded buffer follows via
--- nvim_buf_set_name; for a renamed directory, every loaded buffer whose
--- path was under the old directory is rewritten to the new prefix.
---@param matches RP_FNameMatch[]
---@return integer renamed, string[] errors
function M.apply(matches)
  -- Deepest-first: a safety net even after filter_nested (e.g. unrelated
  -- same-length siblings), so a rename never operates on a path a previous
  -- rename in this batch already moved.
  table.sort(matches, function(a, b) return #a.old_path > #b.old_path end)

  local renamed = 0
  ---@type string[]
  local errors = {}

  for _, m in ipairs(matches) do
    local uv = vim.uv or vim.loop
    local ok_rename, err = uv.fs_rename(m.old_path, m.new_path)
    if ok_rename then
      renamed = renamed + 1
      if m.is_dir then
        local old_prefix, new_prefix = m.old_path .. "/", m.new_path .. "/"
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          local name = vim.api.nvim_buf_get_name(bufnr)
          if name == m.old_path then
            pcall(vim.api.nvim_buf_set_name, bufnr, m.new_path)
          elseif name:sub(1, #old_prefix) == old_prefix then
            pcall(vim.api.nvim_buf_set_name, bufnr, new_prefix .. name:sub(#old_prefix + 1))
          end
        end
      else
        local bufnr = vim.fn.bufnr(m.old_path)
        if bufnr ~= -1 then pcall(vim.api.nvim_buf_set_name, bufnr, m.new_path) end
      end
    else
      errors[#errors + 1] = string.format("%s -> %s failed (%s)",
        m.old_path, m.new_path, tostring(err))
    end
  end

  return renamed, errors
end

--- Human-readable preview of the planned renames (for --dry).
---@param matches RP_FNameMatch[]
---@return string
function M.build_preview(matches)
  local lines = {}
  for _, m in ipairs(matches) do
    lines[#lines + 1] = string.format("%s  %s -> %s",
      m.is_dir and "[dir] " or "[file]",
      vim.fn.fnamemodify(m.old_path, ":."), vim.fn.fnamemodify(m.new_path, ":."))
  end
  return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- :ReplaceFNames
--------------------------------------------------------------------------------

local USAGE = "Usage: :ReplaceFNames[!] {old} {new} [scope] [--dry]"

--- Register :ReplaceFNames.
---@return nil
function M.register()
  local usercmd = require("lib.nvim.usercmd")
  local command = require("replacer.command")
  local confirm = require("lib.nvim.ui.kit.confirm")

  usercmd.create("ReplaceFNames", function(opts)
    local raw = (type(opts.args) == "string") and opts.args or ""
    local tokens, unterminated = command.tokenize(raw)
    if unterminated then
      notify.error("ReplaceFNames: unterminated quote in argument list.\n" .. USAGE)
      return
    end

    ---@type RP_Request
    local req = {
      old = "", new = "", scope = "",
      all = opts.bang and true or false,
      dry = false, export = nil, line_range = nil,
      overrides = {}, filters = { file_types = {}, globs = {}, exclude = {} },
    }
    local positionals, err = command.apply_tokens(tokens, req)
    if not positionals then
      notify.error("ReplaceFNames: " .. err)
      return
    end
    if #positionals < 2 or #positionals > 3 then
      notify.error(USAGE)
      return
    end
    req.old, req.new = positionals[1], positionals[2]

    local cfg = require("replacer.config").resolve(req.overrides)
    req.scope = (positionals[3] and positionals[3] ~= "") and positionals[3] or cfg.default_scope

    local roots = command.resolve_scope(req.scope)
    local scope_path = roots and roots[1]
    if not scope_path then return end -- resolve_scope already notified

    local matches = M.collect(req.old, req.new, scope_path, cfg)
    local kept, skipped = M.filter_nested(matches)
    if #kept == 0 then
      notify.info("ReplaceFNames: no matching file/directory names found")
      return
    end

    local function do_apply()
      local renamed, errors = M.apply(kept)
      notify.info(string.format(
        "ReplaceFNames: renamed %d %s%s",
        renamed, renamed == 1 and "entry" or "entries",
        skipped > 0
          and string.format(" (%d nested match(es) skipped — re-run to catch them)", skipped)
          or ""))
      for _, e in ipairs(errors) do notify.error("ReplaceFNames: " .. e) end
    end

    if req.dry then
      pcall(function()
        vim.cmd("botright new")
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(M.build_preview(kept), "\n", { plain = true }))
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].swapfile = false
        vim.bo[buf].modifiable = false
        pcall(vim.api.nvim_buf_set_name, buf, "[replacer-fnames-plan]")
      end)
      return
    end

    if req.all then
      do_apply()
      return
    end

    confirm.open({
      question = string.format("Rename %d file/director%s matching '%s' -> '%s'?",
        #kept, #kept == 1 and "y" or "ies", req.old, req.new),
      on_answer = function(yes)
        if yes then do_apply() else notify.info("cancelled") end
      end,
    })
  end, { nargs = "+", bang = true, desc = USAGE })
end

return M
