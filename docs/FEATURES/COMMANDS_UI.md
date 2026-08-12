# Commands & UI

The picker itself, the scope/engine machinery around it, and the feedback
layer (progress, messages, errors) that surrounds every run.

## Double-`<Esc>` picker close

Both backends treat the first `<Esc>` as leaving the query's own edit mode
(terminal-insert for fzf-lua, insert mode for Telescope) and the second as
actually closing the picker, matching each backend's own native feel instead
of a single global override.

- **Module:** `pickers/fzf.lua` (quit keymap wiring), `pickers/telescope.lua`
  (quit keymap wiring)
- **Config:** `opts.keymaps.quit` (default `<Esc>`)

## `[range]Replace`

`:[range]Replace` restricts matching to a visual selection (or any other
`[range]`) instead of the whole scope.

- **Module:** `command.lua` (`M.register`, `spec.routes[1].range = true`)
- **Usercmds:** `:[range]Replace[!] {old} {new} [scope] [--flags]` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))

## Picker engine auto-detection

`engine = "auto"` picks fzf-lua when installed, else Telescope — set
explicitly to `"fzf"`/`"telescope"` to skip the detection.

- **Module:** `init.lua` (`pick_picker`)
- **Config:** `opts.engine` (default `"auto"`)

## Preview-window match highlighting

The matched span is highlighted in the preview window via the
`ReplacerTarget` extmark highlight group, in both pickers.

- **Module:** `pickers/telescope.lua` (`ReplacerTarget` extmark), `pickers/fzf.lua`
- **Docs:** [BINDINGS.md](../BINDINGS.md)

## Progress indicator

Large-scope searches show a progress indicator via
[lib.nvim.progress](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/progress/README.md),
styled `notify`/`statusline`/`fidget`/`float`; silently skipped when
lib.nvim isn't installed.

- **Module:** `rg.lua` (`new_progress`)
- **Config:** `opts.progress_style` (`"auto"` | `"notify"` |
  `"statusline"` | `"fidget"` | `"float"` | `"kit"`, default `"auto"`)
- **Docs:** [`docs/progress-indicator.md`](../progress-indicator.md)

## Configurable picker keymaps + which-key labels

Every picker keymap (`toggle_select`, `toggle_select_prev`, `apply_all`,
`quit`, `replace_and_reopen`) is overridable via `setup({ keymaps = {...} })`
buffer-locally inside the picker window; which-key shows labels for these
where the backend allows it (Telescope's real `vim.keymap.set` calls are
fully labeled, fzf-lua's terminal-native bindings cannot be seen by
which-key).

- **Module:** `pickers/utils.lua` (which-key label registration),
  `pickers/telescope.lua`, `pickers/fzf.lua`
- **Config:** `opts.keymaps.*`
- **Keymaps:** see [BINDINGS.md](../BINDINGS.md#picker-keymaps)

## Apply-and-reopen

`keymaps.replace_and_reopen` (`<C-r>` by default) applies the entry under
cursor, then reopens the picker with the remaining matches — a modifier key
by design, since both pickers' query line is live text input and a bare
letter would be swallowed by it instead of reaching the search box.

- **Module:** `pickers/telescope.lua`, `pickers/fzf.lua`
- **Config:** `opts.keymaps.replace_and_reopen` (default `<C-r>`)
- **Keymaps:** see [BINDINGS.md](../BINDINGS.md#picker-keymaps)

## Specific parse errors

Argument parsing reports specific, actionable errors — an unterminated
quote, a mis-flagged boolean — instead of a generic "invalid arguments"
failure.

- **Module:** `error.lua` (`M.new`, `M.invalid_scope`, `M.format`),
  `command.lua` (`parse_args`, `M.parse_request`)

## Overridable messages + quiet mode

`config.messages` overrides any key in `messages.lua`'s `DEFAULTS`
(`string.format` templates); `config.quiet` suppresses routine info-level
notifications entirely (warnings/errors always show).

- **Module:** `messages.lua` (`M.fmt`, `M.info`, `M.DEFAULTS`)
- **Config:** `opts.messages` (default `{}`), `opts.quiet` (default `false`)
