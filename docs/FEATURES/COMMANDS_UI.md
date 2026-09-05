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

## `:Surround` / `:Wrap`

`:[range]Surround[!] {pattern} [delim] [scope] [--flags]` wraps every
occurrence of `{pattern}` with a delimiter — the replacement is
`<left>{pattern}<right>`. A convenience layer over `:Replace`, not a second
engine: it builds a normal request and hands it to the same executor, so
scope, `[range]`, `--dry`, `--all` and every `:Replace` flag work unchanged.
Search is always literal, because a regex pattern has no fixed text to wrap.

`{delim}` takes a literal string, a named alias, or a bracket opener that
pairs with its own closer; omit it to be prompted. **Idempotent by default** —
a match already wrapped by the chosen delimiter is skipped, so re-running
never produces `****test****`. `--nested` (alias `--allow-nested`) forces
another layer. A charwise `[range]` on a single line narrows to the columns
of the selection rather than the whole line.

- **Module:** `surround.lua` (`ALIASES`, `build_request`, `M.register`)
- **Usercmds:** `:[range]Surround[!] {pattern} [delim] [scope] [--flags]`,
  `:Wrap` as an alias (see [BINDINGS.md](../BINDINGS.md#user-commands))

## `<Tab>` completion on `:Replace`

Every slot of `:Replace`/`:Replacer`/`:Surround`/`:Wrap` completes: the scope
keywords, all 41 flag names (43 on `:Surround`) at a bare `--`, and the values
of the four flags that have one — `--type=` (ripgrep's own type names, read
live from `rg --type-list` and cached per session, so a type added by the
user's own `--type-add` is offered too), `--changed=` (comma-joinable kinds,
with kinds already named dropped from the candidates), `--engine=`, and
`--export=`.

`--glob=`/`--exclude=` deliberately do not complete: they take *patterns*, so
offering an existing path would be a candidate that is accepted, matches that
one file, and silently narrows the replacement. `--context=`/`--max-filesize=`
are integers. `{old}`/`{new}` are free text.

- **Module:** `argtypes.lua` (`RP_RG_TYPE`, `RP_CHANGED_KINDS`), `command.lua`
  (`M.FLAGS` types, `M.register` calling `argtypes.register()`)
- **Docs:** [BINDINGS.md](../BINDINGS.md#user-commands), `:help replacer-completion`

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
`quit`, `replace_and_reopen`, `filter`) is overridable via `setup({ keymaps = {...} })`
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

## Filter results (`keymaps.filter`)

A `cwd`-scoped replace can surface hundreds of matches. `keymaps.filter`
(`<C-f>` by default) opens a `vim.ui.select` → `vim.ui.input` flow that adds
a **filter clause** — *path contains X*, *content does not contain Y*, … —
narrowing the list. Clauses **stack** (AND) and are individually removable;
a term entered as `/…/` is a Lua pattern, anything else a case-insensitive
substring. The active filter shows in the prompt title
(`Select matches — path~src · ¬content~test (42/380)`). On Telescope the list
refreshes in place; on fzf-lua the picker reopens with the filtered set.

Backed by [pickers.nvim](https://github.com/StefanBartl/pickers.nvim)'s
`pickers.refine` (the shared filter-stack model). **It is a soft dependency:**
without pickers.nvim the key reports that filtering needs it and does nothing
else — every other picker key is unaffected.

- **Module:** `pickers/common.lua` (`new_refine`), `pickers/telescope.lua`,
  `pickers/fzf.lua`
- **Config:** `opts.keymaps.filter` (default `<C-f>`)
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
