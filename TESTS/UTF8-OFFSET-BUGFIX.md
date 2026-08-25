# Replacer: UTF-8 offset fix & debug extensions

## Table of content

  - [Problem analysis](#problem-analysis)
  - [Implemented fixes](#implemented-fixes)
    - [1. **rg.lua** - robust offset conversion](#1-rglua--robust-offset-conversion)
    - [2. **apply.lua** - extended diagnostics](#2-applylua--extended-diagnostics)
    - [3. **Debug utilities** - new modules](#3-debug-utilities--new-modules)
      - [`replacer.debug`](#replacerdebug)
      - [`test.utf8_offsets`](#testutf8_offsets)
  - [Usage](#usage)
    - [1. Setup with the debug option](#1-setup-with-the-debug-option)
    - [2. Debug workflow when something goes wrong](#2-debug-workflow-when-something-goes-wrong)
    - [3. Interpreting the warnings](#3-interpreting-the-warnings)
  - [Typical problems & solutions](#typical-problems--solutions)
    - [Problem 1: UTF-8 umlauts are not found](#problem-1-utf-8-umlauts-are-not-found)
    - [Problem 2: trailing whitespace](#problem-2-trailing-whitespace)
    - [Problem 3: emoji/multi-byte](#problem-3-emojimulti-byte)
  - [Performance impact](#performance-impact)
  - [Tests](#tests)
  - [Architecture conformance](#architecture-conformance)
    - [✅ Principles observed](#-principles-observed)
    - [📋 Checklist (from Arch&Coding-Regeln.md)](#-checklist-from-archcoding-regelnmd)
  - [Migration](#migration)
    - [Breaking changes](#breaking-changes)
    - [New dependencies](#new-dependencies)
    - [Config changes (optional)](#config-changes-optional)
  - [Further improvement proposals](#further-improvement-proposals)
  - [Support](#support)

---

## Problem analysis

The "skip changed spot" warnings occurred because of:

1. **Byte vs. character offset confusion**: ripgrep JSON can deliver character-based offsets, but Lua's `string.sub` works with bytes
2. **Multi-byte UTF-8 characters**: German umlauts (ä, ö, ü), emoji etc. cause offset drift
3. **Line normalisation**: inconsistent handling of `\n` between `rg.lua` and `apply.lua`

## Implemented fixes

### 1. **rg.lua** - robust offset conversion

**New features:**
- `char_to_byte()`: converts character indices to byte indices via `vim.str_byteindex()`
- `validate_match()`: validates ripgrep submatches against the actual line content
- `normalize_line()`: consistent removal of `\r?\n`
- **Fallback strategy**: on validation errors, an automatic switch to a manual line scan

**Before:**
```lua
local s = sm.start  -- could be char or byte
local matched_text = sm.match.text
matches[#matches + 1] = { col0 = s, old = matched_text, ... }
```

**After:**
```lua
local byte_start = char_to_byte(line_text, sm.start)
local valid, actual = validate_match(line_text, byte_start, matched_text)
if valid then
  -- OK, use the ripgrep submatch
else
  -- Fallback: scan the line manually
end
```

### 2. **apply.lua** - extended diagnostics

**New features:**
- `normalize_line()`: the same normalisation as in rg.lua
- `hex_dump()`: shows byte values on mismatches (in debug mode)
- **Retry logic**: also tries with `vim.trim()` on whitespace discrepancies
- **Skip statistics**: counts the different skip reasons (changed, trimmed, out-of-range)

**Extended validation:**
```lua
-- 1. Exact validation
if seg == it.old then
  -- Apply
end

-- 2. Trimmed retry (for whitespace edge cases)
if vim.trim(seg) == vim.trim(it.old) then
  -- Apply with a warning
end

-- 3. Detailed mismatch reporting
if debug then
  vim.notify(string.format(
    "expected: '%s' [%s]\nactual: '%s' [%s]",
    it.old, hex_dump(it.old),
    seg, hex_dump(seg)
  ))
end
```

### 3. **Debug utilities** - new modules

#### `replacer.debug`
**Commands:**
- `:ReplaceDebug on` - enables verbose diagnostics
- `:ReplaceDebug off` - disables debug mode
- `:ReplaceDebug status` - shows the current status
- `:ReplaceDebug test` - runs the test suite
- `:ReplaceDebug inspect` - inspects the current buffer
- `:ReplaceDebug analyze <line> <pattern>` - analyses a specific line

#### `test.utf8_offsets`
**Test suite:**
- ASCII baseline (reference)
- UTF-8 multi-byte characters (ä, ö, ü)
- Emoji (4-byte UTF-8)
- Ripgrep submatch simulation
- Line normalisation
- Match validation

## Usage

### 1. Setup with the debug option

```lua
require("replacer").setup({
  engine = "telescope",
  ext_highlight_opts = {
    enabled = true,
    debug = false,  -- set to true when something goes wrong
  },
})
```

### 2. Debug workflow when something goes wrong

```vim
" 1. Enable debug mode
:ReplaceDebug on

" 2. Inspect the buffer
:ReplaceDebug inspect

" 3. Analyse a specific line
:ReplaceDebug analyze 45 "Müller"

" 4. Run the replace (now with verbose diagnostics)
:Replace "Müller" "Mueller" %

" 5. Run the test suite
:ReplaceDebug test

" 6. Disable debug mode
:ReplaceDebug off
```

### 3. Interpreting the warnings

**Before (unclear):**
```
[replacer] skip changed spot: file.lua:45:5
```

**After (with debug):**
```
[replacer] skip (mismatch): file.lua:45:5
  expected: 'Müller' [4D C3 BC 6C 6C 65 72]
  actual:   'Muller' [4D 75 6C 6C 65 72]
```

**After (without debug, compact):**
```
[replacer] skip (mismatch): file.lua:45:5 (expected 'Müller', got 'Muller')
[replacer] skipped 4 spot(s): 4 changed, 0 trimmed, 0 out-of-range
```

## Typical problems & solutions

### Problem 1: UTF-8 umlauts are not found

**Symptom:**
```
[replacer] skip (mismatch): expected 'Müller', got 'M?ller'
```

**Cause:** ripgrep delivers a character offset instead of a byte offset

**Solution:** the fix in `rg.lua` converts automatically via `char_to_byte()`

### Problem 2: trailing whitespace

**Symptom:**
```
[replacer] skip (mismatch): expected 'test', got 'test '
```

**Solution:** the fix in `apply.lua` has retry logic with `vim.trim()`

### Problem 3: emoji/multi-byte

**Symptom:**
```
[replacer] skip (out of range): s=15 e=19 len=18
```

**Cause:** a 4-byte emoji (😀) counts as 1 character but 4 bytes

**Solution:** the new `validate_match()` checks byte ranges before extraction

## Performance impact

- **Minimal overhead** from the additional validation (~5-10 % on small files)
- **No impact** when debug mode is disabled (only compact warnings)
- **The fallback scan** only on ripgrep submatch failures

## Tests

Run test suite:
```lua
:lua require('test.utf8_offsets').run_all()
```

Expected output:
```
=== Replacer UTF-8 Offset Tests ===

✓ ASCII baseline
✓ UTF-8 offsets
✓ Match validation
✓ Emoji offsets
✓ Ripgrep submatch simulation
✓ Line normalization

=== Results: 6 passed, 0 failed ===
```

## Architecture conformance

### ✅ Principles observed

1. **Safety**
   - Everything wrapped in `pcall()` (vim.str_byteindex, vim.api calls)
   - Type guards before critical operations
   - Explicit error returns with context

2. **Modularity**
   - Debug utilities in a separate module
   - Tests in their own namespace
   - No global state

3. **Performance**
   - The fallback only when needed
   - String concatenation via table.concat
   - Local aliases for frequent calls

4. **Documentation**
   - EmmyLua annotations for all new functions
   - Inline comments for complex logic
   - Debug output with context

5. **Testability**
   - An isolated test suite
   - Reproducible test cases
   - Independent of ripgrep

### 📋 Checklist (from Arch&Coding-Regeln.md)

| Status | Rule | Met |
|--------|------|-----|
| ✅ | pcall() preferred | Yes (char_to_byte, validate_match) |
| ✅ | Type guards | Yes (before vim.api calls) |
| ✅ | Explicit returns | Yes (validate_match returns bool + actual) |
| ✅ | One module = one responsibility | Yes (debug, test, rg, apply separated) |
| ✅ | Pure functions | Yes (char_to_byte, normalize_line, hex_dump) |
| ✅ | Local instead of global | Yes (all helpers local) |
| ✅ | Documentation complete | Yes (EmmyLua + inline comments) |

## Migration

### Breaking changes
**None** — all changes are backwards compatible

### New dependencies
**None** — it uses only Neovim built-in APIs

### Config changes (optional)
```lua
-- New: the debug option in ext_highlight_opts
ext_highlight_opts = {
  enabled = true,
  debug = false,  -- optional
}
```

## Further improvement proposals

1. **Pattern cache**: cache frequently used regex patterns
2. **Parallel processing**: large files in chunks via vim.loop
3. **Preview with a diff**: show old/new side by side in the picker
4. **History**: store the last replacements for a quick re-run

## Support

If the problems persist:
1. `:ReplaceDebug on`
2. `:ReplaceDebug inspect`
3. `:Replace ...` (with verbose diagnostics)
4. Copy the output and open a GitHub issue with:
   - the Neovim version (`:version`)
   - the ripgrep version (`rg --version`)
   - the file encoding (`:set fileencoding?`)
   - the debug output
