# Batch, history, presets & project

Running more than one replace in a single command, extending replace to
file/directory names instead of content, and the tooling around the repo
itself.

## Batch replace

`:ReplaceBatch[!] {source} [scope] [--flags]` runs multiple `{old → new}`
pairs in one command, sourced from a file, the clipboard, or the quickfix
list — one full `:Replace` dispatch per pair.

- **Module:** `batch.lua` (`M.parse`, `M.run`, `M.register`)
- **Usercmds:** `:ReplaceBatch[!] {source} [scope] [--flags]` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))

## History

`:ReplaceHistory` shows a `vim.ui.select` picker over the last 50 applies
and re-runs the chosen one.

- **Module:** `history.lua` (`M.add`, `M.pick`, `M.register`)
- **Usercmds:** `:ReplaceHistory` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))

## Named presets

`:ReplaceSavePreset {name} {old} {new} [scope] [--flags]` saves a named,
reusable replace request; `:ReplacePreset {name}` re-runs it exactly as
saved, with `<Tab>` completion over saved names.

- **Module:** `presets.lua` (`M.save`, `M.as_request`, `M.names`,
  `M.register`)
- **Usercmds:** `:ReplaceSavePreset {name} {old} {new} [scope] [--flags]`,
  `:ReplacePreset {name}` (see [BINDINGS.md](../BINDINGS.md#user-commands))

## Rename files/directories by name

`:ReplaceFNames[!] {old} {new} [scope] [--dry]` renames every file/directory
under scope whose basename matches `{old}` — a nested match is skipped in
favor of its already-renamed ancestor, instead of content search-and-replace.

- **Module:** `fnames.lua` (`M.collect`, `M.filter_nested`, `M.apply`,
  `M.register`)
- **Usercmds:** `:ReplaceFNames[!] {old} {new} [scope] [--dry]` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))

## Pair content replace with file rename

`--also-rename-file` pairs a single-file content replace with renaming that
file, when the old/new text also matches the file's own basename. Scoped to
single-file replaces only — a directory tree is `:ReplaceFNames`' job.

- **Module:** `rename_assist.lua` (`M.maybe_rename`)
- **Usercmds:** `--also-rename-file` flag on `:Replace`

## GitHub repo metadata

The repository's description and topics on GitHub are filled in, so the
repo is discoverable and self-describing outside the plugin's own docs.

## CI workflow

`.github/workflows/ci.yml` runs luacheck, stylua, and the headless test
suite on every push/PR.

- **Module:** `.github/workflows/ci.yml`
