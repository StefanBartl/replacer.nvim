# Features

What each feature actually is, and where it lives in the codebase. This
consolidates a personal-notes audit (originally
`MyPlugin-Notes/ReplacerRoadmap.md`: 12 numbered points plus a 22-item
wishlist) against the real implementation as of this writing — every item on
that list has shipped, with one narrower exception noted at the bottom.

For day-to-day usage see [`:help replacer`](../doc/replacer.txt) (the
authoritative reference); this file exists so "did we ever build X" has one
place to check instead of re-reading the whole module tree.

## Search & matching

| Feature | Implemented as |
| --- | --- |
| Case-preserving replace (`foo→bar`, `Foo→Bar`, `FOO→BAR`, `fooBar→bazQux`) | `case_preserve` config / `--case-preserve` flag, [`casing.lua`](../lua/replacer/casing.lua) |
| Whole-word matching | `word_boundary` config / `--word` flag |
| Skip matches inside strings/comments (Tree-sitter, best-effort) | `code_only` config / `--code-only` flag, [`tscode.lua`](../lua/replacer/tscode.lua) |
| Regex mode with helpers (escape, live test panel, backreferences) | `--regex`, `:ReplaceEscape`, `:ReplaceTest`, [`regex.lua`](../lua/replacer/regex.lua) |
| Preserve a match's own surrounding whitespace | `preserve_whitespace` config / `--preserve-ws` flag |
| ripgrep with automatic `vimgrep` fallback | `search_engine = "auto"`, [`rg.lua`](../lua/replacer/rg.lua) |
| File-scope filters (`--type`, globs, exclude, size limit) | `file_types`/`globs`/`exclude`/`max_file_size` config |
| Monorepo/project-root detection | `"root"` scope token + `:ReplaceRoot`, [`root.lua`](../lua/replacer/root.lua) |
| Git changed/staged/untracked-files-only mode | `--changed[=<kinds>]`, [`gitfiles.lua`](../lua/replacer/gitfiles.lua) |
| BOM/CRLF-aware raw file reads | [`encoding.lua`](../lua/replacer/encoding.lua) |

## Applying changes

| Feature | Implemented as |
| --- | --- |
| Plan/review without applying, patch/JSON export | `--dry`/`--export`, [`export.lua`](../lua/replacer/export.lua) |
| Quickfix/location-list export (never writes) | `--to-quickfix`/`--to-loclist` |
| Per-file confirmation (All/Skip/Only-some/Quit) | `confirm_per_file` config / `--confirm-per-file`, [`perfile.lua`](../lua/replacer/perfile.lua) |
| Undo checkpoint before an ALL apply | `checkpoint` config / `--checkpoint` + `:ReplaceUndo`, [`checkpoint.lua`](../lua/replacer/checkpoint.lua) |
| Safe-mode (skip read-only/oversized/binary files) | `safe_mode`/`skip_binary`/`max_file_size` config / `--safe` |
| Soft LSP-driven rename for identifier matches | `lsp` config / `--lsp`, [`lsp_rename.lua`](../lua/replacer/lsp_rename.lua) |
| Before/after hooks around the apply pipeline | `hooks` config / [`hooks.lua`](../lua/replacer/hooks.lua) |

## Batch, history & presets

| Feature | Implemented as |
| --- | --- |
| Multiple `{old → new}` pairs in one run (file/clipboard/quickfix) | `:ReplaceBatch`, [`batch.lua`](../lua/replacer/batch.lua) |
| Recent-runs history, re-run from a picker | `:ReplaceHistory`, [`history.lua`](../lua/replacer/history.lua) |
| Named, reusable replace requests | `:ReplaceSavePreset`/`:ReplacePreset`, [`presets.lua`](../lua/replacer/presets.lua) |
| Rename files/directories whose basename matches | `:ReplaceFNames`, [`fnames.lua`](../lua/replacer/fnames.lua) |
| Pair a single-file content replace with renaming that file | `--also-rename-file`, [`rename_assist.lua`](../lua/replacer/rename_assist.lua) |

## UI & feedback

| Feature | Implemented as |
| --- | --- |
| Progress indicator for large-scope searches | `progress_style`, via [`lib.nvim.progress`](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/progress/README.md) — see [`docs/progress-indicator.md`](progress-indicator.md) |
| Preview-window match highlighting | `ReplacerTarget` extmark highlight, both pickers |
| Configurable picker keymaps + which-key labels | `keymaps.*` config — see [`docs/BINDINGS.md`](BINDINGS.md) |
| Specific, actionable parse errors (not a generic failure) | [`error.lua`](../lua/replacer/error.lua) + [`messages.lua`](../lua/replacer/messages.lua) |
| Overridable message templates, quiet mode | `messages`/`quiet` config, [`messages.lua`](../lua/replacer/messages.lua) |
| `:help replacer` | [`doc/replacer.txt`](../doc/replacer.txt) |

## Known loose end

`pickers/utils.lua` defines `ReplacerOld`/`ReplacerOldStrikethrough`/
`ReplacerNew` highlight groups and a `setup_highlight_groups()` function for a
richer old-vs-new diff view in the preview (strikethrough on the old text,
colored new-text hint) — but nothing in either picker actually calls
`setup_highlight_groups()`. It's dead code today, not a wired-up feature; only
`ReplacerTarget` (plain span highlight) is live. Worth either finishing the
wiring or removing the unused code, but out of scope for this pass.

## The one item not (fully) done

**True live picker fill** — populating the picker as ripgrep results stream
in, so you can start selecting before the search finishes. `--stream`
switches collection to an incremental `rg --json` parser
(`rg.lua`'s `collect_streaming`) that's proven equivalent to the non-streaming
collector by test, giving smoother progress updates — but the picker itself
still only opens once collection finishes. Wiring incremental results into
fzf-lua and Telescope (structurally very different APIs for a growing source)
is deliberately deferred; tracked in [`docs/ROADMAP.md`](ROADMAP.md), not
duplicated here.
