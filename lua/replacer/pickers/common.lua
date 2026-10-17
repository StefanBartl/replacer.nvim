---@module 'replacer.pickers.common'
--- Shared helpers used by both pickers (Telescope / fzf-lua):
--- list display formatting, preview text (with context and the exact target
--- position for highlighting), and uniform result notifications.
---
--- Notes:
---   - We operate on byte indices (Lua's `#` on strings) which matches ripgrep's
---     byte-based columns (`it.col0`). This keeps UTF-8 safe for our purposes.
---   - `preview_lines_with_pos` returns the 0-based row/col where the match starts
---     inside the preview buffer. Pickers decide how to highlight (buf HL vs ANSI).

local encoding = require("replacer.encoding")

local M = {}

--------------------------------------------------------------------------------
-- Result refinement (soft: needs pickers.nvim's `pickers.refine`)
--------------------------------------------------------------------------------

--- A `pickers.refine` handle configured for replacer's match list, or nil
--- when pickers.nvim is not installed. The picker's filter key checks for
--- nil and reports it rather than failing.
---
--- `path` matches against the cwd-relative form shown in the list (so typing
--- `src` filters what the user sees); `content` matches the match line.
---@return table|nil
function M.new_refine()
  local ok, refine = pcall(require, "pickers.refine")
  if not ok then
    return nil
  end
  return refine.new({
    fields = {
      -- Normalized to forward slashes so a `/`-typed term matches on Windows
      -- too, where the display path may carry backslashes.
      path = function(it)
        return (vim.fs.normalize(vim.fn.fnamemodify(it.path, ":.")))
      end,
      content = function(it)
        return it.line
      end,
    },
  })
end

--- Copy of `list` without the entry whose `.id` equals `id`.
---@param list RP_Match[]
---@param id integer
---@return RP_Match[]
function M.without(list, id)
  local out = {}
  for _, it in ipairs(list) do
    if it.id ~= id then
      out[#out + 1] = it
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- Display line for list entries
--------------------------------------------------------------------------------

---@param it RP_Match
---@return string
function M.format_display(it)
  return string.format(
    "%s:%d:%d — %s",
    vim.fn.fnamemodify(it.path, ":."),
    it.lnum,
    it.col0 + 1,
    it.line
  )
end

--------------------------------------------------------------------------------
-- Preview helpers
--------------------------------------------------------------------------------

--- Build preview lines around a match and compute the exact target position
--- (0-based row/col within the returned block) for the caller to highlight.
--- @param it RP_Match
--- @param ctx integer
--- @return string[] lines, integer target_row0, integer target_col0
function M.preview_lines_with_pos(it, ctx)
  -- Read entire file (simple & robust; fast enough for typical preview sizes).
  local ok, fh = pcall(io.open, it.path, "r")
  if not ok or not fh then
    return { "[unreadable]" }, 0, 0
  end
  ---@type string[]
  local file = {}
  for s in fh:lines() do
    if #file == 0 then
      s = encoding.strip_bom(s)
    end
    file[#file + 1] = encoding.strip_cr(s)
  end
  fh:close()

  -- Clamp window to available lines
  local pad = (type(ctx) == "number" and ctx >= 0) and ctx or 2
  local start = math.max(1, it.lnum - pad)
  local stop = math.min(#file, it.lnum + pad)

  ---@type string[]
  local out = {}
  local target_row0, target_col0 = 0, 0

  for i = start, stop do
    local is_hit = (i == it.lnum)
    local mark = is_hit and "▶ " or "  "
    -- Build full preview line
    local content = tostring(file[i] or "")
    local line = string.format("%s%6d  %s", mark, i, content)
    out[#out + 1] = line

    if is_hit then
      -- Compute byte length of the prefix as rendered above*:
      local prefix = mark .. string.format("%6d", i) .. "  "
      -- 0-based row index within the preview block
      target_row0 = (#out - 1)
      -- 0-based col: prefix bytes + original match byte column
      target_col0 = #prefix + (it.col0 or 0)
    end
  end

  return out, target_row0, target_col0
end

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------

--- Uniform success notification. Honors cfg.messages.result / cfg.quiet.
--- @param files integer
--- @param spots integer
--- @param cfg RP_Config|nil
function M.notify_result(files, spots, cfg)
  local messages = require("replacer.messages")
  messages.info(cfg, messages.fmt(cfg, "result", spots, files))
end

--------------------------------------------------------------------------------
-- Session end signal (rstate.on_close)
--------------------------------------------------------------------------------
-- A picker session spans every reopen (replace_and_reopen, fzf's filter) and
-- whatever an action does after the window is gone (the apply, a confirm
-- float). `rstate.on_close`, when set, fires exactly once when all of that is
-- over: --confirm-per-file uses it to go on with the next file only once no
-- picker window and no float of the session is left (UI-53).
--
-- `rstate.busy` means "an action owns the end of the session": the window
-- closing then does not end it, the action does (through `M.session_end`,
-- or by reopening, which clears `busy` again at the start of run()).
--
-- `rstate.gen` counts the picker windows of the session. A close is only
-- heard for the newest one: Telescope wipes the prompt buffer on a later
-- tick (layout:unmount schedules it), so a replace_and_reopen's old window
-- can report its close after the reopened picker is already up.

--- A picker window of the session opens: nothing is pending any more.
---@param rstate table
---@return integer gen  pass to `M.session_closed` for this window
function M.session_open(rstate)
  rstate.busy = false
  rstate.gen = (rstate.gen or 0) + 1
  return rstate.gen
end

--- End the session: fire `rstate.on_close` once, on a later tick so the
--- picker's own close/action code unwinds first.
---@param rstate table
function M.session_end(rstate)
  local cb = rstate.on_close
  if type(cb) ~= "function" or rstate.ended then
    return
  end
  rstate.ended = true
  vim.schedule(cb)
end

--- The picker window `gen` went away. Ends the session unless an action took
--- it over or a newer window of the session is open. Checked on a later
--- tick: fzf-lua closes its window before it runs the action that sets `busy`.
---@param rstate table
---@param gen integer  from `M.session_open` for that window
function M.session_closed(rstate, gen)
  vim.schedule(function()
    if rstate.gen == gen and not rstate.busy then
      M.session_end(rstate)
    end
  end)
end

--- An action takes over the end of the session.
---@param rstate table
function M.session_hold(rstate)
  rstate.busy = true
end

--- `on_result` for an apply started by a picker action: report the result,
--- then end the session.
---@param rstate table
---@param cfg RP_Config|nil
---@return fun(files: integer, spots: integer)
function M.session_result(rstate, cfg)
  return function(files, spots)
    M.notify_result(files, spots, cfg)
    M.session_end(rstate)
  end
end

--------------------------------------------------------------------------------
-- which-key (optional)
--------------------------------------------------------------------------------

--- Register which-key labels for buffer-local picker keymaps. Soft
--- dependency: a no-op if which-key.nvim isn't installed, or if its `add()`
--- API isn't present (older/incompatible versions) — picker keymaps work
--- identically either way, this only adds a hint in which-key's popup.
--- @param bufnr integer
--- @param entries { lhs: string, desc: string, modes?: string[] }[]
function M.register_which_key(bufnr, entries)
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk.add) ~= "function" then
    return
  end

  local spec = {}
  for _, e in ipairs(entries) do
    for _, mode in ipairs(e.modes or { "n" }) do
      spec[#spec + 1] = { e.lhs, desc = e.desc, mode = mode, buffer = bufnr }
    end
  end
  pcall(wk.add, spec)
end

return M
