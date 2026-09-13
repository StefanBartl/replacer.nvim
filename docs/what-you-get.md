# What you get with the defaults

In the picker:

| Key | Does |
| --- | --- |
| `<Tab>` | Select or deselect the entry under the cursor |
| `<CR>` | Apply the selection |
| `<C-a>` | Apply to everything in the list |
| `<C-r>` | Apply this one entry and reopen with the rest |
| `<C-f>` | Filter the list by stacked path and content clauses (needs [pickers.nvim](https://github.com/StefanBartl/pickers.nvim)) |
| `<Esc>` `<Esc>` | Close — the second press, so one `<Esc>` never loses a selection |

All of them are configurable and all of them are buffer-local. The full set,
together with the commands and the single autocommand, is
[BINDINGS.md](BINDINGS.md); the flags are [commands.md](commands.md).
