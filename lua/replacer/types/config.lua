---@module 'replacer.types.config'
--------------------------------------------------------------------------------
-- Types (LuaLS)
--------------------------------------------------------------------------------

---@class RP_PickerFzf
---@field winopts table|nil

---@class RP_PickerTelescope
---@field layout_config table|nil

---Buffer-local picker keymaps. All set inside the picker window only.
---@class RP_Keymaps
---@field toggle_select?      string -- multi-select + move to next (default "<Tab>")
---@field toggle_select_prev? string -- multi-select + move to previous (default "<S-Tab>")
---@field apply_all?          string -- replace ALL matches, respects confirm_all (default "<C-a>")
---@field quit?                string -- close the picker (default "<Esc>")

---@class RP_Config
---@field engine?               "fzf"|"telescope"|"auto"  -- picker UI; "auto" -> fzf-lua if present, else telescope
---@field search_engine?        "ripgrep"|"vimgrep"|"auto" -- match collector; "auto" -> ripgrep if present, else vimgrep
---@field progress_style?       "auto"|"notify"|"statusline"|"fidget"|"float"|"kit" -- lib.nvim.progress style (requires lib.nvim; skipped otherwise). "float"/"kit" open a small window; focus it + <Esc> asks to cancel the search ("kit" is themed via lib.nvim.ui.kit)
---@field write_changes?        boolean
---@field confirm_all?          boolean
---@field confirm_wide_scope?   boolean
---@field preview_context?      integer
---@field hidden?               boolean
---@field exclude_git_dir?      boolean
---@field literal?              boolean     -- default search mode (flags may override per-run)
---@field _old_len? 	           number
---@field smart_case?           boolean
---@field default_scope?        string      -- "%", "cwd", ".", or explicit path
---@field file_types?           string[]    -- ripgrep --type values (e.g. { "lua" })
---@field globs?                string[]     -- include glob patterns (e.g. { "*.lua" })
---@field exclude?              string[]     -- exclude path/glob patterns (e.g. { "node_modules" })
---@field fzf?                  RP_PickerFzf|nil
---@field telescope?            RP_PickerTelescope|nil
---@field git_ignore?           boolean
---@field keymaps?              RP_Keymaps
---@field preserve_whitespace?  boolean     -- keep old_text's leading/trailing ws around new_text
---@field case_preserve?        boolean     -- re-case new_text to match each match's case style
---@field word_boundary?        boolean     -- keep only whole-word matches
---@field code_only?            boolean     -- skip matches inside strings/comments (Tree-sitter, best-effort)

---@class ReplacerConfigModule
---@field setup fun(opts:RP_Config|table|nil): nil
---@field get fun(): RP_Config
---@field resolve fun(partial:table|nil): RP_Config

return {}
