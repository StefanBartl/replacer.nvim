# replacer.nvim — developer tasks
# Usage: make test | make lint | make fmt | make fmt-check | make check

.PHONY: test lint fmt fmt-check check

# Run the headless test suites (same set as .github/workflows/ci.yml).
test:
	nvim -n -i NONE -l TESTS/feature_smoke.lua
	nvim -n -i NONE -l TESTS/surround_smoke.lua
	nvim -n -i NONE -l TESTS/async_utf8.lua
	nvim -n -i NONE -l TESTS/refine_wiring.lua
	nvim -n -i NONE -l TESTS/gitfiles_equivalence.lua
	nvim -n -i NONE -l TESTS/config_merge.lua
	nvim -n -i NONE -l TESTS/argtypes_debug_error.lua
	nvim -n -i NONE -l TESTS/health_pickers_tscode.lua
	nvim -n -i NONE -l TESTS/bindings_wiring.lua
	nvim -n -i NONE -l TESTS/init_dispatch.lua
	nvim -n -i NONE -l TESTS/pickers_backends.lua
	nvim -n -i NONE -l TESTS/usrcmd_option_help.lua

# Static analysis. Explicit file list (not a bare `luacheck lua/`): some
# luacheck/OS combinations (observed with a Windows/mingw install) fail
# directory-argument traversal with a permission error; globbing files
# ourselves sidesteps that and works identically everywhere.
lint:
	find lua plugin TESTS -name '*.lua' | xargs luacheck

# Format in place.
fmt:
	stylua lua/ TESTS/

# Verify formatting without writing.
fmt-check:
	stylua --check lua/ TESTS/

# Everything CI runs (keep lint/fmt paths and the suite list in sync with
# .github/workflows/ci.yml).
check: fmt-check lint test
