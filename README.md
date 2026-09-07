> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# replacer.nvim

```
  ____             _
 |  _ \ ___ _ __ | | __ _  ___ ___ _ __
 | |_) / _ \ '_ \| |/ _` |/ __/ _ \ '__|
 |  _ <  __/ |_) | | (_| | (_|  __/ |
 |_| \_\___| .__/|_|\__,_|\___\___|_|
           |_|                     .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
[![CI](https://github.com/StefanBartl/replacer.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/replacer.nvim/actions/workflows/ci.yml)

Project-wide search-and-replace where every occurrence is its own decision.

ripgrep finds the matches, a picker — fzf-lua or Telescope — lets you select
them one by one with the hit highlighted in the preview, and nothing is written
before you have had the chance to look at a diff.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Where this sits](#where-this-sits)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md) — the README is the shop window, that
is the reference, one file per question.

- [Features](docs/FEATURES/README.md) — the catalog: every shipped feature against the module, command and config option that implements it, split into [search](docs/FEATURES/SEARCH.md), [apply](docs/FEATURES/APPLY.md), [commands and UI](docs/FEATURES/COMMANDS_UI.md), and [batch and presets](docs/FEATURES/BATCH_AND_PRESETS.md).
- [Installation](docs/installation.md) — requirements, the spec, and the declared-CLI-tools popup.
- [Configuration](docs/configuration.md) — every `setup()` option with its default, plus hooks and message templates.
- [Command reference](docs/commands.md) — all fourteen commands, their grammar, and all 41 flags.
- [Bindings cheatsheet](docs/BINDINGS.md) — commands, picker keymaps and the single autocommand, on one page.
- [Workflow](docs/WORKFLOW.md) — not what each feature is, but how they combine into habits worth keeping.
- [Progress indicator](docs/progress-indicator.md) — the six `progress_style` values, with recordings, and how to drive the headless one from your own statusline.
- [Lua API](docs/api.md) — `setup`, `run`, `config.get`, `hooks.on`: the surface meant for scripting.
- [Health](docs/health.md) — what `:checkhealth replacer` checks, and which of its warnings are supposed to be warnings.
- [Troubleshooting](docs/troubleshooting.md) — symptom-first, plus what `:ReplaceDebug` can tell you.
- [Contributing](docs/CONTRIBUTING.md) — repository layout, the checks CI runs, and where documentation belongs.

`:help replacer` is the same reference inside the editor.

---

## What it does

A project-wide replace is easy to start and hard to trust. The usual tools
either apply everything or make you edit a results buffer by hand, and both
answers are wrong for the common case: most of the hits are right, a few are
not, and you want to see which is which before anything is written.

| Area | Does |
| --- | --- |
| **Occurrence-level selection** | Several hits on one line are several entries, not one — pick and skip individually, with the match highlighted in the preview |
| **Two backends, auto-detected** | ripgrep `--json` for precise coordinates, or a native `vimgrep` scan when `rg` is absent. Two pickers, likewise |
| **Nothing writes by surprise** | `--dry` for stats and a diff, `--export=` for a git-applyable patch or JSON, `--to-quickfix` for a navigable list, `--confirm-per-file`, and `--checkpoint` with `:ReplaceUndo` to recover from an apply that already happened |
| **Matching that knows what it is looking at** | Case-preserving replace, whole-word, Tree-sitter-aware `--code-only`, whitespace preservation, regex with backreferences and a live test panel, and a soft `--lsp` mode that upgrades identifier-shaped matches to a real symbol rename |
| **More than one replace at a time** | Batch pairs from a file, the clipboard or the quickfix list; named presets; a re-runnable history; file and directory renames by basename |
| **`:Surround` / `:Wrap`** | Wrap every match with a delimiter, idempotently |

Every one of these, against the module and config option that implements it, is
[docs/FEATURES/](docs/FEATURES/README.md).

---

## Around it

> **[fileops.nvim](https://github.com/StefanBartl/fileops.nvim)** — the same
> job one level up: moving, copying, deleting and creating the files
> themselves, where replacer renames what is inside them.
>
> **[pickers.nvim](https://github.com/StefanBartl/pickers.nvim)** — provides
> the stacked path and content clauses `<C-f>` filters the result list with.
>
> **[recommender.nvim](https://github.com/StefanBartl/recommender.nvim)** —
> finds the repetition worth renaming in the first place, and drives `:Replace`
> to carry the rename out.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) and a picker are the real
> dependencies — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.9+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — the `:Replace` / `:Surround` command layer, notifications, confirm dialogs, file export and the progress indicator all resolve through it |
| A picker | [fzf-lua](https://github.com/ibhagwan/fzf-lua) or [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim), auto-detected in that order |

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| `rg` (ripgrep) | Precise match coordinates from `--json`. Without it a native `vimgrep` backend takes over automatically — recommended, not required |
| Tree-sitter parsers | `--code-only`, which skips matches in comments and strings |
| An LSP server | `--lsp`, which upgrades an identifier-shaped match to a real symbol rename |
| [pickers.nvim](https://github.com/StefanBartl/pickers.nvim) | `<C-f>`, the stacked path and content filter over the result list |

The declared tools and how to turn off the one-time popup are in
[docs/installation.md](docs/installation.md).

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/replacer.nvim",
  cmd = { "Replace", "Replacer", "Surround", "Wrap" },
  dependencies = {
    "StefanBartl/lib.nvim",
    "ibhagwan/fzf-lua", -- or nvim-telescope/telescope.nvim + nvim-lua/plenary.nvim
  },
  opts = {}, -- engine defaults to "auto": fzf-lua first, then telescope
}
```

`cmd` is enough: nothing happens until you ask for a replace. The full
requirements list and the other plugin managers are in
[docs/installation.md](docs/installation.md).

---

## Quickstart

Replace something in the buffer you are in, and look at the hits before
committing to any of them:

```vim
:Replace foo bar
```

Then the wider cases:

```vim
:Replace foo bar cwd --dry     " stats and a diff over the working directory, no writes
:Replace foo bar cwd --all     " apply everywhere, no picker
:'<,'>Replace foo bar          " only within the visual selection
:Surround word **              " **word** — wrap every match with a delimiter
```

`<Tab>` completes at every slot of the command: the scope keywords, all 41 flag
names at a bare `--`, and the values of the four flags that have any.

Verify your setup any time with:

```vim
:checkhealth replacer
```

---

## What you get with the defaults

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
[docs/BINDINGS.md](docs/BINDINGS.md); the flags are
[docs/commands.md](docs/commands.md).

---

## Where this sits

- [**nvim-spectre**](https://github.com/nvim-pack/nvim-spectre) — the
  best-known alternative; reach for it if you want a dedicated editable results
  buffer rather than a picker over individual occurrences.
- [**grug-far.nvim**](https://github.com/MagicDuck/grug-far.nvim) — a
  buffer-as-form take on the same job, if you prefer typing a search into a
  live-updating window over a command grammar.

replacer's own bias: every occurrence is an individually selectable entry, and
nothing is written before you have had the chance to look at a diff.

---

## Health check

```vim
:checkhealth replacer
```

Nine sections: Neovim, lib.nvim, ripgrep, the pickers, the configuration as it
was merged, the optional integrations, UTF-8 support, the declared tools, and a
summary. Several of its warnings are meant to be warnings — a missing `rg` is
one — and [docs/health.md](docs/health.md) says which.

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the repository layout, the
checks CI runs, and where documentation belongs.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/replacer.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/replacer.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
