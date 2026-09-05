---@module 'replacer.pickers.telescope'
--- Telescope-based interactive selection with consistent UX:
---   - <CR>: apply multi if present, else single (fixed, Telescope's own default key)
---   - cfg.keymaps.toggle_select / toggle_select_prev: toggle + move (default <Tab>/<S-Tab>)
---   - cfg.keymaps.apply_all: apply ALL (respects cfg.confirm_all; default <C-a>)
---   - cfg.keymaps.replace_and_reopen: apply entry under cursor, reopen with
---     the rest (default <C-r>)
---   - cfg.keymaps.quit: close the picker (default <Esc>)
--- Preview:
---   - Uses common.preview_lines_with_pos to compute exact (row,col)
---   - Highlights the target span via extmarks (hl_group = "ReplacerTarget")
---
--- Notes:
---   - We highlight only when a literal old-length is available (cfg._old_len > 0).
---   - For regex, extend the collector to provide match length/col1 if needed.

local common = require("replacer.pickers.common")
local notify = require("replacer.util.notify")
local confirm = require("lib.nvim.ui.kit.confirm")

--------------------------------------------------------------------------------
-- Implementation
--------------------------------------------------------------------------------

-- Use an extmark namespace for clean highlight management
local NS = vim.api.nvim_create_namespace("replacer_preview")

---@internal
---@param items RP_Match[]
---@param new_text string
---@param cfg RP_Config            -- receives _old_len optionally (we cast below)
---@param apply_func fun(items: RP_Match[], new_text: string, write_changes: boolean): (integer, integer)
---@param rstate? { original: RP_Match[], handle: table|false }  refine state, threaded across reopens
---@return nil
local function run(items, new_text, cfg, apply_func, rstate)
  local ok, _ = pcall(require, "telescope")
  if not ok then
    notify.error("telescope.nvim not found")
    return
  end

  local pickers_ok, pickers = pcall(require, "telescope.pickers")
  local finders_ok, finders = pcall(require, "telescope.finders")
  local previewers_ok, previewers = pcall(require, "telescope.previewers")
  local conf_ok, conf = pcall(require, "telescope.config")
  local actions_ok, actions = pcall(require, "telescope.actions")
  local action_state_ok, action_state = pcall(require, "telescope.actions.state")
  if
    not (pickers_ok and finders_ok and previewers_ok and conf_ok and actions_ok and action_state_ok)
  then
    notify.error("telescope submodules missing")
    return
  end

  -- Let LuaLS know that cfg may carry `_old_len`
  ---@cast cfg RP_ConfigPicker

  -- Refine state, created once and threaded across reopens. `handle` is a
  -- `pickers.refine` handle, or `false` once we have checked and pickers.nvim
  -- is absent. `original` is the full match set the filters run against.
  rstate = rstate or {}
  rstate.original = rstate.original or items
  if rstate.handle == nil then
    rstate.handle = common.new_refine() or false
  end
  local refine_h = rstate.handle or nil

  local base_title = "Select matches"
  local function current_title()
    if refine_h and refine_h:is_active() then
      return refine_h:title(base_title, #items, #rstate.original)
    end
    return base_title
  end

  -- Ensure a visible highlight group; harmless if repeatedly called.
  pcall(vim.api.nvim_set_hl, 0, "ReplacerTarget", { link = "Search" })

  ---@param it RP_Match
  local function entry_maker(it)
    return {
      value = it,
      display = common.format_display(it),
      ordinal = it.path .. " " .. it.line,
    }
  end

  local previewer = previewers.new_buffer_previewer({
    title = "Preview",
    define_preview = function(self, entry)
      ---@cast entry { value: RP_Match }
      local it = entry and entry.value or nil
      if not it then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "[no selection]" })
        return
      end

      local lines, row0, col0 = common.preview_lines_with_pos(it, cfg.preview_context)
      vim.bo[self.state.bufnr].filetype = "" -- neutral to avoid syntax noise
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

      -- Clear previous extmarks & apply fresh highlight if length is known
      vim.api.nvim_buf_clear_namespace(self.state.bufnr, NS, 0, -1)
      local len = tonumber(cfg._old_len or 0) or 0
      if len > 0 and row0 >= 0 and col0 >= 0 then
        -- extmark-based highlight (recommended API). end_col is exclusive.
        pcall(vim.api.nvim_buf_set_extmark, self.state.bufnr, NS, row0, col0, {
          end_col = col0 + len,
          hl_group = "ReplacerTarget",
        })
      end
    end,
  })

  -- Theme/layout options as first argument; picker options as second
  local theme_opts = vim.tbl_deep_extend("force", { multi_icon = "*" }, cfg.telescope or {})

  local picker = pickers.new(theme_opts, {
    prompt_title = current_title(),
    sorter = conf.values.generic_sorter(theme_opts),
    finder = finders.new_table({
      results = items,
      entry_maker = entry_maker,
    }),
    previewer = previewer,

    attach_mappings = function(prompt_bufnr, map)
      local function apply_selected_or_one()
        local sel = action_state.get_selected_entry()
        if not sel then
          return
        end

        local cur_picker = action_state.get_current_picker(prompt_bufnr)
        local multi = (cur_picker and cur_picker:get_multi_selection()) or {}

        if type(multi) == "table" and #multi > 0 then
          ---@type RP_Match[]
          local chosen = {}
          for _, e in ipairs(multi) do
            if e and e.value then
              chosen[#chosen + 1] = e.value
            end
          end
          local files, spots = apply_func(chosen, new_text, cfg.write_changes)
          common.notify_result(files, spots, cfg)
          actions.close(prompt_bufnr)
        else
          if not sel.value then
            return
          end
          ---@cast sel { value: RP_Match }
          local files, spots = apply_func({ sel.value }, new_text, cfg.write_changes)
          common.notify_result(files, spots, cfg)
          actions.close(prompt_bufnr)
        end
      end

      local keys = (cfg.keymaps or {}) --[[@as RP_Keymaps]]

      -- <CR>: multi-aware default action (not user-remappable: Telescope
      -- treats <CR> as its own default select key, replaced in place).
      actions.select_default:replace(apply_selected_or_one)

      -- toggle_select/toggle_select_prev: toggle + move
      local function toggle_next()
        actions.toggle_selection(prompt_bufnr)
        actions.move_selection_next(prompt_bufnr)
      end
      local function toggle_prev()
        actions.toggle_selection(prompt_bufnr)
        actions.move_selection_previous(prompt_bufnr)
      end
      local key_next = keys.toggle_select or "<Tab>"
      local key_prev = keys.toggle_select_prev or "<S-Tab>"
      map("i", key_next, toggle_next)
      map("n", key_next, toggle_next)
      map("i", key_prev, toggle_prev)
      map("n", key_prev, toggle_prev)

      -- apply_all: replace ALL matches with optional confirmation
      local function do_all()
        if cfg.confirm_all then
          local messages = require("replacer.messages")
          local msg = messages.fmt(cfg, "confirm_all_short", #items)
          -- Close the picker before opening the confirm float: leaving it open
          -- underneath a second focus-stealing float corrupts Telescope's
          -- internal picker registry, so closing it afterward (from
          -- on_answer) crashes on a nil picker lookup inside actions.close.
          actions.close(prompt_bufnr)
          confirm.open({
            question = msg,
            on_answer = function(yes)
              if not yes then
                return
              end
              local files, spots = apply_func(items, new_text, cfg.write_changes)
              common.notify_result(files, spots, cfg)
            end,
          })
          return
        end
        local files, spots = apply_func(items, new_text, cfg.write_changes)
        common.notify_result(files, spots, cfg)
        actions.close(prompt_bufnr)
      end
      local key_all = keys.apply_all or "<C-a>"
      map("i", key_all, do_all)
      map("n", key_all, do_all)

      -- replace_and_reopen: apply the entry under cursor, reopen the picker
      -- with the rest. A modifier key by design (see config default) so it
      -- never swallows a character typed into the live query line.
      local function do_reopen()
        local sel = action_state.get_selected_entry()
        if not sel or not sel.value then
          return
        end
        local it = sel.value ---@type RP_Match

        actions.close(prompt_bufnr)

        local files, spots = apply_func({ it }, new_text, cfg.write_changes)
        common.notify_result(files, spots, cfg)

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
        -- Drop the applied match from the full set too, so a later "clear
        -- filters" cannot bring it back.
        rstate.original = common.without(rstate.original, it.id)
        vim.schedule(function()
          run(remaining, new_text, cfg, apply_func, rstate)
        end)
      end
      local key_reopen = keys.replace_and_reopen or "<C-r>"
      map("i", key_reopen, do_reopen)
      map("n", key_reopen, do_reopen)

      -- filter: narrow the list via pickers.refine (stacked path/content
      -- clauses). Refreshes the finder in place — the query line, selection
      -- and preview stay. A modifier key by design, like replace_and_reopen.
      local key_filter = keys.filter or "<C-f>"
      local function do_filter()
        if not refine_h then
          notify.warn("result filtering needs pickers.nvim (pickers.refine) — not installed")
          return
        end
        refine_h:prompt(function()
          local filtered = refine_h:apply(rstate.original)
          items = filtered
          local p = action_state.get_current_picker(prompt_bufnr)
          if not p then
            return
          end
          p:refresh(
            finders.new_table({ results = filtered, entry_maker = entry_maker }),
            { reset_prompt = false }
          )
          pcall(function()
            p.prompt_border:change_title(current_title())
          end)
        end)
      end
      map("i", key_filter, do_filter)
      map("n", key_filter, do_filter)

      -- Double-escape: 1st <Esc> leaves insert -> Telescope normal mode,
      -- 2nd (normal mode, "quit" key) closes the picker.
      local key_quit = keys.quit or "<Esc>"
      map("i", key_quit, function()
        vim.cmd("stopinsert")
      end)
      map("n", key_quit, actions.close)

      common.register_which_key(prompt_bufnr, {
        { lhs = key_next, desc = "replacer: toggle select + next", modes = { "n", "i" } },
        { lhs = key_prev, desc = "replacer: toggle select + previous", modes = { "n", "i" } },
        { lhs = key_all, desc = "replacer: apply to ALL matches", modes = { "n", "i" } },
        {
          lhs = key_reopen,
          desc = "replacer: apply under cursor, reopen with the rest",
          modes = { "n", "i" },
        },
        {
          lhs = key_filter,
          desc = "replacer: filter results (path / content)",
          modes = { "n", "i" },
        },
        { lhs = key_quit, desc = "replacer: close picker", modes = { "n" } },
      })

      return true
    end,
  })

  picker:find()
end

return { run = run }
