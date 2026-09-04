# Health

```vim
:checkhealth replacer
```

replacer.nvim registers a `vim.health` provider
([`health.lua`](../lua/replacer/health.lua)). It runs nine sections, in this
order:

| Section | Fails when | Degrades when |
| --- | --- | --- |
| **Neovim** | version below 0.9.0 | — |
| **lib.nvim** | `lib.nvim.bindings.usercmd.composer` does not resolve — the commands cannot register at all | — |
| **ripgrep** | — | `rg` missing (the native `vimgrep` backend takes over), or older than 11.0 (`--json` support) |
| **Pickers** | neither fzf-lua nor telescope.nvim is installed | the configured `engine` names a picker that is not installed |
| **Configuration** | an option has the wrong type or an out-of-range value | — |
| **UTF-8 Support** | `vim.str_byteindex` is missing | the round-trip conversion test is inconclusive |
| **Optional integrations** | — | `lib.nvim.progress` absent (`progress_style` is inert) or which-key absent (keymaps unlabeled) |
| **Declared tools** | — | reports [`install.json`](install.json) through `lib.nvim.deps`, skipped silently on an older lib.nvim |
| **Summary** | — | usage line, plus a composer pre-flight for the `:Replace` and `:Surround` routes |

A `warn` is never something to fix blindly. `ripgrep not found` is a warning
rather than an error precisely because the vimgrep fallback is a supported
mode — see [FEATURES/SEARCH.md](FEATURES/SEARCH.md#native-vimgrep-backend-with-automatic-fallback)
for what changes when it engages.

When a check points at behaviour rather than a missing binary — matches
skipped, offsets off, a pattern that works in `rg` but not in the picker — go
to [troubleshooting.md](troubleshooting.md) instead.
