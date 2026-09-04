# Features

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
