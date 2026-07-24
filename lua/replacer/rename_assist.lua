---@module 'replacer.rename_assist'
--- --also-rename-file: after a successful single-file content replace,
--- offer to also rename the file itself using the same old->new
--- substitution on its basename. A thin wrapper over replacer.fnames'
--- primitives, deliberately scoped to exactly one file (never a directory
--- tree — that's :ReplaceFNames' job).

local notify = require("replacer.util.notify")

local M = {}

--- If `path`'s basename contains `old` (literal substring), confirm and
--- rename the file — following its own loaded buffer — to the same
--- basename with `old` replaced by `new`. A no-op when the basename
--- doesn't contain `old` at all (most content replaces won't).
---@param path string
---@param old string
---@param new string
---@param cfg RP_Config|nil
---@return nil
function M.maybe_rename(path, old, new, cfg)
  local fnames = require("replacer.fnames")
  local matches = fnames.collect(old, new, path, cfg or {})
  if #matches == 0 then return end
  local m = matches[1]

  local function do_rename()
    local renamed, errors = fnames.apply({ m })
    if renamed == 1 then
      notify.info(string.format("also renamed file: %s -> %s",
        vim.fn.fnamemodify(m.old_path, ":."), vim.fn.fnamemodify(m.new_path, ":.")))
    end
    for _, e in ipairs(errors) do notify.error(e) end
  end

  local choice = vim.fn.confirm(
    string.format("Also rename %s -> %s?",
      vim.fn.fnamemodify(m.old_path, ":t"), vim.fn.fnamemodify(m.new_path, ":t")),
    "&Yes\n&No", 2)
  if choice == 1 then do_rename() end
end

return M
