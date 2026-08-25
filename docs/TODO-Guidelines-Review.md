# TODO – guidelines review of `replacer`

**Status: all 10 points implemented & verified via `TESTS/feature_smoke.lua` (22/22).**

- [x] 1. Multiple occurrences per line → one picker entry each (ripgrep & vimgrep). *(rg.lua `find_all_occurrences`)*
- [x] 2. `--literal` / `--no-literal` / `--regex` (+ further options) as command flags. *(command.lua)*
- [x] 3. Comments/docs: all new modules annotated in detail; README + `doc/replacer.txt` updated.
- [x] 4. `search_engine = "ripgrep"|"vimgrep"|"auto"`; vimgrep as the automatic fallback when `rg` is missing. *(rg.lua `pick_backend`)*
- [x] 5. Picker auto-detect: `engine="auto"` → fzf-lua if present, otherwise telescope. *(init.lua `pick_picker`)*
- [x] 6. Range support: `:'<,'>Replace` limited to the line range. *(command.lua `range=true`)*
- [x] 7. Clear error messages (missing / too many / unknown option), deferred notify. *(command.lua)*
- [x] 8. Filters as arguments `--type=` / `--glob=` / `--exclude=` + in the config (`file_types`/`globs`/`exclude`).
- [x] 9. `--dry` (plan only) with statistics (hits/files) + `--export=` (patch/JSON). *(export.lua, init.lua)*
- [x] 10. Patch export: a git-applyable unified diff (`vim.diff`) or JSON. *(export.lua)*

Also fixed: `confirm_all=false` was swallowed by `as_bool(x) or default`
(the Lua `false` trap) → `pick_bool` introduced; Windows paths with `\` were
destroyed by the tokenizer → backslash escaping now only before quotes/space/backslash.

---

## 1. Clearing up the remaining merge leftovers

- [x] 🔴 **Dead picker duplicates removed.** `pickers/fzf/` & `pickers/telescope/` (~620 LOC, required by
  nobody) deleted; `init.lua` uses the monolithic `fzf.lua`/`telescope.lua`.
- [x] 🔴 **`health.lua` switched to the new config API.** It now uses `require("replacer.config").get()`,
  knows `engine="auto"`/`search_engine`/filters, and reports the vimgrep fallback instead of a hard rg error.

## 2. Safety & error handling (rules 1, 3, 7)

- [x] 🔴 **API guards + `pcall` in `apply.lua`.** `bufadd`/`bufload`/`nvim_buf_set_text`/`write` are now
  wrapped in `pcall` + `nvim_buf_is_valid`/`is_loaded` checks; errors are collected instead of thrown.
- [x] 🔴 **Structured errors instead of silent ones.** A new module [error.lua](../lua/replacer/error.lua)
  (`safe_call` + `WriteError`/`SearchError`/`InvalidScopeError`); `apply_matches` returns `RP_Error[]`,
  rg search errors flow to the calling layer via `err`; the silent `fzf.lua` pcall is commented as optional.
- [x] 🟡 **`notify()` reduced in low-level code.** Apply collects errors & returns them; rg search errors
  (async) are notified in `init.run` via `err`. The remaining notifies are purely informational
  (a buffer-scan hint, the vimgrep fallback warning) — deliberately kept.

## 3. Architecture & testability (rules 2, 6)

- [x] 🟡 **`apply` as a pure function.** `apply.compute_file_edits(lines, matches, new)` is side-effect free
  and unit-tested; the real buffer application is separated into `apply_matches`.
- [x] 🟡 **Test harness.** [TESTS/feature_smoke.lua](../tests/feature_smoke.lua) (22) +
  [TESTS/async_utf8.lua](../tests/async_utf8.lua) (7), `make test`, a CI workflow. Run via `nvim -l`.
- [ ] 🟢 **A `/config` structure (DEFAULTS.lua).** Deliberately deferred — little benefit, the defaults are
  already cleanly encapsulated in `config.lua`.

## 4. Documentation & annotations (rule 5)

- [x] 🟡 **Doc drift fixed.** `README.md` + `doc/replacer.txt` fully updated (new flags,
  `engine="auto"`, `search_engine`, filters, dry run/export); all `ext_highlight_opts`/`:ReplaceDebug`/
  `replacer.options` references removed.
- [~] 🟡 **File/function tags.** All new/reworked modules annotated in detail
  (`@param`/`@return`/`@class`). A complete `@brief` sweep over *all* legacy files is still open.

## 5. Tooling (checklist section 7)

- [x] 🟡 **`stylua.toml` + `.luacheckrc` + CI.** Created + a `Makefile` (`fmt`/`lint`/`test`/`check`) +
  a GitHub Actions workflow ([.github/workflows/ci.yml](../.github/workflows/ci.yml)).
- [x] 🟡 **`.luarc.json`** with `diagnostics.globals=["vim"]`, a workspace library, hints.

---

## 6. Additional proposals (beyond the checklists)

### Safety
- [x] 🔴 **`confirm_wide_scope` enforced.** `:Replace … cwd --all` triggers a confirmation dialog for a
  non-buffer scope (`init.lua` `dispatch`, the `wide` check).
- [x] 🟡 **Multi-file replace is not atomic — documented.** A note in the README (Safety) and in
  `doc/replacer.txt` (*replacer-troubleshooting-not-atomic*), including dry run/export as the review route.

### Performance
- [x] 🟡 **`rg` now runs async.** `rg.collect_async` uses `vim.system(..., on_exit)` + `vim.schedule`;
  the vimgrep/buffer path stays synchronous. `init.run` dispatches in the callback. No more UI blocking on large repos.
- [x] 🟢 Table-building micro-optimisation (`t[#t+1]` → `t[i]=v`). The hot flat-list loops
  (`find_all_occurrences`, `parse_rg_json`, `collect_from_buffer`, `scan_file`, `list_files`,
  `apply_line_range`, `read_lines`) now use an explicit index counter; the `group_by_path` buckets use
  a parallel count map. Bounded per-file loops were left unchanged.

### Cross-platform & correctness
- [x] 🟡 **UTF-8 regression checked.** [TESTS/async_utf8.lua](../tests/async_utf8.lua) tests umlauts + emoji
  (`Grüße Müller 😀 Müller` → `Mueller`), byte offsets correct, no regression.
- [x] 🟢 **Windows paths/backslashes.** `vim.system` (an argument vector, no shell) is the standard path;
  `shellescape` is only a legacy fallback. Plus a tokenizer fix for `\` in paths. Verified on Windows.
