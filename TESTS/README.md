# TESTS

Standalone Lua scripts, not a `plenary`/`busted` suite. Each file is a
self-contained headless test run via `nvim -l TESTS/<name>.lua` or
`nvim --headless -u NONE -c "luafile TESTS/<name>.lua" -c "qa"` — there is no
shared `run.lua` aggregator and no `_spec` suffix convention.

## Running a suite

Every suite that requires the plugin needs `lib.nvim` and `ui.nvim` on the
runtimepath (hard dependencies of `replacer.notify`/`replacer.gitfiles` and
`replacer.init`'s `ui.kit.confirm` require, respectively). `refine_wiring.lua`
additionally uses `pickers.nvim` as a soft dependency (only the picker
`filter` key needs it — its checks are skipped with a note when absent).

```sh
nvim --headless -u NONE \
  -c "set rtp+=." -c "set rtp+=./lib.nvim" -c "set rtp+=./ui.nvim" \
  -c "luafile TESTS/feature_smoke.lua" -c "qa"
```

`TESTS/resolve_lib_nvim.lua`/`resolve_ui_nvim.lua` are shared helpers each
suite `dofile()`s at the top (never `require`d — they have to run *before*
either dependency is on the path). They look for `$LIB_NVIM_PATH`/
`$UI_NVIM_PATH` first, then a sibling checkout (`../lib.nvim`, `../ui.nvim`),
then the lazy.nvim-managed copy under `stdpath("data")/lazy`.
`$PICKERS_NVIM_PATH` follows the same pattern for `refine_wiring.lua`
(resolved inline there, not via a shared helper — it is soft, not hard).

See `.github/workflows/ci.yml` for the exact invocation of every file below.

## Suites (CI-run)

- `feature_smoke.lua` — the bulk of the plugin: request parsing, native
  (vimgrep) search incl. word-boundary/safe-mode/encoding, root detection,
  `--changed` (gitfiles), per-file confirm, checkpoints, hooks, history,
  presets, batch mode, i18n messages, filename/directory rename (`fnames`),
  `--also-rename-file`, soft LSP rename, `--stream`, pure edit computation,
  dry-run/export/patch/JSON, real apply (incl. the wide/chunked async path),
  and quickfix export.
- `gitfiles_equivalence.lua` — `--changed` against git itself: for every kind
  combination the selection must equal raw `git … -z` (unstaged/staged/both,
  added, deleted, renamed, nested and space-named untracked, ignored, non-ASCII
  names, unmerged paths, byte-order sorting), one `git status` process for all
  three kinds, and failure reporting for a broken repository.
- `surround_smoke.lua` — `:Surround`/`:Wrap`: delimiter resolution, the
  shared command tokenizer/flag helpers, the real user command end-to-end
  (buffer/dir scope, no-delimiter prompt via `ui.kit`), and idempotency
  (skip-already-wrapped vs. `--nested`).
- `async_utf8.lua` — the async ripgrep collection path, and UTF-8 (umlauts +
  emoji) byte-offset correctness through search/compute/apply.
- `refine_wiring.lua` — `replacer.pickers.common`'s `without()` and the
  `pickers.refine` handle (`new_refine()`) stacked path/content filters.
- `config_merge.lua` — `replacer.config`/`replacer.config.DEFAULTS`: every
  coercer (`as_bool`/`as_pos_int`/`as_engine`/`as_search_engine`/
  `as_progress_style`/`as_string_list`/`as_keymaps`), the nested `fzf`/
  `telescope` deep-merge, and `setup()`/`get()`/`resolve()`'s merge
  semantics (`setup()` is cumulative, not a reset — see the file's own
  comments).
- `argtypes_debug_error.lua` — `replacer.argtypes`'s two custom composer
  argument types (`RP_RG_TYPE`/`RP_CHANGED_KINDS`, fetched back through
  `lib.nvim`'s own argtype registry), `replacer.debug`'s `:ReplaceDebug`
  dispatch, and `replacer.error`'s structured errors / `safe_call` envelope.
- `health_pickers_tscode.lua` — `replacer.health` (`vim.health` stubbed to
  capture the report regardless of which optional tools happen to be
  installed), the picker-engine-agnostic halves of
  `replacer.pickers.common`/`replacer.pickers.utils`, `replacer.tscode`'s
  real Tree-sitter string/comment classification, and a smoke check of
  `replacer.util.notify`.
- `bindings_wiring.lua` — `replacer.bindings.{init,usrcmds,keymaps,
  autocmds}`: the command registry/`names()`, `bindings.setup()`
  end-to-end, both `:ReplaceTest` panel close keys, the panel's
  `TextChanged`/`TextChangedI` re-highlight autocmd, and the real
  `:ReplaceTest` float driving both.
- `init_dispatch.lua` — `replacer/init.lua`'s orchestration: the legacy
  positional `run(old, new, scope, all)` form, the dry-run/export "plan"
  path (incl. the `[replacer-plan]` diff scratch buffer), the
  "no picker available" fallback when neither fzf-lua nor telescope.nvim is
  installed, the post-collection `request.filter` hook, the real
  (non-stubbed-apply) confirm-before-ALL flow, `confirm_wide_scope` vs.
  single-file scope, and dispatch's own `cfg.checkpoint`/
  `cfg.confirm_per_file` wiring (as opposed to those two modules' isolated
  unit tests in `feature_smoke.lua`, which drive them with a fake
  `apply_func`).
- `pickers_backends.lua` — `replacer.pickers.fzf`/`replacer.pickers.telescope`'s
  `run()`, with the actual backend (`fzf-lua` / `telescope.nvim`) stubbed at
  `package.loaded` instead of skipped: candidate/entry-maker construction,
  the id-tag lookup both reopen paths use, every `attach_mappings`/`actions`
  entry (default apply, multi-select, apply-all incl. the real
  `confirm_all` → `ui.kit.confirm` flow, replace-and-reopen's recursive
  re-run with the match removed, and the `<C-f>` filter guard when
  pickers.nvim is absent), the telescope previewer's highlight-extmark math,
  and fzf's `<C-a>`/`<S-Tab>`/`<M-x>`/bare-`<CR>` → `ctrl-a`/`shift-tab`/
  `alt-x`/`enter` key-notation translator. Only the one call each adapter
  makes into the real rendering UI (`fzf.fzf_exec`/`picker:find()`) is
  replaced with a capture stub; everything upstream of it is this plugin's
  own logic, not the backend's.

## Present but not run by CI

- `resolve_lib_nvim.lua` / `resolve_ui_nvim.lua` — shared `dofile()` helpers,
  not test files themselves.
- `health_debug.lua` / `utf8_offsets.lua` — pre-existing standalone
  diagnostic/legacy scripts (`:lua require('test.health_debug').diagnose()`
  style), never wired into `.github/workflows/ci.yml`. Left as-is; their
  real assertions now live in `argtypes_debug_error.lua` (`:ReplaceDebug`)
  and `async_utf8.lua`/`feature_smoke.lua` (UTF-8 offsets).

## Deliberately excluded from any suite

- The actual rendering call inside `pickers/fzf.lua` (`fzf.fzf_exec`) and
  `pickers/telescope.lua` (`picker:find()`'s real floating window / keypress
  loop) — a live picker UI genuinely rendering is the one part of those two
  files `pickers_backends.lua` does not (and should not) exercise. Everything
  else in both `run()` functions is covered there; see that suite's entry
  above. (An earlier round excluded both files outright on the premise that
  they "hard-require an actual picker backend... neither of which is a CI
  sibling checkout" — true of the literal `require`, but that require only
  needs *something* in `package.loaded`, which doesn't need a real plugin
  checkout, in CI or anywhere else.)
- `@types`/`types/*.lua` — pure `---@meta` annotations, no runtime code.
- `pickers/utils.lua`'s `setup_highlight_groups`/`ansi_snippets` — not a
  backend-availability exclusion: as of this audit neither function has any
  caller anywhere in the codebase (see the "NOTE: nothing calls this today"
  comment on `setup_highlight_groups` itself). Each function is still tested
  directly by `health_pickers_tscode.lua`; there is no caller left to cover.

## Known bugs (pinned as regression tests, not fixed)

- `replacer.health.check()`: `check_lib_nvim()` already handles
  `lib.nvim.bindings.usercmd.composer` being unavailable — it reports
  `health.error("lib.nvim not found — commands will fail to register", ...)`
  and lets `M.check()` carry on. But `M.check()` itself then unconditionally
  calls `require("lib.nvim.bindings.usercmd.composer").checkhealth("Replace")`
  / `.checkhealth("Surround")` a few lines later (the "composer route
  pre-flight"), with no guard — so on a lib.nvim checkout old enough to be
  missing just that one submodule, `:checkhealth replacer` reports the clean
  warning and then crashes on the exact same missing dependency instead of
  degrading to it. Pinned in `health_pickers_tscode.lua` (section 6, via a
  `package.preload` stub that makes the require genuinely fail rather than
  swapping in a fake module) rather than fixed here, per this campaign's rule
  for a real behavior bug that isn't a trivial, zero-risk infra fix — the
  right degradation (skip the pre-flight entirely? report a third error
  section instead?) is a product decision, not this audit's to make quietly.

## Bugs found while writing these suites (since fixed)

- `replacer.config.get()`'s docstring promised "a deep copy, to avoid
  accidental mutation by callers", but it was implemented as
  `vim.tbl_deep_extend("force", {}, state)`. That call only deep-merges a
  sub-table when *both* sides being merged already have a table at that key —
  a key that exists on only one side (every key here, since the first
  argument is `{}`) was assigned by reference. Every nested table `get()`
  returned (`keymaps`, `fzf`, `telescope`, `hooks`, `messages`,
  `file_types`/`globs`/`exclude`) was therefore the *same table object*
  backing the module's private `state`; mutating what looked like a
  read-only snapshot silently corrupted persistent config for the rest of
  the session. Fixed to `vim.deepcopy(state)`; `config_merge.lua` asserts
  nested tables are no longer aliased.
- `replacer.debug`'s `enable()`/`disable()`/`status()` wrote/read
  `require("replacer").options.ext_highlight_opts.debug` — a field
  `init.lua` never exposed, so the config-echo half of `status()`'s message
  always reported "OFF" regardless of real state. Removed (dead code with
  no consumer); `status()` now only reports the module-local flag.
  Separately, `M.test()` required `"test.utf8_offsets"`, which resolves to
  `lua/test/utf8_offsets.lua` on the runtimepath — but the real suite lives
  at `TESTS/utf8_offsets.lua`, outside `lua/`'s search path, so `:ReplaceDebug
  test` always reported "Test suite not found". Fixed to load the suite by
  file path (relative to `debug.lua`'s own location) instead of `require()`.
  Both pinned and verified fixed in `argtypes_debug_error.lua`.
