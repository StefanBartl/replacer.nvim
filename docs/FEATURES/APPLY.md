# Apply

What happens once matches are collected and you commit to changing them:
planning without writing, safety nets around the write itself, and
extensibility hooks around the whole pipeline.

## Plan/review without applying

`--dry` computes stats and a diff without writing anything; `--export`
writes the plan as a patch or JSON file instead of (or alongside) showing
it.

- **Module:** `export.lua` (`M.build_results`, `M.build_patch`,
  `M.build_json`, `M.write_export`), `init.lua` (`plan`)
- **Usercmds:** `--dry`, `--export={path}` flags on `:Replace`

## Safe-mode

`--safe` skips read-only, oversized, and binary files instead of touching
them, once enabled.

- **Module:** `apply.lua` (`safe_mode_skip_reason`, `is_binary_file`)
- **Config:** `opts.safe_mode` (default `false`), `opts.max_file_size`
  (default 5 MiB), `opts.skip_binary` (default `true`)
- **Usercmds:** `--safe` flag on `:Replace`

## Quickfix/location-list export

`--to-quickfix` / `--to-loclist` send the raw match list to the
quickfix/location list and open it, without writing any changes.

- **Module:** `export.lua` (`M.to_qf_entries`, `M.send_to_quickfix`)
- **Usercmds:** `--to-quickfix`, `--to-loclist` flags on `:Replace`

## Per-file confirmation

`--confirm-per-file` prompts All/Skip/Only-some/Quit for each file
individually instead of one global "apply ALL?" confirmation; supersedes
`confirm_all`/`confirm_wide_scope` when enabled.

- **Module:** `perfile.lua` (`M.run`)
- **Config:** `opts.confirm_per_file` (default `false`)
- **Usercmds:** `--confirm-per-file` flag on `:Replace`

## Checkpoint + undo

`--checkpoint` snapshots every about-to-be-touched file before an ALL apply;
`:ReplaceUndo [id]` restores files from that snapshot (most recent when
`[id]` is omitted).

- **Module:** `checkpoint.lua` (`M.create`, `M.list`, `M.undo`,
  `M.register`)
- **Config:** `opts.checkpoint` (default `false`)
- **Usercmds:** `--checkpoint` flag on `:Replace`, `:ReplaceUndo [id]` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))

## Hook system

`config.hooks` (via `setup()`) and `require("replacer.hooks").on(event, fn)`
(programmatically) both register `before_apply`/`after_apply`/
`before_write`/`after_write` callbacks around the apply pipeline. Config
hooks run first; a hook error is caught and warned, never allowed to abort
the apply. A `before_apply` hook may return `false` to veto (skip) that
file.

- **Module:** `hooks.lua` (`M.on`, `M.run`, `M.clear`)
- **Config:** `opts.hooks` (`{ before_apply = fn|fn[], ... }`, default `{}`)

## Soft LSP-driven rename

`--lsp` tries an LSP-driven rename first for matches whose old/new text both
look like plain identifiers and whose buffer has an LSP client that
supports rename; always falls back to a plain text edit otherwise.

- **Module:** `lsp_rename.lua` (`M.looks_like_identifier`,
  `M.try_rename_batch`)
- **Config:** `opts.lsp` (default `false`)
- **Usercmds:** `--lsp` flag on `:Replace`
