# Search

Everything involved in finding matches, before any replacement is applied:
which backend runs, what counts as a match, and which files/lines are even
considered.

## Multiple occurrences per line as separate entries

When a line contains more than one occurrence of the search pattern, each
occurrence becomes its own entry in the picker instead of being collapsed
into one line-level hit — so you can select/skip individual occurrences on
the same line.

- **Module:** `rg.lua` (`find_all_occurrences`)

## Per-command search options

`--literal`/`--regex`, `--smart-case`, `--hidden`, `--ignore`, and the other
search-shaping flags are settable per invocation via `:Replace` flags, not
only in `setup()` — a one-off search doesn't need a config change.

- **Module:** `command.lua` (`M.FLAGS`, `apply_tokens`)
- **Config:** `opts.literal`, `opts.smart_case`, `opts.hidden`
- **Usercmds:** `:Replace[!] {old} {new} [scope] [--flags]` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))

## Native vimgrep backend with automatic fallback

When ripgrep isn't installed (or `search_engine = "vimgrep"` is set
explicitly), matching falls back to a native Neovim implementation instead
of failing outright.

- **Module:** `rg.lua` (`collect_ripgrep`, `collect_ripgrep_async`)
- **Config:** `opts.search_engine` (`"auto"` | `"ripgrep"` | `"vimgrep"`,
  default `"auto"`)

## File-scope filters

`--type`, include globs, and exclude patterns narrow which files are
searched, on top of the resolved scope.

- **Module:** `rg.lua` (`build_rg_args`)
- **Config:** `opts.file_types`, `opts.globs`, `opts.exclude`
- **Usercmds:** `--type=`, `--glob=`, `--exclude=` flags on `:Replace`

## Preserve a match's own whitespace

`--preserve-ws` keeps a match's own leading/trailing whitespace (relevant
with regex patterns like `\s*foo\s*`) around the replacement instead of
letting the replacement clobber it.

- **Module:** `apply.lua` (`wrap_with_original_whitespace`,
  `effective_new_text`)
- **Config:** `opts.preserve_whitespace` (default `false`)

## Case-preserving replace

`--case-preserve` re-cases the replacement to match each match's own case
style: `foo→bar`, `Foo→Bar`, `FOO→BAR`, `fooBar→bazQux`, `FooBar→BazQux`.

- **Module:** `casing.lua` (`M.detect`, `M.apply`)
- **Config:** `opts.case_preserve` (default `false`)

## Whole-word and code-only matching

`--word` restricts matches to whole-word boundaries (no word byte
immediately before/after). `--code-only` skips matches that fall inside a
string/comment Tree-sitter node, best-effort with a fallback to keeping
everything when no parser is available for the file's language.

- **Module:** `apply.lua` (word-boundary check), `tscode.lua`
  (`M.is_in_string_or_comment`)
- **Config:** `opts.word_boundary`, `opts.code_only` (both default `false`)

## Regex helpers: escape, live test panel, backreferences

`:ReplaceEscape {text}` escapes text for use as a Vim regex pattern and
copies it to the unnamed register. `:ReplaceTest [pattern] [sample]` opens a
small floating panel with live match highlighting as you type. Regex-mode
replacement text supports `\0`-`\9` backreferences.

- **Module:** `regex.lua` (`M.escape`, `M.open_test_panel`,
  `M.expand_backrefs`, `M.has_backrefs`)
- **Usercmds:** `:ReplaceEscape {text}`, `:ReplaceTest [pattern] [sample]`
  (see [BINDINGS.md](../BINDINGS.md#user-commands))

## BOM/CRLF-aware raw file reads

File content is read with BOM stripping and end-of-line detection, so
matches and replacements on Windows-authored files (CRLF, UTF-8 BOM) don't
corrupt the line endings or leave a stray BOM byte sequence in the diff.

- **Module:** `encoding.lua` (`M.strip_bom`, `M.strip_cr`, `M.detect_eol`)

## Auto-detected project root scope

The `"root"` scope token and `:ReplaceRoot` resolve the search scope to an
auto-detected project root (`.git`, `package.json`, `go.mod`, …) instead of
a manually typed path, prompting when more than one candidate is found.

- **Module:** `root.lua` (`M.detect`, `M.detect_best`, `M.pick`,
  `M.register`)
- **Usercmds:** `:ReplaceRoot[!] {old} {new} [--flags]` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))

## Git changed/staged/untracked-files-only mode

`--changed[=<kinds>]` restricts matching to files git reports as
changed/staged/untracked, intersected with the resolved scope rather than
widening it.

- **Module:** `gitfiles.lua` (`M.list`), `init.lua` (`cfg._changed_only`
  handling)
- **Usercmds:** `--changed[=<kinds>]` flag on `:Replace`

## Incremental ripgrep parsing

`--stream` switches collection to an incremental `rg --json` parser instead
of parsing the full stdout blob at the end, giving smoother, filter-aware
progress updates as matches are found. The picker itself still only opens
once collection finishes — true live picker fill is a separate, undone
follow-up.

- **Module:** `rg.lua` (`M.collect_streaming`)
- **Config:** `opts.stream` (default `false`)
