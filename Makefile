# replacer.nvim — developer tasks
# Usage: make test | make lint | make fmt | make fmt-check | make check

.PHONY: test lint fmt fmt-check check

# Run the headless test suites.
test:
	nvim -l TESTS/feature_smoke.lua
	nvim -l TESTS/surround_smoke.lua
	nvim -l TESTS/async_utf8.lua
	nvim -l TESTS/refine_wiring.lua

# Static analysis. Explicit file list (not a bare `luacheck lua/`): some
# luacheck/OS combinations (observed with a Windows/mingw install) fail
# directory-argument traversal with a permission error; globbing files
# ourselves sidesteps that and works identically everywhere.
lint:
	find lua plugin -name '*.lua' | xargs luacheck

# Format in place.
fmt:
	stylua lua/

# Verify formatting without writing.
fmt-check:
	stylua --check lua/

# Everything CI runs.
check: fmt-check lint test
