-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "replacer",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "script",
  -- Lua patterns a file name must match to be a spec (the old runner started these files by name).
  spec_pattern = {
    "_spec%.lua$",
    "^TESTS/feature_smoke%.lua$",
    "^TESTS/surround_smoke%.lua$",
    "^TESTS/async_utf8%.lua$",
    "^TESTS/refine_wiring%.lua$",
    "^TESTS/gitfiles_equivalence%.lua$",
    "^TESTS/config_merge%.lua$",
    "^TESTS/argtypes_debug_error%.lua$",
    "^TESTS/health_pickers_tscode%.lua$",
    "^TESTS/bindings_wiring%.lua$",
    "^TESTS/init_dispatch%.lua$",
    "^TESTS/pickers_backends%.lua$",
    "^TESTS/usrcmd_option_help%.lua$",
    "^TESTS/rg_partial_failure%.lua$",
    -- fails when a script under TESTS/ is missing from this list
    "^TESTS/spec_coverage%.lua$",
  },
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim", "ui.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "file",
  -- "c" = child started from a -c command (v:vim_did_enter is 0, <cword> works),
  -- "l" = `nvim -l`.
  host = "c",
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  env_allow = { "LIB_NVIM_PATH", "PICKERS_NVIM_PATH", "UI_NVIM_PATH" },
}
