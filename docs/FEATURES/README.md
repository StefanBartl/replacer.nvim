# Features

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

## Where this sits

- [**nvim-spectre**](https://github.com/nvim-pack/nvim-spectre) — the
  best-known alternative; reach for it if you want a dedicated editable results
  buffer rather than a picker over individual occurrences.
- [**grug-far.nvim**](https://github.com/MagicDuck/grug-far.nvim) — a
  buffer-as-form take on the same job, if you prefer typing a search into a
  live-updating window over a command grammar.

replacer's own bias: every occurrence is an individually selectable entry, and
nothing is written before you have had the chance to look at a diff.

## The catalog

The catalog of everything replacer.nvim actually ships, cross-referenced
against the module, command, and config option that implements it. One `##`
section per feature, so "did we ever build X, and where does it live" has one
address instead of a walk through the module tree.

For day-to-day usage, [`:help replacer`](../../doc/replacer.txt) is the
reference and [`../commands.md`](../commands.md) is the command grammar. This
folder answers the different question: what exists, and in which file.

## Files

- **[SEARCH.md](SEARCH.md)** — how matches are found: backends, matching
  modes (word/case/code-only/whitespace), scope and file filters, regex
  helpers, git-aware and streaming collection.
- **[APPLY.md](APPLY.md)** — what happens to a match once you commit to it:
  dry-run/export, quickfix/loclist, safe-mode, per-file confirmation,
  checkpoints, hooks, LSP-driven rename.
- **[COMMANDS_UI.md](COMMANDS_UI.md)** — the picker UI itself and the
  commands wrapped around it: `:Surround`/`:Wrap`, scope shorthand,
  `[range]`, completion, auto-detected engine/picker, preview highlighting,
  progress indicator, keymaps, messages/quiet mode, parse errors.
- **[BATCH_AND_PRESETS.md](BATCH_AND_PRESETS.md)** — running more than one
  replace at once (history, presets, batch pairs) and extending replace to
  file and directory names.

## Not (fully) done

**True live picker fill.** `--stream` already switches collection to an
incremental `rg --json` parser, proven equivalent to the non-streaming
collector by test, which is what makes progress updates smooth. The picker
itself still only opens once collection finishes; wiring a growing source
into fzf-lua and Telescope (structurally very different APIs for that) is
deliberately deferred. See [SEARCH.md](SEARCH.md#incremental-ripgrep-parsing).
