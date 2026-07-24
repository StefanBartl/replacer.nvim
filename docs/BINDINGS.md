# Bindings Cheatsheet

Every user command, keymap, and autocommand replacer.nvim registers, in one
place.

---

## User commands

| Command | File | Description |
| --- | --- | --- |
| `:Replace` | [command.lua](../lua/replacer/command.lua) | Search-and-replace with scope/flags/range; see `:help replacer-commands` |
| `:Replacer` | [command.lua](../lua/replacer/command.lua) | Alias for `:Replace` |
| `:Surround` | [surround.lua](../lua/replacer/surround.lua) | Wrap every match of a pattern with a delimiter; see `:help :Surround` |
| `:Wrap` | [surround.lua](../lua/replacer/surround.lua) | Alias for `:Surround` |
| `:ReplaceEscape {text}` | [regex.lua](../lua/replacer/regex.lua) | Escape `{text}` for use as a Vim regex pattern; echoes it and copies it to the unnamed register |
| `:ReplaceTest [pattern] [sample]` | [regex.lua](../lua/replacer/regex.lua) | Small floating live pattern-test panel: line 1 is the pattern, line 2 the sample text, matches highlight as you type; `<Esc>`/`q` closes |
| `:ReplaceRoot[!] {old} {new} [--flags]` | [root.lua](../lua/replacer/root.lua) | Like `:Replace`, but the scope is an auto-detected project root; prompts when detection finds more than one candidate |
| `:ReplaceUndo [id]` | [checkpoint.lua](../lua/replacer/checkpoint.lua) | Restore files from a `--checkpoint` snapshot (most recent when `[id]` omitted) |
| `:ReplaceHistory` | [history.lua](../lua/replacer/history.lua) | `vim.ui.select` over the last 50 applies; re-runs the chosen one |
| `:ReplaceSavePreset {name} {old} {new} [scope] [--flags]` | [presets.lua](../lua/replacer/presets.lua) | Save a named, reusable replace request |
| `:ReplacePreset {name}` | [presets.lua](../lua/replacer/presets.lua) | Run a saved preset exactly as saved; `<Tab>` completes names |
| `:ReplaceDebug` | [debug.lua](../lua/replacer/debug.lua) | Developer utility: `on`/`off`/`status`/`test`/`inspect`/`analyze <line> <pattern>` |

All support `[range]` and the bang form (`!`) where documented in `:help replacer-commands`.

---

## Picker keymaps

Set inside the picker window only (buffer-local) — never global. Configurable
via `require("replacer").setup({ keymaps = { ... } })`, see
[`RP_Keymaps`](../lua/replacer/types/config.lua).

| Action | Config key | Default | fzf-lua | Telescope |
| --- | --- | --- | --- | --- |
| Apply to selection (multi if present, else single) | *(fixed)* | `<CR>` | fzf's own default key | Telescope's own default key |
| Toggle select + move to next | `keymaps.toggle_select` | `<Tab>` | ✅ (fzf's native multi-select toggle) | ✅ real Neovim keymap |
| Toggle select + move to previous | `keymaps.toggle_select_prev` | `<S-Tab>` | ✅ (fzf's native multi-select toggle) | ✅ real Neovim keymap |
| Apply to ALL matches (respects `confirm_all`) | `keymaps.apply_all` | `<C-a>` | ✅ via fzf action/`--bind` | ✅ real Neovim keymap |
| Close the picker | `keymaps.quit` | `<Esc>` | ✅ (2nd `<Esc>`; 1st leaves terminal-insert, fixed) | ✅ (2nd `<Esc>`; 1st leaves insert mode, fixed) |

**which-key:** if [which-key.nvim](https://github.com/folke/which-key.nvim) is
installed, its popup shows labels for these keys — with one caveat: fzf-lua's
`toggle_select`/`apply_all` are fzf's own terminal-native bindings (consumed
by the fzf binary itself, never passing through Neovim's keymap layer), so
which-key cannot see or label those two for the fzf backend. Telescope's keys
are real `vim.keymap.set` calls and are fully labeled. `quit` is labeled for
both backends.

**Not yet implemented** (documented as a future item, see
[`docs/ROADMAP.md`](ROADMAP.md)): a `r` key to replace the single entry under
the cursor and reopen the picker with the remaining matches. Earlier
README/vimdoc revisions listed this as if it already existed — it did not;
this file reflects only keys that are actually wired up.

---

## Autocommands

None. replacer.nvim registers no `autocmd`/`augroup` of any kind.
