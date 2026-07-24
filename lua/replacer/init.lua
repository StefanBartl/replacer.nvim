---@module 'replacer'
--- Core orchestration: parse a request, collect matches, then either plan
--- (dry-run / export) or apply (interactive picker / non-interactive ALL).
---
--- Public API:
---   - setup(opts): initialize/override configuration
---   - run(request): execute a replace workflow from a parsed request
---       (also accepts the legacy positional form run(old, new, scope, all))
---
--- Notes:
---   - `setup` delegates to `replacer.config.setup`.
---   - `run` merges per-run flag overrides + filters via `replacer.config.resolve`
---     without mutating global state.

local M = {}

local cfg_mod = require("replacer.config")
local rg = require("replacer.rg")
local apply = require("replacer.apply")
local export = require("replacer.export")
local common = require("replacer.pickers.common")
local cmd_mod = require("replacer.command")
local notify = require("replacer.util.notify")
local confirm = require("lib.nvim.ui.kit.confirm")

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Initialize/override configuration (delegates to replacer.config).
---@param opts RP_Config|table|nil
---@return nil
function M.setup(opts)
  cfg_mod.setup(opts)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Resolve the picker UI engine, honoring "auto" (fzf-lua preferred, else telescope).
---@param cfg RP_Config
---@return "fzf"|"telescope"|nil
local function pick_picker(cfg)
  local e = cfg.engine or "auto"
  if e == "fzf" or e == "telescope" then return e end
  if pcall(require, "fzf-lua") then return "fzf" end
  if pcall(require, "telescope") then return "telescope" end
  return nil
end

--- Append every element of `src` onto `dst` (in place).
---@param dst string[]
---@param src string[]|nil
local function extend(dst, src)
  for i = 1, #(src or {}) do dst[#dst + 1] = src[i] end
end

--- Build the effective per-run config from a request (overrides + filters + range).
---@param request RP_Request
---@return RP_Config
local function effective_cfg(request)
  local cfg = cfg_mod.resolve(request.overrides or {})
  extend(cfg.file_types, request.filters and request.filters.file_types)
  extend(cfg.globs, request.filters and request.filters.globs)
  extend(cfg.exclude, request.filters and request.filters.exclude)
  cfg._line_range = request.line_range
  cfg._old_len = cfg.literal and #request.old or 0
  cfg._changed_only = request.overrides and request.overrides.changed_only
  cfg._also_rename_file = request.overrides and request.overrides.also_rename_file
  return cfg
end

--- Open a read-only scratch split showing diff text.
---@param patch string
local function show_diff_scratch(patch)
  if patch == "" then return end
  pcall(function()
    vim.cmd("botright new")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(patch, "\n", { plain = true }))
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "diff"
    vim.bo[buf].modifiable = false
    pcall(vim.api.nvim_buf_set_name, buf, "[replacer-plan]")
  end)
end

--- Dry-run / export path: compute the plan, report stats, optionally export, preview.
---@param request RP_Request
---@param items RP_Match[]
---@param cfg RP_Config
---@return nil
local function plan(request, items, cfg)
  local results, totals = export.build_results(items, request.new, cfg, request.old)
  notify.info(string.format(
    "dry-run: %d spot(s) in %d file(s)%s — no changes written",
    totals.spots, totals.files,
    totals.skipped > 0 and string.format(" (%d skipped)", totals.skipped) or ""))

  if request.export and request.export ~= "" then
    local ok, err = export.write_export(request.export, results, request.new)
    if ok then
      notify.info("plan exported to " .. request.export)
    else
      notify.error(err or "export failed")
    end
  end

  show_diff_scratch(export.build_patch(results))
end

--- Handle collected matches: plan (dry/export), apply ALL, or open the picker.
---@param request RP_Request
---@param cfg RP_Config
---@param single_file boolean
---@param items RP_Match[]
---@return nil
local function dispatch(request, cfg, single_file, items)
  -- Plan-only path (dry-run / export). Never writes.
  if request.dry or (request.export and request.export ~= "") then
    return plan(request, items, cfg)
  end

  -- Quickfix/loclist export: send the raw match list and open it. Never writes.
  if request.to_quickfix or request.to_loclist then
    export.send_to_quickfix(items, request.to_loclist == true)
    notify.info(string.format(
      "%d match(es) sent to %s", #items, request.to_loclist and "the location list" or "quickfix"))
    return
  end

  -- Applier closure shared by ALL mode, per-file confirm, and the pickers.
  -- Records history for every real apply (never for dry-run/export/
  -- quickfix, which don't reach here); a history-write failure must never
  -- affect the apply itself, hence the pcall.
  local function apply_func(chosen, replacement, write_changes)
    -- Soft LSP integration: try an LSP-driven rename first for eligible
    -- (identifier-shaped) matches; only whatever falls back goes through
    -- the normal plain-text apply below. Guarded so any failure here just
    -- means nothing was LSP-renamed, never a lost edit.
    local lsp_count = 0
    local to_apply = chosen
    if cfg.lsp then
      local ok_lsp, lsp_renamed, fallback = pcall(
        require("replacer.lsp_rename").try_rename_batch, chosen, replacement)
      if ok_lsp and lsp_renamed and fallback then
        lsp_count = #lsp_renamed
        to_apply = fallback
      end
    end

    local files, spots = apply.apply_matches(to_apply, request.old, replacement, write_changes, cfg)
    spots = spots + lsp_count
    pcall(function()
      require("replacer.history").add(request, { files = files, spots = spots })
    end)
    -- --also-rename-file: single-file scope only (never a directory tree —
    -- that's :ReplaceFNames' job). Guarded so a rename-assist failure never
    -- affects the content apply it followed.
    if cfg._also_rename_file and single_file and files > 0 and chosen[1] then
      pcall(function()
        require("replacer.rename_assist").maybe_rename(chosen[1].path, request.old, replacement, cfg)
      end)
    end
    return files, spots
  end

  -- Interactive picker over `pick_items` (auto-detected when engine = "auto").
  -- Shared by the default interactive path and --confirm-per-file's "Only
  -- some" choice, which scopes it to a single file's matches.
  local function open_picker(pick_items)
    local engine = pick_picker(cfg)
    if not engine then
      notify.error("no picker available — install fzf-lua or telescope.nvim")
      return
    end
    if engine == "fzf" then
      require("replacer.pickers.fzf").run(request.old, pick_items, request.new, cfg, apply_func)
    else
      require("replacer.pickers.telescope").run(pick_items, request.new, cfg, apply_func)
    end
  end

  -- Non-interactive ALL.
  if request.all then
    if cfg.checkpoint then
      local ok_cp, id = pcall(function() return require("replacer.checkpoint").create(items) end)
      if ok_cp and id then
        notify.info(string.format("checkpoint '%s' created — :ReplaceUndo to revert", id))
      else
        notify.warn("failed to create a checkpoint — proceeding without one")
      end
    end

    if cfg.confirm_per_file then
      local perfile = require("replacer.perfile")
      local files, spots = perfile.run(items, request.new, cfg.write_changes, apply_func, open_picker)
      common.notify_result(files, spots, cfg)
      return
    end

    local fileset = {}
    for _, it in ipairs(items) do fileset[it.path] = true end
    local filecount = 0
    for _ in pairs(fileset) do filecount = filecount + 1 end

    local wide = (not single_file) and cfg.confirm_wide_scope
    if cfg.confirm_all or wide then
      local messages = require("replacer.messages")
      local msg = messages.fmt(cfg, "confirm_all", #items, filecount)
      confirm.open({
        question = msg,
        on_answer = function(yes)
          if not yes then
            messages.info(cfg, messages.fmt(cfg, "cancelled"))
            return
          end
          local files, spots = apply_func(items, request.new, cfg.write_changes)
          common.notify_result(files, spots, cfg)
        end,
      })
      return
    end

    local files, spots = apply_func(items, request.new, cfg.write_changes)
    common.notify_result(files, spots, cfg)
    return
  end

  open_picker(items)
end

--------------------------------------------------------------------------------
-- Run
--------------------------------------------------------------------------------

--- Execute a replace workflow.
--- Accepts a structured RP_Request, or the legacy positional form
--- run(old, new_text, scope, all) for backward compatibility.
---@param request RP_Request|string
---@param new_text? string
---@param scope? string
---@param all? boolean
---@return nil
function M.run(request, new_text, scope, all)
  if type(request) == "string" then
    request = {
      old = request, new = new_text or "", scope = scope or "",
      all = all and true or false, dry = false, export = nil, line_range = nil,
      overrides = {}, filters = { file_types = {}, globs = {}, exclude = {} },
    }
  end
  ---@cast request RP_Request

  local cfg = effective_cfg(request)

  -- 1) Resolve scope (fall back to configured default when none was given).
  local scope_tok = (request.scope ~= "" and request.scope) or cfg.default_scope
  local roots, single_file = cmd_mod.resolve_scope(scope_tok)
  if not roots or #roots == 0 then
    return -- resolve_scope already notified on edge cases
  end
  ---@cast roots string[]

  -- 1b) --changed: restrict roots to git changed/staged/untracked files,
  -- intersected with the resolved scope (a specific dir/file still narrows
  -- the git file list, it doesn't widen it).
  if cfg._changed_only then
    local gitfiles = require("replacer.gitfiles")
    local start_dir = single_file and vim.fn.fnamemodify(roots[1], ":h") or roots[1]
    local files, top = gitfiles.list(start_dir, cfg._changed_only)
    if not top then
      notify.warn("--changed: not inside a git repository")
      return
    end
    -- git always reports forward-slash paths regardless of OS; normalize
    -- the scope prefix the same way before comparing (fnamemodify keeps
    -- native backslashes on Windows).
    local prefix = vim.fn.fnamemodify(roots[1], ":p"):gsub("\\", "/"):gsub("/+$", "")
    local filtered = {}
    for _, f in ipairs(files) do
      if single_file then
        if f == prefix then filtered[#filtered + 1] = f end
      elseif f == prefix or f:sub(1, #prefix + 1) == prefix .. "/" then
        filtered[#filtered + 1] = f
      end
    end
    if #filtered == 0 then
      notify.info("--changed: no changed files match the current scope")
      return
    end
    roots = filtered
    single_file = false
  end

  -- 2) Collect matches asynchronously (ripgrep is non-blocking; vimgrep is sync),
  --    then 3) dispatch to plan / ALL / picker inside the callback.
  local function on_collected(items, err)
    if err then
      notify.error(require("replacer.error").format(err))
      return
    end
    if not items or #items == 0 then
      local messages = require("replacer.messages")
      messages.info(cfg, messages.fmt(cfg, "no_matches"))
      return
    end
    -- Optional post-collection filter (e.g. :Surround skipping already-wrapped
    -- matches). Applied here so plan/ALL/picker all see the same reduced set.
    if request.filter then
      local kept = vim.tbl_filter(request.filter, items)
      if #kept == 0 then
        notify.info(request.filter_empty_msg or "no matches left after filtering")
        return
      end
      items = kept
    end
    dispatch(request, cfg, single_file, items)
  end

  if cfg.stream then
    -- --stream: incremental ripgrep parsing for smoother, filter-aware
    -- progress as matches are found. The picker itself still only opens
    -- once collection finishes (on_batch is reserved for future live
    -- picker fill) -- see rg.collect_streaming's docstring.
    rg.collect_streaming(request.old, roots, cfg, function(_new_batch) end, on_collected)
  else
    rg.collect_async(request.old, roots, cfg, on_collected)
  end
end

return M
