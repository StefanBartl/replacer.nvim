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
- Specific parse errors for unterminated quotes and mis-flagged bools.
- `--preserve-ws` — keep a match's own whitespace around the replacement.
- `--case-preserve` — match the replacement's casing to the original.
- `--word` (whole-word) and `--code-only` (skip strings/comments, Tree-sitter best-effort).
- `:ReplaceEscape`, `:ReplaceTest`, and `\0`-`\9` backreferences in regex-mode replacement text.
- `--safe` — skip read-only/oversized/binary files.
- BOM/CRLF-aware raw file reads (native vimgrep backend + dry-run/export).
- `--to-quickfix` / `--to-loclist` — send matches to the quickfix/location list.
- `"root"` scope + `:ReplaceRoot` — auto-detected project root.
- `--changed[=<kinds>]` — restrict to git changed/staged/untracked files.
- `--confirm-per-file` — All/Skip/Only-some/Quit prompt per file.
- `--checkpoint` + `:ReplaceUndo` — snapshot files before an apply, with rollback.
- Hook system (`config.hooks` / `replacer.hooks.on()`): before/after callbacks around the apply pipeline.
- `:ReplaceHistory`, `:ReplaceSavePreset` / `:ReplacePreset` — recent runs and named presets.
- `:ReplaceBatch` — multiple `{old → new}` pairs in one run, from a file/clipboard/quickfix.
- `config.messages` / `config.quiet` — overridable prompt text, quiet mode.
- `keymaps.replace_and_reopen` (`<C-r>`) — apply the entry under cursor, reopen with the rest.
- `:ReplaceFNames` — rename files/directories whose basename matches a pattern.
- `--also-rename-file` — pair a single-file content replace with renaming that file.
- `--lsp` — soft LSP-driven rename for identifier-shaped matches, falling back to plain text.
- `--stream` — incremental ripgrep parsing (collection-layer streaming infrastructure; see `lua/replacer/rg.lua`'s `collect_streaming` docstring for the live-picker-fill scope note).
- `.github/workflows/ci.yml` — luacheck/stylua/headless-test-suite CI on push/PR.
