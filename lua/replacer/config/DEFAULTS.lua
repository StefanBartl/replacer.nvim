---@module 'replacer.config.DEFAULTS'
--- Pure default values for replacer's runtime config. No logic here — see
--- `replacer.config` for validation/merging.

---@type RP_Config
return {
  -- Picker UI: "auto" picks fzf-lua if present, else telescope.
  engine = "auto",
  -- Search backend: "auto" picks ripgrep when available, else vimgrep (native).
  search_engine = "auto",
  -- Progress indicator style (requires lib.nvim; silently skipped otherwise):
  -- "auto" | "notify" | "statusline" | "fidget" | "float" | "kit". See lib.nvim.progress.
  progress_style = "auto",

  write_changes = true,
  confirm_all = true,
  confirm_wide_scope = false,
  preview_context = 3,
  hidden = true,
  exclude_git_dir = true,
  literal = true,
  smart_case = true,
  default_scope = "%",
  -- When true, a match's own leading/trailing whitespace (relevant with regex
  -- patterns like `\s*foo\s*`) is preserved around the replacement instead of
  -- being clobbered by it.
  preserve_whitespace = false,
  -- When true, re-case the replacement to match each match's own case style:
  -- foo->bar, Foo->Bar, FOO->BAR, fooBar->bazQux, FooBar->BazQux.
  case_preserve = false,
  -- When true, only whole-word matches are kept (the byte before/after the
  -- match must not be a word byte: letter/digit/underscore).
  word_boundary = false,
  -- When true, matches falling inside a string/comment Tree-sitter node are
  -- skipped (best-effort; falls back to keeping everything when no parser
  -- is available for the file's language). See lua/replacer/tscode.lua.
  code_only = false,
  -- Safe-mode: skip read-only / oversized / binary files instead of
  -- touching them. Off by default; max_file_size/skip_binary only take
  -- effect once safe_mode is enabled.
  safe_mode = false,
  max_file_size = 5 * 1024 * 1024, -- 5 MiB
  skip_binary = true,
  -- ALL-mode: ask All/Skip/Only-some/Quit per file instead of one global
  -- "apply ALL?" confirmation. Supersedes confirm_all/confirm_wide_scope
  -- when enabled.
  confirm_per_file = false,
  -- ALL-mode: snapshot every about-to-be-touched file before applying, so
  -- :ReplaceUndo can restore them. See lua/replacer/checkpoint.lua.
  checkpoint = false,
  -- Lua before/after callbacks around the apply pipeline. Each key takes a
  -- single function or a list of functions: { before_apply = fn, ... }.
  -- See lua/replacer/hooks.lua.
  hooks = {},
  -- i18n / message customization: override any key in
  -- lua/replacer/messages.lua's DEFAULTS (string.format templates), and/or
  -- suppress routine info-level notifications entirely with quiet = true
  -- (warnings/errors always show).
  messages = {},
  quiet = false,

  -- Filters (also overridable per-run via command flags).
  file_types = {}, -- ripgrep --type values, e.g. { "lua", "md" }
  globs = {},      -- include glob patterns, e.g. { "*.lua" }
  exclude = {},    -- path/glob patterns to exclude, e.g. { "node_modules", "*.min.js" }

  fzf = { winopts = { width = 0.85, height = 0.70 } },
  telescope = { layout_config = { width = 0.85, height = 0.70 } },
  git_ignore = true,

  -- Picker keymaps (buffer-local, set inside the picker window only).
  -- Match the previously hardcoded values, so existing setups are unaffected.
  keymaps = {
    toggle_select = "<Tab>",      -- multi-select + move to next
    toggle_select_prev = "<S-Tab>", -- multi-select + move to previous
    apply_all = "<C-a>",          -- replace ALL matches (respects confirm_all)
    quit = "<Esc>",               -- close the picker (double-<Esc> in fzf's terminal)
  },
}
