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

- **`.github` workflows** — CI (headless test runs, luacheck/stylua) on push/PR.
- **`:ReplaceFNames` (or similar)** — extend replace to file/directory names,
  not just file contents:
  - a dedicated picker for filenames/directories, or a combined picker that
    also highlights renamed paths;
  - optionally follow the rename through the language's own import/export
    statements across the project.
- **Soft LSP integration** — offer LSP rename when a symbol is matched
  exactly, falling back to plain text replace otherwise.
- **Streaming picker fill** — populate the picker as ripgrep results stream
  in, so you can start selecting before the search finishes.
- **Rename-assist** — pair a content replace with an optional file rename
  (e.g. class name ↔ file name), previewed together.
