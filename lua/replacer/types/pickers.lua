---@module 'replacer.types.pickers'

--- CDX: flesh out these picker type annotations

--------------------------------------------------------------------------------
-- common.lua
--------------------------------------------------------------------------------

-- Data Model
---@class RP_Match
---@field id integer
---@field path string
---@field lnum integer   -- 1-based line number
---@field col0 integer   -- 0-based byte column (ripgrep)
---@field old string                     # matched text (never nil)
---@field line string

--------------------------------------------------------------------------------
-- telscope.lua / fzf.lua
--------------------------------------------------------------------------------

--- Highlight settings for the preview groups and the fzf ANSI snippets,
--- as read by `replacer.pickers.utils`. Every field is optional: both
--- readers fall back (`ansi_snippets` to "41"/"32", the group setup to
--- `false` for the two decorations).
---
--- NOTE: nothing calls those two functions today -- see the module note
--- in `pickers/utils.lua`.
---@class RP_HighlightConfig
---@field enabled? boolean        # false or nil disables the group setup entirely
---@field old_bg? string          # background of the ReplacerOld group
---@field old_fg? string          # foreground of the ReplacerOld group
---@field new_fg? string          # foreground of the ReplacerNew group
---@field underline? boolean      # underline ReplacerOld
---@field strikethrough? boolean  # also define ReplacerOldStrikethrough
---@field ansi_old_bg? string     # SGR code for the fzf preview, default "41"
---@field ansi_new_fg? string     # SGR code for the fzf preview, default "32"

---@class RP_ConfigPicker : RP_Config
---@field _old_len integer|nil  -- injected by core for literal highlighting

return {}
