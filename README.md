# replacer.nvim

```
  ____             _
 |  _ \ ___ _ __ | | __ _  ___ ___ _ __
 | |_) / _ \ '_ \| |/ _` |/ __/ _ \ '__|
 |  _ <  __/ |_) | | (_| | (_|  __/ |
 |_| \_\___| .__/|_|\__,_|\___\___|_|
           |_|
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-alpha-red)
[![CI](https://github.com/StefanBartl/replacer.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/replacer.nvim/actions/workflows/ci.yml)

Project-wide search-and-replace with ripgrep, an interactive picker (fzf-lua
or Telescope), live preview, and precise application of changes.

> **Alpha stage — active development.** This repository is in its development
> phase; breaking changes are to be expected at any time. Pin a commit or tag
> if you depend on it.

## Where this sits

- [**nvim-spectre**](https://github.com/nvim-pack/nvim-spectre) — the
  best-known alternative; reach for it if you want a dedicated editable
  results buffer rather than a picker over individual occurrences.
- [**grug-far.nvim**](https://github.com/MagicDuck/grug-far.nvim) — a
  buffer-as-form take on the same job, if you prefer typing a search into a
  live-updating window over a command grammar.
- [**fileops.nvim**](https://github.com/StefanBartl/fileops.nvim) — not a
  competitor: file and directory operations (move, copy, delete, touch) from
  the same author, pairing with replacer's content-level renames.

replacer's own bias: every occurrence is an individually selectable entry, and
nothing is written before you have had the chance to look at a diff.

## Installation

```lua
{
  "StefanBartl/replacer.nvim",
  cmd = { "Replace", "Replacer", "Surround", "Wrap" }, -- lazy-load on first use
  dependencies = {
    "StefanBartl/lib.nvim",
    "ibhagwan/fzf-lua", -- or nvim-telescope/telescope.nvim + nvim-lua/plenary.nvim
  },
  opts = {}, -- engine defaults to "auto": fzf-lua first, then telescope
}
```

[`lib.nvim`](https://github.com/StefanBartl/lib.nvim) is a hard dependency —
the `:Replace`/`:Surround` command layer, notifications, confirm dialogs, file
export and the progress indicator all resolve through it. ripgrep is
recommended but not required: without it, a native `vimgrep` backend takes
over automatically. Full requirements, and how to turn off the one-time
declared-tools popup: [`docs/installation.md`](docs/installation.md).

## Quickstart

```vim
:Replace foo bar                  " picker over the current buffer
:Replace foo bar cwd --dry        " stats + diff over the working directory, no writes
:Replace foo bar cwd --all        " apply everywhere, no picker
:'<,'>Replace foo bar             " only within the visual selection
:Surround word **                 " **word** — wrap every match with a delimiter
```

In the picker: `<Tab>` selects, `<CR>` applies the selection, `<C-a>` applies
to everything, `<C-r>` applies the entry under the cursor and reopens with the
rest, `<C-f>` filters the list by stacked path/content clauses (needs
[pickers.nvim](https://github.com/StefanBartl/pickers.nvim)), a second `<Esc>`
closes. All configurable, all buffer-local.

`<Tab>` completes at every slot of the command — scope keywords, all 41 flag
names at a bare `--`, and the values of the four flags that have any.

## Features

- **Occurrence-level selection.** Several hits on one line are several
  entries, not one — pick and skip individually, with the match highlighted in
  the preview.
- **Two backends, auto-detected.** ripgrep `--json` for precise coordinates,
  or a native `vimgrep` scan when `rg` is absent. Two pickers, likewise.
- **Nothing writes by surprise.** `--dry` for stats and a diff, `--export=`
  for a git-applyable patch or JSON, `--to-quickfix` for a navigable list,
  `--confirm-per-file`, and `--checkpoint` + `:ReplaceUndo` to recover from an
  apply that already happened.
- **Matching that knows what it is looking at.** Case-preserving replace,
  whole-word, Tree-sitter-aware `--code-only`, whitespace preservation, regex
  with backreferences and a live test panel, and a soft `--lsp` mode that
  upgrades identifier-shaped matches to a real symbol rename.
- **More than one replace at a time.** Batch pairs from a file, clipboard or
  quickfix; named presets; a re-runnable history; file and directory renames
  by basename.
- **`:Surround` / `:Wrap`.** Wrap every match with a delimiter, idempotently.

Every one of these, with the module and config option that implements it:
[`docs/FEATURES/`](docs/FEATURES/README.md).

## Documentation

| | |
| --- | --- |
| [`docs/README.md`](docs/README.md) | The documentation index |
| [`docs/installation.md`](docs/installation.md) | Requirements, the lazy.nvim spec, declared CLI tools |
| [`docs/commands.md`](docs/commands.md) | All fourteen commands and all 41 flags |
| [`docs/configuration.md`](docs/configuration.md) | Every option, with defaults, hooks and message templates |
| [`docs/BINDINGS.md`](docs/BINDINGS.md) | Commands, keymaps and autocommands on one page |
| [`docs/WORKFLOW.md`](docs/WORKFLOW.md) | How the features are meant to combine day to day |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Symptom-first, plus `:ReplaceDebug` |
| `:help replacer` | The same reference, in-editor |

## Feedback

Bugs, feature ideas and usage questions belong in the
[issue tracker](https://github.com/StefanBartl/replacer.nvim/issues); anything
open-ended in
[Discussions](https://github.com/StefanBartl/replacer.nvim/discussions).
Contributing, and how to run the checks CI runs:
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
