# Roadmap

Consolidated from the original (German) notes plus what's shipped since.
Related docs: [`docs/BINDINGS.md`](BINDINGS.md), [`docs/progress-indicator.md`](progress-indicator.md).

## Already shipped

- Close the picker with double-`<Esc>` (fzf-lua + Telescope).
- Multiple occurrences on the same line each become their own picker entry.
- Search options (`--literal`/`--regex`, `--smart-case`, `--hidden`, `--ignore`, …) settable per-command via flags, not just in `setup()`.
- Native `vimgrep` backend, automatic fallback when ripgrep isn't installed.
- Picker auto-detection: fzf-lua if installed, else Telescope (`engine = "auto"`).
- `[range]Replace` — restrict matching to a visual selection.
- File-scope filters: `--type`, globs, exclude patterns (`file_types`/`globs`/`exclude`).
- Plan/review without applying: `--dry` (stats + diff) and `--export` (patch or JSON).
- Preview highlighting: the matched span is highlighted in the preview window (`ReplacerTarget`).
- Progress indicator for large-scope searches (`progress_style`: notify/statusline/fidget/float), via [lib.nvim.progress](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/progress/README.md).
- Configurable picker keymaps (`keymaps.*`) + which-key labels where the backend allows it (see `docs/BINDINGS.md`).
- GitHub repo metadata (description, topics) filled in.

## Planned

- **Replace-and-reopen key** — a picker key (working name: `r`) that applies
  the single entry under the cursor and reopens the picker with the
  remaining matches. Was documented in an earlier README/vimdoc revision as
  if it already existed; it did not — this is the actual place it's tracked
  now, see `docs/BINDINGS.md`.
- **`.github` workflows** — CI (headless test runs, luacheck/stylua) on push/PR.
- **`:ReplaceFNames` (or similar)** — extend replace to file/directory names,
  not just file contents:
  - a dedicated picker for filenames/directories, or a combined picker that
    also highlights renamed paths;
  - optionally follow the rename through the language's own import/export
    statements across the project.
- **Batch replaces** — multiple `{old → new}` pairs in one run, importable
  from a file/quickfix/clipboard.
- **Monorepo/root detection** — auto-detect the project root (git,
  `package.json`, `go.mod`, …), with a picker when there are multiple
  candidates.
- **Changed-files-only mode** — restrict to git changed/staged/unstaged/untracked files.
- **History & presets** — recent searches/replacements, named presets,
  re-run from a picker.
- **Per-file confirmation step** — an intermediate "All in this file / Skip
  file / Only some hunks" prompt instead of one global ALL confirmation.
- **Undo checkpoint** — an automatic `:write`/git-stash/temp-branch
  checkpoint before a large apply, with one-click rollback.
- **Soft LSP integration** — offer LSP rename when a symbol is matched
  exactly, falling back to plain text replace otherwise.
- **Streaming picker fill** — populate the picker as ripgrep results stream
  in, so you can start selecting before the search finishes.
- **Hook system** — Lua before/after callbacks (per file or global) to run a
  linter/formatter, invalidate a cache, etc.
- **Rename-assist** — pair a content replace with an optional file rename
  (e.g. class name ↔ file name), previewed together.
- **i18n / message customization** — configurable prompt/confirmation text,
  quiet vs. verbose modes.
