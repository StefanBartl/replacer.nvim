# Replacer Feature Implementation Matrix

## Rating criteria
- **Scope:** ⭐ (1 day) to ⭐⭐⭐⭐⭐ (>10 days)
- **Benefit:** 🔥 (low) to 🔥🔥🔥🔥🔥 (high)
- **Performance impact:** ⚡ (neutral) to ⚡⚡⚡⚡⚡ (critical)
- **Priority:** 🅰️ (must-have) 🅱️ (should-have) 🅲️ (nice-to-have) 🅳️ (maybe)

---

## Category: core features

### 1. File scopes & filters

**Scope:** ⭐⭐⭐ (3-4 days)
**Benefit:** 🔥🔥🔥🔥 (very high)
**Performance:** ⚡⚡ (moderate impact)
**Priority:** 🅱️ SHOULD-HAVE

**Description:**
Extended filtering on the replace call:
```vim
:Replace pattern new cwd --type lua --size <1M --exclude test/
:Replace pattern new . --git-status modified,staged
:Replace pattern new . --glob "src/**/*.ts" --exclude "*.spec.ts"
```

**Implementation:**
```lua
-- lua/replacer/command.lua
---@class RP_Filters
---@field filetypes string[]|nil     -- e.g. {"lua", "ts"}
---@field max_size integer|nil       -- in bytes
---@field globs string[]|nil         -- e.g. {"src/**/*.lua"}
---@field excludes string[]|nil      -- e.g. {"test/", "*.spec.lua"}
---@field git_status string[]|nil    -- e.g. {"modified", "staged"}

-- Parse from args
local function parse_filters(args)
  -- :Replace old new . --type lua,ts --size <1M
  local filters = {}
  for i = 4, #args do
    if args[i] == "--type" then
      filters.filetypes = vim.split(args[i+1], ",")
    elseif args[i] == "--size" then
      filters.max_size = parse_size(args[i+1])
    -- ... etc
  end
  return filters
end

-- Apply in rg.lua
local function apply_filters(files, filters)
  if filters.max_size then
    files = vim.tbl_filter(function(f)
      return vim.fn.getfsize(f) <= filters.max_size
    end, files)
  end
  -- ... more filters
  return files
end
```

**Effort breakdown:**
- Argument parsing: 0.5 days
- Ripgrep `--type` integration: 0.5 days
- Git status filter (via `git status --porcelain`): 1 day
- Glob/exclude patterns: 1 day
- Tests & docs: 1 day

**Performance impact:**
- Git status check: +50-200 ms (one-off)
- Glob matching: +10-50 ms per 1000 files
- Overall: acceptable

---

### 2. History & Presets

**Scope:** ⭐⭐⭐ (3-4 days)
**Benefit:** 🔥🔥🔥 (high)
**Performance:** ⚡ (neutral)
**Priority:** 🅱️ SHOULD-HAVE

**Description:**
```vim
" History
:ReplaceHistory         " Picker with the last 50 replacements
<CR> on an entry       " Re-run with the same parameters

" Presets
:ReplaceSavePreset refactor_imports old="import X" new="import Y" scope=src/
:ReplacePreset refactor_imports
```

**Implementation:**
```lua
-- lua/replacer/history.lua
local M = {}
local history_file = vim.fn.stdpath("data") .. "/replacer_history.json"

---@class RP_HistoryEntry
---@field timestamp number
---@field old string
---@field new string
---@field scope string
---@field files_changed integer
---@field spots_changed integer

function M.add(entry)
  local history = M.load()
  table.insert(history, 1, entry)
  -- Keep last 50
  if #history > 50 then
    table.remove(history)
  end
  M.save(history)
end

function M.load()
  local ok, data = pcall(vim.fn.readfile, history_file)
  if not ok then return {} end
  return vim.json.decode(table.concat(data))
end

-- Picker integration
function M.show_picker()
  local history = M.load()
  -- Format for telescope/fzf
  local entries = vim.tbl_map(function(e)
    return string.format(
      "%s | %s → %s | %d files | %s",
      os.date("%Y-%m-%d %H:%M", e.timestamp),
      e.old:sub(1, 20),
      e.new:sub(1, 20),
      e.files_changed,
      e.scope
    )
  end, history)

  -- Show in picker, on select: re-run
end
```

**Presets:**
```lua
-- lua/replacer/presets.lua
local presets_file = vim.fn.stdpath("data") .. "/replacer_presets.json"

---@class RP_Preset
---@field name string
---@field old string
---@field new string
---@field scope string
---@field filters RP_Filters|nil

function M.save_preset(name, config)
  -- Store preset
end

function M.run_preset(name)
  local preset = M.load_preset(name)
  require("replacer").run(preset.old, preset.new, preset.scope, false)
end
```

**Effort:**
- History storage: 1 day
- History picker UI: 1 day
- Preset storage & commands: 1 day
- Tests & docs: 1 day

**Performance:** none, disk I/O is minimal (<10 ms)

---

### 3. Plan/review without applying (dry run)

**Scope:** ⭐⭐ (2 days)
**Benefit:** 🔥🔥🔥🔥 (very high)
**Performance:** ⚡ (neutral)
**Priority:** 🅱️ SHOULD-HAVE

**Description:**
```vim
:Replace pattern new . --dry-run
" Shows:
" - 145 matches across 23 files
" - Grouped by file with counts
" - Export as patch/JSON
```

**Implementation:**
```lua
-- In command.lua: detect --dry-run flag
function M.run(old, new_text, scope, all, opts)
  if opts.dry_run then
    return run_dry_run(old, new_text, scope)
  end
  -- ... normal flow
end

function run_dry_run(old, new_text, scope)
  local roots, _ = resolve_scope(scope)
  local items = RG.collect(old, roots, M.options)

  -- Group by file
  local by_file = {}
  for _, it in ipairs(items) do
    by_file[it.path] = (by_file[it.path] or 0) + 1
  end

  -- Show summary
  print("Dry Run Results:")
  print(string.format("  Total: %d matches in %d files", #items, vim.tbl_count(by_file)))
  print("\nBy File:")
  for path, count in pairs(by_file) do
    print(string.format("  %3d  %s", count, vim.fn.fnamemodify(path, ":.")))
  end

  -- Offer export
  local choice = vim.fn.confirm("Export results?", "&Patch\n&JSON\n&Cancel", 3)
  if choice == 1 then
    export_patch(items, new_text)
  elseif choice == 2 then
    export_json(items)
  end
end
```

**Effort:**
- Dry-run logic: 0.5 days
- Summary formatting: 0.5 days
- Patch export: 0.5 days (unified diff format)
- JSON export: 0.25 days
- Tests: 0.25 days

---

### 4. Quickfix/Loclist Export

**Scope:** ⭐ (1 day)
**Benefit:** 🔥🔥🔥 (high)
**Performance:** ⚡ (neutral)
**Priority:** 🅱️ SHOULD-HAVE

**Description:**
```vim
:Replace pattern new . --to-quickfix
" Sends the matches into the quickfix list
:copen  " Shows the hits
:cfdo %s/old/new/g | w  " Apply via a Vim macro
```

**Implementation:**
```lua
function export_to_quickfix(items)
  local qf_list = vim.tbl_map(function(it)
    return {
      filename = it.path,
      lnum = it.lnum,
      col = it.col0 + 1,  -- 1-based
      text = it.line,
      type = "I",  -- Info
    }
  end, items)

  vim.fn.setqflist(qf_list, "r")
  vim.cmd("copen")
  vim.notify(string.format("[replacer] Sent %d matches to quickfix", #items))
end
```

**Effort:** 1 day (including the loclist variant + docs)

---

### 5. Per-file confirmation

**Scope:** ⭐⭐ (2 days)
**Benefit:** 🔥🔥🔥 (high)
**Performance:** ⚡ (neutral)
**Priority:** 🅲️ NICE-TO-HAVE

**Description:**
```vim
:Replace pattern new . --confirm-per-file
" For each file:
"   file.lua (12 matches)
"   [A]ll | [S]kip | [O]nly selected | [Q]uit
```

**Implementation:**
```lua
function apply_with_file_confirmation(items, new_text, cfg)
  local by_file = group_by_file(items)

  for path, file_items in pairs(by_file) do
    local rel = vim.fn.fnamemodify(path, ":.")
    local choice = vim.fn.confirm(
      string.format("%s (%d matches)", rel, #file_items),
      "&All\n&Skip\n&Only selected\n&Quit",
      1
    )

    if choice == 1 then  -- All
      Apply.apply(file_items, new_text, cfg.write_changes)
    elseif choice == 3 then  -- Only selected
      -- Show picker with only this file's matches
      show_picker_for_file(file_items, new_text, cfg)
    elseif choice == 4 then  -- Quit
      break
    end
    -- choice == 2: Skip, continue to next file
  end
end
```

**Effort:** 2 days

---

### 6. Undo-Checkpoint

**Scope:** ⭐⭐ (2 days)
**Benefit:** 🔥🔥🔥🔥🔥 (critical)
**Performance:** ⚡⚡ (moderate)
**Priority:** 🅰️ MUST-HAVE

**Description:**
```vim
:Replace pattern new . --checkpoint
" Before apply:
" - Creates git stash or
" - Saves buffer states or
" - Creates temp branch
:ReplaceUndo  " Rollback last operation
```

**Implementation:**
```lua
-- lua/replacer/checkpoint.lua
local M = {}

function M.create(strategy)
  if strategy == "git-stash" then
    vim.fn.system("git stash push -m 'replacer checkpoint'")
  elseif strategy == "buffer-snapshot" then
    -- Save undo history per buffer
    M.save_buffer_states()
  elseif strategy == "git-branch" then
    local branch = "replacer-backup-" .. os.time()
    vim.fn.system("git checkout -b " .. branch)
  end
end

function M.rollback(strategy)
  if strategy == "git-stash" then
    vim.fn.system("git stash pop")
  -- ... etc
end
```

**Effort:** 2 days (git integration, buffer-state persistence)

---

## Category: UI/UX features

### 7. Status/Progress

**Scope:** ⭐⭐ (2 days)
**Benefit:** 🔥🔥🔥 (high)
**Performance:** ⚡⚡ (moderate - has to be async)
**Priority:** 🅱️ SHOULD-HAVE

**Description:**
```vim
" During search:
Replacer: Scanning 1234/5000 files (24%)...
" During apply:
Replacer: Applying 45/145 matches (31%)...
```

**Implementation:**
```lua
-- lua/replacer/progress.lua
local M = {}

function M.show(message, progress)
  -- Option 1: fidget.nvim integration
  local ok, fidget = pcall(require, "fidget")
  if ok then
    fidget.notify(message, nil, { percentage = progress })
  else
    -- Option 2: vim.notify with title
    vim.notify(string.format("%s (%d%%)", message, progress), vim.log.levels.INFO)
  end
end

-- In rg.lua: add progress callbacks
function collect_with_progress(pattern, roots, cfg)
  local total_files = #roots
  local processed = 0

  -- ... async file processing ...

  if processed % 100 == 0 then
    M.show("Scanning files", math.floor(processed / total_files * 100))
  end
end
```

**Effort:** 2 days (async integration, fidget.nvim compatibility)

---

### 8. Preserve-whitespace option

**Scope:** ⭐ (1 day)
**Benefit:** 🔥🔥 (medium)
**Performance:** ⚡ (neutral)
**Priority:** 🅲️ NICE-TO-HAVE

**Description:**
```lua
-- Before:
"  function old()"
-- After (normal):
"  function new()"
-- After (preserve-ws):
"  function new()"  -- same indentation
```

**Implementation:**
```lua
-- In apply.lua
if cfg.preserve_whitespace then
  -- Extract leading/trailing whitespace from old match
  local leading = it.old:match("^(%s*)")
  local trailing = it.old:match("(%s*)$")
  local trimmed_old = vim.trim(it.old)

  -- Apply to new text
  local new_with_ws = leading .. new_text .. trailing
  vim.api.nvim_buf_set_text(bufnr, row, s, row, e, { new_with_ws })
else
  -- Normal replace
end
```

**Effort:** 1 day

---

### 9. Safe mode: writable files only

**Scope:** ⭐ (0.5 days)
**Benefit:** 🔥🔥🔥🔥 (very high - safety)
**Performance:** ⚡ (neutral)
**Priority:** 🅰️ MUST-HAVE

**Implementation:**
```lua
-- In config.lua
---@class RP_Config
---@field safe_mode boolean
---@field max_file_size integer  -- bytes, default 5MB
---@field skip_binary boolean    -- default true

-- In apply.lua
function apply(items, new_text, cfg)
  for path, list in pairs(by_path) do
    -- Check file permissions
    if vim.fn.filewritable(path) == 0 then
      vim.notify(string.format("Skip (read-only): %s", path), vim.log.levels.WARN)
      goto next_file
    end

    -- Check file size
    if vim.fn.getfsize(path) > cfg.max_file_size then
      vim.notify(string.format("Skip (too large): %s", path), vim.log.levels.WARN)
      goto next_file
    end

    -- Check binary
    if cfg.skip_binary and is_binary(path) then
      vim.notify(string.format("Skip (binary): %s", path), vim.log.levels.WARN)
      goto next_file
    end

    -- ... proceed with apply
    ::next_file::
  end
end

function is_binary(path)
  local fd = io.open(path, "rb")
  if not fd then return false end
  local chunk = fd:read(512)
  fd:close()
  return chunk:find("\0") ~= nil  -- NULL byte = binary
end
```

**Effort:** 0.5 days

---

### 10. Patch-Export

**Scope:** ⭐⭐ (1.5 days)
**Benefit:** 🔥🔥🔥 (high)
**Performance:** ⚡ (neutral)
**Priority:** 🅲️ NICE-TO-HAVE

**Implementation:**
```lua
function export_patch(items, new_text, output_file)
  local by_file = group_by_file(items)
  local patch_lines = {}

  for path, file_items in pairs(by_file) do
    -- Read original file
    local orig_lines = vim.fn.readfile(path)
    local modified_lines = vim.deepcopy(orig_lines)

    -- Apply replacements (bottom-up)
    for _, it in ipairs(file_items) do
      local line = modified_lines[it.lnum]
      local new_line = line:sub(1, it.col0)
                     .. new_text
                     .. line:sub(it.col0 + #it.old + 1)
      modified_lines[it.lnum] = new_line
    end

    -- Generate unified diff
    table.insert(patch_lines, string.format("--- %s", path))
    table.insert(patch_lines, string.format("+++ %s", path))
    -- ... diff algorithm (simplified)
  end

  vim.fn.writefile(patch_lines, output_file)
end
```

**Effort:** 1.5 days (including a proper unified diff)

---

## Category: advanced features (ideas)

### 11. Case-Preserving Replace

**Scope:** ⭐⭐ (2 days)
**Benefit:** 🔥🔥🔥 (high)
**Performance:** ⚡ (neutral)
**Priority:** 🅲️ NICE-TO-HAVE

**Example:**
```
foo → bar
Foo → Bar
FOO → BAR
```

**Implementation:**
```lua
function apply_case_preserving(old, new, match_text)
  local case_style = detect_case(match_text)

  if case_style == "lower" then
    return new:lower()
  elseif case_style == "upper" then
    return new:upper()
  elseif case_style == "title" then
    return new:sub(1,1):upper() .. new:sub(2):lower()
  elseif case_style == "camel" then
    -- ... camelCase logic
  end
end
```

**Effort:** 2 days (complex case detection)

---

### 12. LSP-Integration

**Scope:** ⭐⭐⭐⭐ (4-5 days)
**Benefit:** 🔥🔥🔥🔥 (very high for code)
**Performance:** ⚡⚡⚡ (LSP call overhead)
**Priority:** 🅲️ NICE-TO-HAVE (but complex)

**What it does:**
```vim
:Replace MyClass NewClass . --lsp
" If MyClass is a symbol:
"   -> use the LSP rename
" Otherwise:
"   -> fall back to a text replace
```

**Challenges:**
- The LSP server may not be available
- Cross-file references have to be correct
- Conflicts with a simultaneous text replace

**Effort:** 4-5 days (LSP integration, fallback logic, tests)

---

### 13. Streaming search

**Scope:** ⭐⭐⭐⭐ (4 days)
**Benefit:** 🔥🔥🔥 (high on large projects)
**Performance:** ⚡⚡⚡⚡ (critical - has to be efficient)
**Priority:** 🅳️ MAYBE (complex)

**Description:**
- Stream the ripgrep output
- Fill the picker progressively
- The user can already select while the search runs

**Implementation:**
```lua
function collect_streaming(pattern, roots, cfg, callback)
  local stdout = vim.loop.new_pipe()
  local handle

  handle = vim.loop.spawn("rg", {
    args = { "--json", pattern },
    stdio = { nil, stdout, nil },
  }, function(code)
    stdout:close()
    handle:close()
  end)

  local buffer = ""
  stdout:read_start(function(err, data)
    if data then
      buffer = buffer .. data

      -- Parse complete JSON lines
      for line in buffer:gmatch("([^\n]+)\n") do
        local ok, item = pcall(vim.json.decode, line)
        if ok then
          callback(item)  -- Send to picker incrementally
        end
      end
    end
  end)
end
```

**Challenges:**
- The picker API has to support incremental updates
- Race conditions on an early selection
- Progress reporting is complex

**Effort:** 4 days

---

## Feature priority matrix

| Feature | Scope | Benefit | Performance | Priority | Recommendation |
|---------|--------|--------|-------------|-----------|------------|
| **Help & Health** | ⭐⭐ | 🔥🔥🔥🔥🔥 | ⚡ | 🅰️ | ✅ IMPLEMENT |
| **Safe-Mode** | ⭐ | 🔥🔥🔥🔥 | ⚡ | 🅰️ | ✅ IMPLEMENT |
| **Undo-Checkpoint** | ⭐⭐ | 🔥🔥🔥🔥🔥 | ⚡⚡ | 🅰️ | ✅ IMPLEMENT |
| **File-Scopes** | ⭐⭐⭐ | 🔥🔥🔥🔥 | ⚡⚡ | 🅱️ | ✅ IMPLEMENT |
| **Dry-Run** | ⭐⭐ | 🔥🔥🔥🔥 | ⚡ | 🅱️ | ✅ IMPLEMENT |
| **Quickfix Export** | ⭐ | 🔥🔥🔥 | ⚡ | 🅱️ | ✅ IMPLEMENT |
| **History** | ⭐⭐⭐ | 🔥🔥🔥 | ⚡ | 🅱️ | ✅ IMPLEMENT |
| **Progress** | ⭐⭐ | 🔥🔥🔥 | ⚡⚡ | 🅱️ | ✅ IMPLEMENT |
| **Patch Export** | ⭐⭐ | 🔥🔥🔥 | ⚡ | 🅲️ | ⏸️ LATER |
| **Per-File Confirm** | ⭐⭐ | 🔥🔥🔥 | ⚡ | 🅲️ | ⏸️ LATER |
| **Preserve-WS** | ⭐ | 🔥🔥 | ⚡ | 🅲️ | ⏸️ LATER |
| **Case-Preserve** | ⭐⭐ | 🔥🔥🔥 | ⚡ | 🅲️ | ⏸️ LATER |
| **LSP Integration** | ⭐⭐⭐⭐ | 🔥🔥🔥🔥 | ⚡⚡⚡ | 🅲️ | ⏸️ LATER |
| **Streaming** | ⭐⭐⭐⭐ | 🔥🔥🔥 | ⚡⚡⚡⚡ | 🅳️ | ❌ SKIP |
| **Vimgrep** | ⭐⭐⭐⭐ | 🔥 | ⚡⚡⚡⚡⚡ | 🅳️ | ❌ SKIP |

## Implementation roadmap

### Phase 1: critical (1-2 weeks)
1. ✅ Help documentation (2 days) - DONE
2. ✅ Health check (1 day) - DONE
3. Safe mode (0.5 days)
4. Undo checkpoint (2 days)

### Phase 2: high value (2-3 weeks)
5. Dry run (2 days)
6. Quickfix export (1 day)
7. File scopes & filters (3-4 days)
8. Progress reporting (2 days)

### Phase 3: enhancement (2-3 weeks)
9. History & presets (3-4 days)
10. Patch export (1.5 days)
11. Per-file confirmation (2 days)

### Phase 4: polish (1-2 weeks)
12. Preserve whitespace (1 day)
13. Case preserving (2 days)

**Total: 8-10 weeks for all high-priority features**
