---@module 'replacer.messages'
--- i18n / message customization: overridable prompt/confirmation text via
--- cfg.messages (a table of string.format templates keyed by message id),
--- plus cfg.quiet to suppress info-level notifications.
---
--- Only routine, "nothing went wrong" chatter is quiet-able (result
--- summaries, "no matches found", "cancelled"). Warnings/errors always
--- show regardless of quiet — they indicate something the user needs to
--- know about, not routine noise.

local notify = require("replacer.util.notify")

local M = {}

---@type table<string, string>
M.DEFAULTS = {
  confirm_all       = "Apply ALL %d spot(s) across %d file(s)?",
  confirm_all_short = "Apply replacement to ALL %d spot(s)?", -- no file count available at the call site
  cancelled         = "cancelled",
  result            = "%d spot(s) in %d file(s)",
  no_matches        = "no matches found",
  surround_prompt   = "Surround with: ",
  surround_cancelled = "Surround: cancelled (no delimiter)",
}

--- Resolve message `key`, formatted with `...`, honoring cfg.messages[key]
--- as a string.format template override. A malformed user template (wrong
--- %-specifiers for the given args) falls back to showing it verbatim
--- rather than erroring.
---@param cfg RP_Config|nil
---@param key string
---@param ... any
---@return string
function M.fmt(cfg, key, ...)
  local template = (cfg and cfg.messages and cfg.messages[key]) or M.DEFAULTS[key] or key
  if select("#", ...) == 0 then return template end
  local ok, result = pcall(string.format, template, ...)
  if ok then return result end
  return template
end

--- Info-level notify, suppressed entirely when cfg.quiet is true.
---@param cfg RP_Config|nil
---@param msg string
---@return nil
function M.info(cfg, msg)
  if cfg and cfg.quiet then return end
  notify.info(msg)
end

return M
