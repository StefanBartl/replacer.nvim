# Features

A `docs/FEATURES_FORMAT.md`-shaped catalog of every item on
[`docs/ROADMAP.md`](../ROADMAP.md)'s "Already shipped" list — one `##`
section per roadmap point, cross-referenced against the module/command/
config option that actually implements it. [`docs/FEATURES.md`](../FEATURES.md)
stays the narrative, table-shaped write-up for humans reading top to bottom;
this folder is the machine-readable catalog `documentation.nvim`'s Features
tab reads.

## Files

- **[SEARCH.md](SEARCH.md)** — how matches are found: backends, matching
  modes (word/case/code-only/whitespace), scope and file filters, regex
  helpers, git-aware and streaming collection.
- **[APPLY.md](APPLY.md)** — what happens to a match once you commit to it:
  dry-run/export, quickfix/loclist, safe-mode, per-file confirmation,
  checkpoints, hooks, LSP-driven rename.
- **[COMMANDS_UI.md](COMMANDS_UI.md)** — the picker UI itself and the
  commands/keymaps wrapped around it: scope shorthand, auto-detected
  engine/picker, preview highlighting, progress indicator, keymaps,
  messages/quiet mode, parse errors.
- **[BATCH_AND_PROJECT.md](BATCH_AND_PROJECT.md)** — running more than one
  replace at once (history, presets, batch pairs), extending replace to
  file/directory names, and the surrounding project tooling (repo metadata,
  CI).
