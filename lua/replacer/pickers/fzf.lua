---@module 'replacer.pickers.fzf'
--- fzf-lua picker using the official builtin previewer:
---  - Pass buffer_or_file ctor + grep hints so previewer highlights FULL span.
---
--- Keys:
---  - <CR>                        apply multi if present, else single (fixed, fzf's own default)
---  - cfg.keymaps.toggle_select / toggle_select_prev: multi-select (default <Tab>/<S-Tab>, marker "*")
---  - cfg.keymaps.apply_all       apply ALL (respects cfg.confirm_all; default <C-a>)
---  - cfg.keymaps.quit            close the picker (default <Esc>, after leaving terminal-insert)
---  - cfg.keymaps.replace_and_reopen  apply the entry under cursor, reopen with the
---                                    rest (default <C-r>)

local common = require("replacer.pickers.common")
local notify = require("replacer.util.notify")
local confirm = require("lib.nvim.ui.kit.confirm")
local map = require("lib.nvim.bindings.keymap")
local window = require("lib.nvim.window")

---@internal
--- Translate a Neovim-style key notation ("<C-a>", "<Tab>", "<S-Tab>", "<Esc>")
--- into fzf's own `--bind`/actions-table key spec ("ctrl-a", "tab", "shift-tab", "esc").
--- Covers the modifiers replacer's default keymaps actually use; unrecognized
--- input is lowercased as a best-effort fallback rather than erroring.
---@param nvim_key string
---@return string
local function to_fzf_key(nvim_key)
  local s = tostring(nvim_key or ""):gsub("^<", ""):gsub(">$", "")
  s = s:gsub("[Cc]%-", "ctrl-"):gsub("[Ss]%-", "shift-"):gsub("[MmAa]%-", "alt-")
  s = s:lower()
  if s == "cr" then
    return "enter"
  end
  return s
end

---@internal
---@param old string
---@param items RP_Match[]
---@param new_text string
---@param cfg RP_Config            -- expects: literal, write_changes, fzf?, _last_query?
---@param apply_func fun(items: RP_Match[], new_text: string, write_changes: boolean, on_result?: fun(files: integer, spots: integer))
---@param rstate? { original: RP_Match[], handle: table|false }  refine state, threaded across reopens
local function run(old, items, new_text, cfg, apply_func, rstate)
  local ok_fzf, fzf = pcall(require, "fzf-lua")
  if not ok_fzf then
    notify.error("fzf-lua not found")
    return
  end

  rstate = rstate or {}
  rstate.original = rstate.original or items
  if rstate.handle == nil then
    rstate.handle = common.new_refine() or false
  end
  local refine_h = rstate.handle or nil

  local base_title = "Select matches"
  local function current_prompt()
    if refine_h and refine_h:is_active() then
      return refine_h:title(base_title, #items, #rstate.original) .. "> "
    end
    return base_title .. "> "
  end

  local last_query = tostring(old or "")

  -- Build candidates in "file:line:col: text\tIDxx"
  local source, idmap = {}, {}
  for i = 1, #items do
    local it = items[i] --[[@as RP_Match]]
    local rel = vim.fn.fnamemodify(it.path, ":.")
    local visible = string.format("%s:%d:%d: %s", rel, it.lnum, it.col0 + 1, it.line)
    local hidden = string.format("ID%d", it.id)
    source[#source + 1] = visible .. "\t" .. hidden
    idmap[hidden] = it
  end

  -- Official previewer ctor (do NOT call it; pass the ctor function)
  local ctor
  do
    local ok_prev, Previewer = pcall(require, "fzf-lua.previewer")
    if ok_prev and Previewer and Previewer.builtin and Previewer.builtin.buffer_or_file then
      ctor = Previewer.builtin.buffer_or_file
    end
  end

  -- Grep provider + last_query so previewer can highlight full span.
  -- OPTIONAL enhancement: if the provider is unavailable the picker still works,
  -- only the full-span preview highlight is skipped. Hence the failure is ignored
  -- on purpose (not a swallowed error).
  local grep_fn
  local ok_grep = pcall(function()
    grep_fn = require("fzf-lua.providers.grep").grep
  end)
  if not ok_grep then
    grep_fn = nil
  end
  local ok_utils, utils = pcall(require, "fzf-lua.utils")
  if ok_utils and utils and (cfg.literal ~= false) then
    last_query = utils.rg_escape(last_query)
  end

  local keys = (cfg.keymaps or {}) --[[@as RP_Keymaps]]
  local key_all = to_fzf_key(keys.apply_all or "<C-a>")
  local key_next = to_fzf_key(keys.toggle_select or "<Tab>")
  local key_prev = to_fzf_key(keys.toggle_select_prev or "<S-Tab>")
  local key_reopen = to_fzf_key(keys.replace_and_reopen or "r")
  local key_filter = to_fzf_key(keys.filter or "<C-f>")

  local actions = {
    ["default"] = function(selected)
      if not selected or #selected == 0 then
        return
      end
      local chosen = {} ---@type RP_Match[]
      for _, line in ipairs(selected) do
        local s = type(line) == "table" and line[1] or line
        local id = (type(s) == "string") and s:match("\t(ID%d+)$") or nil
        local it = id and idmap[id] or nil
        if it then
          chosen[#chosen + 1] = it
        end
      end
      if #chosen == 0 then
        return
      end
      apply_func(chosen, new_text, cfg.write_changes, function(files, spots)
        common.notify_result(files, spots, cfg)
      end)
    end,
    [key_all] = function()
      local all = {} ---@type RP_Match[]
      for _, s in ipairs(source) do
        local id = s:match("\t(ID%d+)$")
        local it = id and idmap[id] or nil
        if it then
          all[#all + 1] = it
        end
      end
      if #all == 0 then
        return
      end
      if cfg.confirm_all then
        local messages = require("replacer.messages")
        local fileset = {}
        for _, it in ipairs(all) do
          fileset[it.path] = true
        end
        local fc = 0
        for _ in pairs(fileset) do
          fc = fc + 1
        end
        confirm.open({
          question = messages.fmt(cfg, "confirm_all", #all, fc),
          on_answer = function(yes)
            if not yes then
              messages.info(cfg, messages.fmt(cfg, "cancelled"))
              return
            end
            apply_func(all, new_text, cfg.write_changes, function(files, spots)
              common.notify_result(files, spots, cfg)
            end)
          end,
        })
        return
      end
      apply_func(all, new_text, cfg.write_changes, function(files, spots)
        common.notify_result(files, spots, cfg)
      end)
    end,
    [key_reopen] = function(selected)
      if not selected or #selected == 0 then
        return
      end
      local s = type(selected[1]) == "table" and selected[1][1] or selected[1]
      local id = (type(s) == "string") and s:match("\t(ID%d+)$") or nil
      local it = id and idmap[id] or nil
      if not it then
        return
      end

      apply_func({ it }, new_text, cfg.write_changes, function(files, spots)
        common.notify_result(files, spots, cfg)
      end)

      local remaining = {} ---@type RP_Match[]
      for _, other in ipairs(items) do
        if other.id ~= it.id then
          remaining[#remaining + 1] = other
        end
      end
      if #remaining == 0 then
        notify.info("no more matches")
        return
      end
      rstate.original = common.without(rstate.original, it.id)
      -- Reopen after this picker instance finishes closing.
      vim.schedule(function()
        run(old, remaining, new_text, cfg, apply_func, rstate)
      end)
    end,
    [key_filter] = function()
      if not refine_h then
        notify.warn("result filtering needs pickers.nvim (pickers.refine) — not installed")
        return
      end
      -- fzf-lua has already closed the picker window by the time an action
      -- runs, so reopen unconditionally (on_done) — with the current filtered
      -- view, which is unchanged when the prompt was cancelled.
      refine_h:prompt(nil, function()
        local filtered = refine_h:apply(rstate.original)
        vim.schedule(function()
          run(old, filtered, new_text, cfg, apply_func, rstate)
        end)
      end)
    end,
  }

  local base = {
    prompt = current_prompt(),
    fzf_opts = {
      ["--multi"] = true,
      ["--with-nth"] = "1",
      ["--delimiter"] = "\t",
      ["--no-mouse"] = true,
      ["--marker"] = "*",
      -- fzf's own default already toggles on tab/shift-tab; this bind is a
      -- no-op in that common case and only matters when the keys are remapped.
      ["--bind"] = string.format("%s:toggle+down,%s:toggle+up", key_next, key_prev),
    },
    actions = actions,
  }
  local opts = vim.tbl_deep_extend("force", base, cfg.fzf or {})

  -- Ensure preview is visible unless user explicitly hid it
  opts.winopts = opts.winopts or {}
  opts.winopts.preview = opts.winopts.preview or {}
  if opts.winopts.preview.hidden == nil then
    opts.winopts.preview.hidden = false
  end

  -- Double-escape: fzf runs in a terminal, so the analog of "normal mode" is
  -- terminal-normal mode. 1st <Esc> leaves terminal-insert (<C-\><C-n>) — this
  -- step is the standard Vim terminal-mode convention, not part of "quit", so
  -- it stays fixed even when cfg.keymaps.quit is remapped. The quit key itself
  -- (now in normal mode) closes the picker window.
  do
    local key_quit = keys.quit or "<Esc>"
    local prev_on_create = opts.winopts.on_create
    opts.winopts.on_create = function(...)
      if type(prev_on_create) == "function" then
        pcall(prev_on_create, ...)
      end
      local buf = vim.api.nvim_get_current_buf()
      local win = vim.api.nvim_get_current_win()
      pcall(function()
        map("t", "<Esc>", [[<C-\><C-n>]], { buffer = buf, nowait = true, silent = true })
      end)
      window.nice_quit(win, { keys = { key_quit }, force = true })

      -- Only "quit" is a real Neovim keymap which-key can see: toggle_select
      -- and apply_all are fzf's own terminal-native bindings (--bind/actions
      -- table), consumed by the fzf binary before Neovim's keymap layer ever
      -- sees them, so which-key cannot label those two.
      common.register_which_key(buf, {
        { lhs = key_quit, desc = "replacer: close picker", modes = { "n" } },
      })
    end
  end

  -- Wire official previewer + grep hints (full-span highlight)
  if ctor and grep_fn and last_query ~= "" then
    opts.previewer = { _ctor = ctor }
    opts.__ACT_TO = grep_fn
    opts._last_query = last_query
  end

  fzf.fzf_exec(source, opts)
end

return { run = run }
