# replacer.nvim — developer tasks
# Usage: make test | make lint | make fmt | make fmt-check | make check

.PHONY: test lint fmt fmt-check check

# Run the headless test suites on testing.nvim (same call as .github/workflows/ci.yml).
test:
	bash scripts/test.sh

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
