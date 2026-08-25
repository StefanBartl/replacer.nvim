# replacer.nvim

```
  ____             _
 |  _ \ ___ _ __ | | __ _  ___ ___ _ __
 | |_) / _ \ '_ \| |/ _` |/ __/ _ \ '__|
 |  _ <  __/ |_) | | (_| | (_|  __/ |
 |_| \_\___| .__/|_|\__,_|\___\___|_|
           |_|
```

![version](https://img.shields.io/badge/version-0.2-blue.svg)
![State](https://img.shields.io/badge/status-beta-orange.svg)
[![CI](https://github.com/StefanBartl/replacer.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/replacer.nvim/actions/workflows/ci.yml)
![Lazy.nvim compatible](https://img.shields.io/badge/lazy.nvim-supported-success)
![Neovim](https://img.shields.io/badge/Neovim-0.9+-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)

> Looking for file/directory-level operations (move, copy, delete, touch) to
> pair with replacer's content-level renames? See
> [`fileops.nvim`](https://github.com/StefanBartl/fileops.nvim), a sister
> plugin from the same author.

Project-wide search-and-replace with ripgrep, an interactive picker (fzf-lua or Telescope), live preview, and precise application of changes.

> Requires [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) — used for
> the `:Replace`/`:Surround` command layer (`lib.nvim.usercmd.composer`),
> notifications, the confirm dialog, file export, and the progress indicator.
> One helper library shared across the author's plugins.

______________________________________________________________________

- [Features](#features)
- [Roadmap](#roadmap)
- [Usage](#usage)
  - [Command Syntax](#command-syntax)
  - [Picker Keymaps](#picker-keymaps)
- [Installation](#installation)
  - [With Lazy.nvim](#with-lazynvim)
  - [With packer.nvim](#with-packernvim)
- [Configuration](#configuration)
- [Progress Indicator](#progress-indicator)
- [Safety & Notes](#safety--notes)
- [Development](#development)
- [Disclaimer](#disclaimer)
- [Feedback](#feedback)

______________________________________________________________________

## Usage

### Command Syntax

```sh
:[range]Replace[!] {old} {new} [scope] [--flags]
```

**Parameters:**

- `old` **required** — literal (or regex with `--regex`) text to search for
- `new` **required** — replacement text; empty string `""` deletes matches
- `scope` **optional** — `%` (current buffer) · `cwd` / `.` (working dir) · `root` (auto-detected project root, see below) · `<path>` (file/dir). Default: `default_scope` (`%`)
- `[range]` **optional** — e.g. `:'<,'>Replace` restricts matching to the selected lines
- `!` **optional** — bang is shorthand for `--all` (non-interactive)

Each occurrence on a line becomes its own selectable entry (multiple hits per line are all handled).

**Flags** (anywhere; a lone `--` stops flag parsing):

| Flag | Effect |
| ---- | ------ |
| `--literal` / `--no-literal` / `--regex` | toggle literal vs regex search |
| `--smart-case` / `--no-smart-case` | toggle ripgrep smart-case |
| `--hidden` / `--no-hidden` | include/exclude dotfiles |
| `--ignore` / `--no-ignore` | respect/ignore `.gitignore` |
| `--preserve-ws` / `--no-preserve-ws` | keep the match's own leading/trailing whitespace around the replacement (useful with regex patterns like `\s*foo\s*`) |
| `--case-preserve` / `--no-case-preserve` | re-case the replacement to match each match's own case style (`foo→bar`, `Foo→Bar`, `FOO→BAR`, `fooBar→bazQux`, `FooBar→BazQux`) |
| `--word` / `--no-word` | keep only whole-word matches (byte before/after must not be a word byte) |
| `--code-only` / `--no-code-only` | skip matches inside strings/comments (Tree-sitter, best-effort — falls back to keeping everything when no parser is available) |
| `--safe` / `--no-safe` | safe-mode: skip read-only/oversized/binary files instead of touching them |
| `--max-filesize=<bytes>` | override the safe-mode size threshold for this run (default 5 MiB) |
| `--to-quickfix` | send matches to the quickfix list and open it (never writes) |
| `--to-loclist` | send matches to the current window's location list and open it (never writes) |
| `--changed` / `--changed=<kinds>` | restrict to git changed files; bare = modified+staged+untracked, or a comma-list subset (e.g. `--changed=modified,staged`) |
| `--confirm-per-file` / `--no-confirm-per-file` | ALL-mode: ask All/Skip/Only-some/Quit per file instead of one global confirmation |
| `--also-rename-file` / `--no-also-rename-file` | single-file scope only: after a successful content replace, offer to also rename the file itself the same way |
| `--lsp` / `--no-lsp` | soft LSP integration: identifier-shaped matches try an LSP-driven rename first, falling back to plain text (see below) |
| `--stream` / `--no-stream` | incremental ripgrep `--json` parsing for smoother, filter-aware progress while a search is in flight (see below) |
| `--checkpoint` / `--no-checkpoint` | ALL-mode: snapshot every about-to-be-touched file first; `:ReplaceUndo` restores them |
| `--type=<ft>` *(repeatable)* | restrict to a filetype (ripgrep `--type`) |
| `--glob=<pat>` *(repeatable)* | include glob pattern |
| `--exclude=<pat>` *(repeatable)* | exclude path/glob pattern |
| `--engine=<fzf\|telescope>` | override picker for this run |
| `--context=<n>` | preview context lines |
| `--all` | non-interactive: apply to every match |
| `--dry` | plan only: show stats + diff, no writes |
| `--export=<path>` | write the planned diff (or `.json`) to a file (implies `--dry`) |

Examples:

```sh
:Replace foo bar                             # picker over cwd
:Replace foo bar %                           # picker over current file
:Replace "very old" "brand new" ./src        # picker over ./src
:Replace foo "" %                            # delete matches in current file
:Replace foo bar cwd --all                   # apply to all, no picker
:Replace TODO DONE cwd --type=lua --exclude=node_modules
:'<,'>Replace foo bar                        # only within the visual selection
:Replace foo bar cwd --dry                   # preview diff + stats, no writes
:Replace foo bar cwd --export=changes.patch  # write a git-applyable patch
:Replace foo bar cwd --export=plan.json      # write a JSON change plan
:Replace foo bar cwd --to-quickfix           # send matches to the quickfix list, never writes
:Replace foo bar cwd --changed                # only git modified/staged/untracked files
:Replace foo bar cwd --changed=staged         # only staged files
```

### Surround — wrap every match

```sh
:[range]Surround[!] {pattern} [delim] [scope] [--flags]
```

A convenience layer over `:Replace` that wraps every occurrence of `{pattern}`
with a delimiter (the replacement is `<left>{pattern}<right>`). It reuses the
full pipeline — scope, picker, `--dry`, `--all`, and every flag above. `:Wrap`
is an alias. Search is always **literal** (regex would need per-match capture).

- `delim` — a literal char/string (`` ` `` `"` `'` `*` `**` `_`), a **named alias**, or a **bracket opener** (`(` `[` `{` `<`) which pairs with its closer. Omit it to be prompted.
- Aliases: `b`→`` ` ``, `q`→`"`, `s`→`'`, `star`→`*`, `bold`→`**`, `italic`→`_`, `paren`→`( )`, `bracket`→`[ ]`, `brace`→`{ }`, `angle`→`< >`.
- **Idempotent by default** — matches already wrapped by the chosen delimiter are skipped, so re-running is safe: `:Surround test **` on `**test**` leaves it as `**test**` (not `****test****`). Pass `--nested` (alias `--allow-nested`) to force another layer.

```sh
:Surround word `                 # `word`  in the current buffer
:Surround word b                 # `word`  (alias for backtick)
:Surround "foo bar" ** cwd       # **foo bar**  across the working dir
:Surround TODO ( .               # (TODO)  project-wide, all files
:Surround! name q %              # "name"  everywhere in buffer, no picker
:'<,'>Surround item *            # *item*  within the selected lines
:Surround word                   # prompt: "Surround with: "
:Surround word ** --nested       # wrap even already-**bold** matches
```

- A **charwise** Visual range (`v`) on a **single line** narrows further: only
  matches inside the selection itself are wrapped, not every match on that
  line. A linewise (`V`) or multi-line range keeps the line-span behavior
  above — narrowing to columns only makes sense with exactly one line's worth
  of them.

```sh
# "foo bar foo baz" with only the FIRST foo charwise-selected:
:'<,'>Surround foo *             # *foo* bar foo baz   (only the selected one)
# the same line with a linewise V selection:
:'<,'>Surround foo *             # *foo* bar *foo* baz (every match on the line)
```

### Regex helpers

- `:ReplaceEscape {text}` — escape `{text}` for use as a Vim regex pattern; echoes the result and copies it to the unnamed register.
- `:ReplaceTest [pattern] [sample]` — a small floating live pattern-test panel: edit the pattern (line 1) and sample text (line 2), matches highlight as you type. Close with `<Esc>` or `q`.
- Backreferences — in regex mode (`--regex`), `{new}` may use `\0`-`\9` to reference `\(...\)` capture groups from `{old}`: `:Replace "\(\w\+\)=\(\w\+\)" "\2_\1" % --regex` turns `foo=bar` into `bar_foo`.

### Monorepo / project-root detection

The `root` scope token auto-detects a project root by walking up from the
current buffer's directory (or cwd) looking for markers (`.git`, `package.json`,
`go.mod`, `Cargo.toml`, `pyproject.toml`, …). When several candidates are found
(e.g. a monorepo package with its own `package.json` nested inside a git repo),
this deterministically prefers the outermost one with `.git`, without prompting:

```sh
:Replace old new root       # e.g. resolves to the git root even from a nested package
```

For an interactive prompt when there's more than one candidate, use
`:ReplaceRoot` instead — same grammar as `:Replace` minus the scope
positional (scope is always the detected root):

```sh
:ReplaceRoot old new --dry
:ReplaceRoot! old new       # bang = --all
```

### History & Presets

- `:ReplaceHistory` — `vim.ui.select` over the last 50 real applies (never dry-run/export/quickfix); picking one re-runs it.
- `:ReplaceSavePreset {name} {old} {new} [scope] [--flags]` — save a named, reusable replace request (including flags/filters).
- `:ReplacePreset {name}` — run a saved preset exactly as saved; `<Tab>` completes names.

```sh
:ReplaceSavePreset fix-imports "import old" "import new" src/ --type=ts
:ReplacePreset fix-imports
```

Both are stored as JSON under `stdpath("data")/replacer/` (`history.json`,
`presets.json`).

### Checkpoints & Undo

`--checkpoint` snapshots every file an ALL-mode apply is about to touch
(byte-exact, current buffer content preferred over disk) into
`stdpath("data")/replacer/checkpoints/<id>/` before writing. `:ReplaceUndo
[id]` restores from a checkpoint afterward — most recent when `[id]` is
omitted, `<Tab>` completes over existing checkpoint ids. This is a plain
file snapshot (not a git stash), so it never touches unrelated
uncommitted work in the same repo.

```sh
:Replace foo bar cwd --all --checkpoint   # snapshot, then apply everywhere
:ReplaceUndo                              # restore the most recent checkpoint
:ReplaceUndo 20240131-101530-4821         # restore a specific one
```

### Batch Replaces

`:ReplaceBatch[!] {source} [scope] [--flags]` runs multiple `{old → new}`
pairs in one invocation — each pair is dispatched as its own full `:Replace`
run (search + apply, sequentially, non-interactive), so it gets the exact
same pipeline (dry-run, filters, checkpoints, hooks, history, …) as a normal
`:Replace!`.

`{source}` is a file path, or one of `clipboard`/`+`, `unnamed`/`"`, `qf`/`quickfix`.
Pairs are one `old => new` per line (`#` comments and blank lines ignored),
or a `[{"old":"...","new":"..."}, ...]` JSON array (auto-detected from a
leading `[`):

```sh
:ReplaceBatch pairs.txt src/          # from a file
:ReplaceBatch clipboard cwd --dry     # from the clipboard, plan-only first
:ReplaceBatch pairs.json .            # every pair applies non-interactively (no picker — the ! is implied and optional)
```

### Renaming Files & Directories

`:ReplaceFNames[!] {old} {new} [scope] [--dry]` renames every file/directory
under `scope` whose *basename* contains `{old}` (literal substring) — this is
about names, not file contents. Renames are computed from one snapshot of
the tree; when a match is nested inside another match, only the outer one is
renamed this run (the inner one moves along for free) — re-run to catch it
on its own if its name still matches afterward.

```sh
:ReplaceFNames old_prefix new_prefix src/ --dry   # preview first
:ReplaceFNames! old_prefix new_prefix src/         # bang = non-interactive
```

Does not follow the rename through source references (imports/requires)
across the project — see [Rename-Assist](#rename-assist) for the narrower,
single-file case that pairs a content replace with renaming that same file.

### Rename-Assist

`--also-rename-file` pairs a single-file content replace with an offer to
also rename the file itself the same way — e.g. renaming a class and its
file in one go. Scoped to single-file scope only (`%`/`buf` or an explicit
file path — never a directory tree; use [`:ReplaceFNames`](#renaming-files--directories)
for that). A no-op (no prompt at all) when the file's own basename doesn't
contain `{old}`.

```sh
:Replace MyWidget MyButton % --also-rename-file --all
" content replaced; if the file is named e.g. MyWidget.lua, you're asked:
" "Also rename MyWidget.lua -> MyButton.lua?"
" (the file rename is a literal substring match on the basename, independent
" of --case-preserve, which only affects replaced content)
```

### Soft LSP Integration

`--lsp` tries an LSP-driven rename (a proper workspace-wide symbol rename,
via `textDocument/rename`) for each match whose old *and* new text both look
like a plain identifier (letters/digits/underscore only) and whose buffer
has an attached LSP client that supports rename — always falling back to
the normal plain-text replace otherwise (no client, non-identifier text, or
the request fails/times out). Position-based, not cursor-based, so it never
moves your cursor or window even when triggered from a picker.

```sh
:Replace MyWidget MyButton cwd --lsp --all
```

This is genuinely best-effort: mixed results (some matches LSP-renamed,
others plain-text) are normal and expected in one run.

### Streaming Collection

`--stream` switches ripgrep collection to an incremental `--json` parser
(`rg.collect_streaming`) instead of parsing the whole output at the end,
giving smoother, filter-aware progress updates while a large search is
still running.

**Scope note:** the picker itself still only opens once collection
finishes — true live picker fill (select matches while ripgrep is still
running) is not implemented yet. This flag ships the collection-layer
infrastructure for it (proven equivalent to the non-streaming collector by
test, see `TESTS/feature_smoke.lua`); wiring it into the pickers themselves
is a follow-up, deliberately deferred given the integration risk of
terminal-UI live-population code that can't be verified by an automated
test suite. See `lua/replacer/rg.lua`'s `collect_streaming` docstring.

### i18n / Messages

Override any of the following message templates via `messages` in `setup()`
(each is a `string.format` template; a malformed override is shown verbatim
rather than erroring), and/or suppress routine info-level notifications
entirely with `quiet = true` (warnings/errors always show):

| Key | Default | Args |
| --- | --- | --- |
| `confirm_all` | `Apply ALL %d spot(s) across %d file(s)?` | spots, files |
| `confirm_all_short` | `Apply replacement to ALL %d spot(s)?` | spots |
| `cancelled` | `cancelled` | — |
| `result` | `%d spot(s) in %d file(s)` | spots, files |
| `no_matches` | `no matches found` | — |
| `surround_prompt` | `Surround with: ` | — |
| `surround_cancelled` | `Surround: cancelled (no delimiter)` | — |

```lua
require("replacer").setup({
  quiet = false,
  messages = {
    no_matches = "keine Treffer",
    result = "%d Fundstelle(n) in %d Datei(en)",
  },
})
```

### Hooks

Lua before/after callbacks around the apply pipeline — run a linter/formatter,
invalidate a cache, log every change, etc. Two ways to register:

```lua
require("replacer").setup({
  hooks = {
    before_apply = function(ctx) -- ctx = { path, matches, new_text }
      if ctx.path:match("%.generated%.lua$") then return false end -- veto: skip this file
    end,
    after_write = function(ctx) -- ctx = { path, bufnr, ok }
      if ctx.ok then vim.system({ "stylua", ctx.path }) end
    end,
  },
})

-- or programmatically, in addition to config.hooks:
require("replacer.hooks").on("after_apply", function(ctx) -- ctx = { path, spots, skipped }
  print(string.format("%s: %d spot(s)", ctx.path, ctx.spots))
end)
```

Events: `before_apply` (may return `false` to skip/veto that file), `after_apply`,
`before_write`, `after_write` — all fire once per file. A hook error is caught
and warned, never aborts the apply.

### Picker Keymaps

All keys except `<CR>` (apply) are configurable via `keymaps` in `setup()` —
defaults match the behavior below exactly:

- `<Tab>` / `<S-Tab>`: toggle selection, move next/previous (`keymaps.toggle_select` / `toggle_select_prev`)
- `<CR>`: apply to the selected entry/entries (fixed — the picker's own default key)
- `<C-a>`: replace ALL matches at once, respects `confirm_all` (`keymaps.apply_all`)
- `<C-r>`: apply the entry under cursor, reopen the picker with the remaining matches (`keymaps.replace_and_reopen`)
- `<Esc>`: 1st press leaves terminal-insert/insert mode (fixed); 2nd press (normal mode) closes the picker (`keymaps.quit`)

Full reference (incl. which-key support per backend, usrcmds, and the
explicit "no autocmds" note): [`docs/BINDINGS.md`](docs/BINDINGS.md).

______________________________________________________________________

## Features

- Project-wide search using ripgrep `--json` for precise match coordinates
- **Native `vimgrep` fallback** when ripgrep is not installed (no external dep)
- Interactive selection via `fzf-lua` or `telescope.nvim`, **auto-detected** (`engine = "auto"`)
- Every occurrence per line is a separate, selectable entry
- Live context preview around each match
- Replace only the selected occurrences; or replace all at once
- **Dry-run** (`--dry`) with a stats summary and a diff preview — no writes
- **Export** the planned change as a git-applyable `.patch` or `.json` (`--export=`)
- **`--checkpoint` / `:ReplaceUndo`** — snapshot touched files before an ALL apply, restore them afterward
- Per-run **flags** (`--regex`, `--type=`, `--glob=`, `--exclude=`, …) and config defaults
- **Range** support: `:'<,'>Replace` limits to the selected lines
- **`:Surround` / `:Wrap`** — wrap every match with a delimiter (backticks, quotes, `**`, brackets, …)
- Guarded, bottom-up in-buffer edits to avoid offset shift bugs
- Optional write-to-disk on apply (or keep changes unsaved)
- BOM/CRLF-aware raw file reads (native vimgrep backend + dry-run/export), matching what a Neovim buffer would show for the same file
- Strong EmmyLua annotations and type hints for LuaLS
- Clean, modular code layout (search, apply, export, pickers, command, config)

______________________________________________________________________

## Roadmap

See [`docs/FEATURES.md`](docs/FEATURES.md) for what shipped and where it
lives in the codebase, and [`docs/ROADMAP.md`](docs/ROADMAP.md) for what's
still planned.

______________________________________________________________________

## Installation

**Requirements;**

- Neovim 0.9 or newer
- ripgrep (`rg`) in `PATH` — *recommended*; without it the native `vimgrep` backend is used automatically
- One picker:
  - `ibhagwan/fzf-lua`, or
  - `nvim-telescope/telescope.nvim` (+ `nvim-lua/plenary.nvim`)

### With Lazy.nvim

**Minmal:**

```lua
{
  "StefanBartl/replacer.nvim",
  cmd = { "Replace", "Replacer", "Surround", "Wrap" }, -- lazy-load on first use
  dependencies = { "StefanBartl/lib.nvim" },
  opts = {}, -- engine already defaults to "auto" (fzf-lua first, then telescope)
}
```

**With configuration:**

```lua
{
  "StefanBartl/replacer.nvim",
  cmd = { "Replace", "Replacer", "Surround", "Wrap" }, -- lazy-load on first use
  dependencies = { "StefanBartl/lib.nvim" },
  opts = {
    engine = "auto",           -- picker: "auto" | "fzf" | "telescope"
    search_engine = "auto",    -- backend: "auto" | "ripgrep" | "vimgrep"
    progress_style = "auto",   -- "auto" | "notify" | "statusline" | "fidget" | "float" | "kit" (needs lib.nvim)
                               -- "float"/"kit": small window, bottom-right, never steals focus;
                               -- focus it + <Esc> asks (English prompt) to abort the search
                               -- ("kit" is themed via lib.nvim.ui.kit's preset system)
    write_changes = true,      -- write buffers after replace
    confirm_all = true,        -- ask before replacing all
    preview_context = 3,       -- lines of context in preview
    hidden = true,             -- include dotfiles
    git_ignore = true,         -- respect .gitignore
    exclude_git_dir = true,    -- skip .git/ explicitly
    literal = true,            -- fixed-strings by default
    smart_case = true,         -- ripgrep -S
    preserve_whitespace = false, -- keep a match's own leading/trailing ws around the replacement
    case_preserve = false,     -- re-case the replacement to match each match's case style
    word_boundary = false,     -- keep only whole-word matches
    code_only = false,         -- skip matches inside strings/comments (Tree-sitter, best-effort)
    safe_mode = false,         -- skip read-only/oversized/binary files
    max_file_size = 5 * 1024 * 1024, -- bytes; only enforced when safe_mode is true
    skip_binary = true,        -- only enforced when safe_mode is true

    default_scope = "%",          -- "%", "cwd", ".", or <path>
    confirm_wide_scope = false,   -- ask once for permission if scope ≠ "%"

    file_types = {},              -- default ripgrep --type filters, e.g. { "lua" }
    globs = {},                   -- default include globs, e.g. { "*.lua" }
    exclude = {},                 -- default exclude patterns, e.g. { "node_modules" }

    keymaps = {                -- picker keymaps (buffer-local); shown values are the defaults
      toggle_select = "<Tab>",
      toggle_select_prev = "<S-Tab>",
      apply_all = "<C-a>",
      replace_and_reopen = "<C-r>",
      quit = "<Esc>",
    },

    fzf = {                    -- extra fzf-lua options (optional)
      winopts = { width = 0.85, height = 0.70 },
    },
    telescope = {              -- extra telescope options (optional)
      layout_config = { width = 0.85, height = 0.70 },
    },
  },
}
```

### With packer.nvim

```lua
use({
  "StefanBartl/replacer.nvim",
  cmd = { "Replace", "Replacer", "Surround", "Wrap" }, -- lazy-load on first use
  requires = { "StefanBartl/lib.nvim" }, -- required: command layer + progress indicator
  config = function()
    require("replacer").setup({
      engine = "auto",
    })
  end,
})
```

______________________________________________________________________

## Configuration

**Available Options:**

| Option          | Type    | Description                                                    |
| --------------- | ------- | -------------------------------------------------------------- |
| engine          | string  | Picker UI: "auto" / "fzf" / "telescope" ("auto" → fzf-lua if present, else telescope) |
| search_engine   | string  | Match backend: "auto" / "ripgrep" / "vimgrep" ("auto" → ripgrep if present, else vimgrep) |
| progress_style  | string  | Progress indicator style (requires [`lib.nvim`](#with-lazynvim), silently skipped otherwise): "auto" / "notify" / "statusline" / "fidget" / "float" / "kit" — see [Progress Indicator](#progress-indicator) |
| write_changes   | boolean | Write modified buffers on apply (true) or keep unsaved (false) |
| confirm_all     | boolean | Ask confirmation before replacing all matches at once          |
| confirm_wide_scope | boolean | Extra confirmation for non-buffer (cwd/dir) ALL applies      |
| preview_context | integer | Context lines shown in preview around the hit                  |
| hidden          | boolean | Include dotfiles (`--hidden`)                                  |
| git_ignore      | boolean | Respect .gitignore (false → `--no-ignore`)                     |
| exclude_git_dir | boolean | Exclude `.git` directory explicitly (`--glob !.git`)           |
| literal         | boolean | Literal search (`--fixed-strings`); set false for regex mode   |
| smart_case      | boolean | Smart-case (`-S`)                                              |
| default_scope   | string  | Scope used when none is given (`%`, `cwd`, `.`, or `<path>`)    |
| file_types      | string[] | Default filetype filters (ripgrep `--type`)                   |
| globs           | string[] | Default include glob patterns                                 |
| exclude         | string[] | Default exclude path/glob patterns                            |
| preserve_whitespace | boolean | Keep a match's own leading/trailing whitespace around the replacement (default: false) |
| case_preserve   | boolean | Re-case the replacement to match each match's own case style (default: false) |
| word_boundary   | boolean | Keep only whole-word matches (default: false) |
| code_only       | boolean | Skip matches inside strings/comments, Tree-sitter best-effort (default: false) |
| confirm_per_file | boolean | ALL-mode: ask All/Skip/Only-some/Quit per file, supersedes confirm_all (default: false) |
| checkpoint      | boolean | ALL-mode: snapshot touched files first for `:ReplaceUndo` (default: false) |
| hooks           | table?  | Before/after callbacks around the apply pipeline: `{ before_apply, after_apply, before_write, after_write }`, each a function or list of functions |
| messages        | table?  | Override any [message template](#i18n--messages) by key (`string.format` templates) |
| quiet           | boolean | Suppress routine info-level notifications; warnings/errors still show (default: false) |
| safe_mode       | boolean | Skip read-only/oversized/binary files instead of touching them (default: false) |
| max_file_size   | integer | Bytes; only enforced when safe_mode is true (default: 5 MiB) |
| skip_binary     | boolean | Only enforced when safe_mode is true (default: true) |
| fzf             | table?  | Extra options for `fzf-lua` (merged into picker opts)          |
| telescope       | table?  | Extra options for Telescope picker (theme/layout)              |

**Full example:**

```lua
require("replacer").setup({
  engine = "auto",           -- "auto" | "fzf" | "telescope"
  search_engine = "auto",    -- "auto" | "ripgrep" | "vimgrep"
  progress_style = "auto",   -- "auto" | "notify" | "statusline" | "fidget" | "float" | "kit"
  default_scope = "%",
  write_changes = true,
  confirm_all = true,        -- affects <C-a> and :Replace!
  confirm_wide_scope = false,
  preview_context = 3,
  hidden = true,
  exclude_git_dir = true,
  literal = true,
  smart_case = true,
  preserve_whitespace = false,
  case_preserve = false,
  word_boundary = false,
  code_only = false,
  safe_mode = false,
  max_file_size = 5 * 1024 * 1024,
  skip_binary = true,
  file_types = {},           -- e.g. { "lua" }
  globs = {},                -- e.g. { "*.lua" }
  exclude = {},              -- e.g. { "node_modules" }
  fzf = { winopts = { width = 0.85, height = 0.70 } },
  telescope = { layout_config = { width = 0.85, height = 0.70 } },
})
```

______________________________________________________________________

## Progress Indicator

On a large `cwd` scope (many projects/files) a search can take a few seconds.
Replacer reports on this via [`lib.nvim`](https://github.com/StefanBartl/lib.nvim)'s
[`lib.nvim.progress`](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/progress/README.md)
module — an **optional** dependency (see [Installation](#installation)). Without it,
everything works exactly as before, just silently without any indicator.

Configure it with `progress_style` (default `"auto"`):

| Style         | What it does                                                                 | Extra dependency |
| ------------- | ----------------------------------------------------------------------------- | ---------------- |
| `"auto"`      | Prefers `"fidget"` when `fidget.nvim` is installed, else `"notify"`. Never picks `"float"`/`"kit"` on its own. | none (uses whatever is present) |
| `"notify"`    | `vim.notify`; updated in place if your notify backend supports it (e.g. [nvim-notify](https://github.com/rcarriga/nvim-notify)), otherwise one notification per update. | none |
| `"statusline"`| Headless — nothing is drawn by replacer itself. You read the live text from your own statusline component (see below). | none |
| `"fidget"`    | Renders through [fidget.nvim](https://github.com/j-hui/fidget.nvim)'s LSP-style progress corner. | `fidget.nvim` |
| `"float"`     | A small floating window, bottom-right, that never steals focus. Focus it deliberately and press `<Esc>` (normal mode) to get a confirm prompt — "Yes" aborts the running search, "No" (or leaving the window) keeps it running. | none |
| `"kit"`       | Same interaction as `"float"` (focus + `<Esc>` to cancel), but rendered through [`lib.nvim.ui.kit`](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/ui/kit/README.md)'s themed `surface` — matches your configured ui.kit preset (border/highlights) instead of a fixed look. | none (part of `lib.nvim`) |

A search only ever becomes visible after ~150ms, so a fast search on a small
scope never flashes any UI — regardless of style.

### Using the `"statusline"` style

This style deliberately draws nothing; it exists so you can fold the current
search status into your **own** statusline instead of getting a separate
notification/float. Read the active text(s) from
`lib.nvim.progress.styles.statusline`:

```lua
local replacer_status = require("lib.nvim.progress.styles.statusline")

local function my_statusline_component()
  local active = replacer_status.active() -- string[], oldest first, e.g. { "[replacer] 42 match(es) found… (3/9)" }
  if #active == 0 then
    return "" -- nothing running right now
  end
  return table.concat(active, " | ")
end
```

`active()` returns every currently in-flight progress text across **all**
plugins using this style (not just replacer), oldest first — one line per
handle. It updates live as `h:update(...)` is called and clears itself on
`finish`/`cancel`, so you never need to poll or clean up. Every change also
triggers `:redrawstatus`, so your component refreshes even while you're
sitting idle watching the search run — not just on the next unrelated redraw.

See [`docs/progress-indicator.md`](docs/progress-indicator.md) for a deeper
walkthrough (all styles, `--` interaction with `--dry`, and copy-pasteable
statusline snippets for lualine/vanilla `statusline`).

______________________________________________________________________

## Safety & Notes

- Use `--dry` (or `--export=`) first to review the exact diff before touching any file.
- Edits are applied bottom-up per file, each guarded with `pcall`, to avoid index shift and partial-failure issues.
- Each occurrence is verified against the original text before editing; mismatches are skipped and reported.
- When `write_changes = false`, buffers stay modified—review and `:write` manually or use VCS hunk staging.
- Literal mode is the default; for regex, use `--regex` (or set `literal = false`).
- ripgrep is recommended; if it is not on `PATH`, the native `vimgrep` backend is used automatically (no `.gitignore`/rich `--type` support in that mode). Declared in [`docs/install.json`](docs/install.json), parsed by lib.nvim's [`deps` module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md) — a popup explains this on first `setup()` after installing, `:Lib deps show replacer.nvim` repeats it, also folded into `:checkhealth replacer`. Disable it right in this plugin's own spec: `require("replacer").setup({ deps_popup = false })`. `vim.g.lib_nvim_deps_disable_first_run = true` (every plugin) / `vim.g.lib_nvim_deps_disabled_plugins = { "replacer.nvim" }` also still work, for turning it off without touching any plugin's config.

______________________________________________________________________

## Development

- Repository layout follows standard `lua/<plugin_name>/...` convention for Lazy.nvim.
- Type hints use EmmyLua; LuaLS-friendly stubs are provided where helpful.
- To hack locally, add your repo via `dir = "/path/to/replacer"`.
- Typical debug flow:
  - `:Replace foo bar cwd`
  - In picker, inspect preview; Tab to select specific hits; Enter to apply
  - Ctrl-A to replace all with confirmation
  - Set `write_changes=false` to review changes before writing

**Running checks locally** (same checks CI runs on every push/PR, see
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)):

```sh
make lint       # luacheck lua/
make fmt-check  # stylua --check lua/
make test       # headless test suite (requires lib.nvim on the runtimepath)
make check      # all three
```

The test suite requires [`lib.nvim`](https://github.com/StefanBartl/lib.nvim)
on the runtimepath (the plugin's hard dependency), e.g.:

```sh
nvim --headless -u NONE -c "set rtp+=." -c "set rtp+=/path/to/lib.nvim" \
  -c "luafile TESTS/feature_smoke.lua" -c "qa"
```

______________________________________________________________________

## Disclaimer

ℹ️ This plugin is under active development – some features are planned or experimental.
Expect changes in upcoming releases.

______________________________________________________________________

## Feedback

Your feedback is very welcome!

Please use the [GitHub issue tracker](https://github.com/StefanBartl/replacer/issues) to:

- Report bugs
- Suggest new features
- Ask questions about usage
- Share thoughts on UI or functionality

For general discussion, feel free to open a [GitHub Discussion](https://github.com/StefanBartl/replacer/discussions).

If you find this plugin helpful, consider giving it a ⭐ on GitHub — it helps others discover the project.

______________________________________________________________________
