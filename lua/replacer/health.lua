---@module 'replacer.health'
--- Health check module for :checkhealth replacer
local M = {}

---@internal
--- Check if command exists in PATH
---@param cmd string
---@return boolean
local function cmd_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

---@internal
--- Get version string from command
---@param cmd string
---@param args string[]
---@return string|nil
local function get_version(cmd, args)
  if not cmd_exists(cmd) then
    return nil
  end

  local ok, result
  if vim.system then
    local obj = vim.system(vim.list_extend({ cmd }, args), { text = true }):wait()
    ok = obj.code == 0
    result = obj.stdout or ""
  else
    ok, result =
      require("lib.nvim.cross.run_argv").run_blocking_captured(vim.list_extend({ cmd }, args))
  end

  if not ok then
    return nil
  end

  -- Extract version number (first line, first number-like sequence)
  local first_line = result:match("^([^\n]+)")
  if not first_line then
    return nil
  end

  local version = first_line:match("(%d+%.%d+[%.%d]*)")
  return version
end

---@internal
--- Check Neovim version
---@param health table vim.health module
local function check_neovim(health)
  health.start("Neovim")

  local required = { 0, 9, 0 }
  local current = vim.version()

  if vim.version.cmp(current, required) >= 0 then
    health.ok(
      string.format(
        "Version %s.%s.%s (required: 0.9.0+)",
        current.major,
        current.minor,
        current.patch
      )
    )
  else
    health.error(
      string.format("Version %s.%s.%s is too old", current.major, current.minor, current.patch),
      { "Upgrade to Neovim 0.9.0 or newer" }
    )
  end
end

---@internal
--- Require a module for a health probe and tell "not installed" apart from
--- "installed, but throws while loading". `pcall(require, name)` is false in
--- both cases, yet only the first one is fixed by installing/updating the
--- dependency; the second needs the module's own load error to be diagnosed.
--- Only a "not found" for `name` itself counts as missing: a module that loads
--- but requires some other missing module is broken, not absent.
---@param name string
---@return "ok"|"missing"|"broken" status
---@return string|nil err the require error, for "missing" and "broken"
local function probe_module(name)
  local ok, err = pcall(require, name)
  if ok then
    return "ok", nil
  end
  err = tostring(err)
  if err:find("module '" .. name .. "' not found", 1, true) then
    return "missing", err
  end
  return "broken", err
end

---@internal
--- Report one required module: ok, missing (with the install/update advice) or
--- broken (with the module's own load error in the message).
---@param health table vim.health module
---@param name string module to require
---@param spec {ok: string, missing: string, missing_advice: string[], consequence: string}
local function report_required_module(health, name, spec)
  local status, err = probe_module(name)
  if status == "ok" then
    health.ok(spec.ok)
  elseif status == "missing" then
    health.error(spec.missing, spec.missing_advice)
  else
    health.error(
      string.format("%s is installed but fails to load — %s: %s", name, spec.consequence, err),
      {
        "The module was found, so updating may not help: check the lib.nvim checkout "
          .. "for a half-applied update or a local edit (the load error is quoted above)",
      }
    )
  end
end

---@internal
--- Check lib.nvim: required for the :Replace/:Replacer/:Surround/:Wrap
--- command layer (lib.nvim.bindings.usercmd.composer). Notify/confirm/export also
--- depend on it directly; only progress_style (see check_optional) stays
--- genuinely soft.
---@param health table vim.health module
local function check_lib_nvim(health)
  health.start("lib.nvim")

  report_required_module(health, "lib.nvim.bindings.usercmd.composer", {
    ok = "lib.nvim detected (:Replace/:Surround command layer available)",
    missing = "lib.nvim not found — commands will fail to register",
    missing_advice = { "Add 'WKDSteve/lib.nvim' as a dependency" },
    consequence = "commands will fail to register",
  })

  -- replacer.hooks builds its registry on lib.nvim.hooks and apply.lua runs it on every
  -- apply, so an older lib.nvim that has the composer but not this module fails at the
  -- first :Replace/:Surround apply.
  report_required_module(health, "lib.nvim.hooks", {
    ok = "lib.nvim.hooks available (apply hooks)",
    missing = "lib.nvim.hooks not found — every apply will fail",
    missing_advice = { "Update 'WKDSteve/lib.nvim' (replacer.hooks needs lib.nvim.hooks)" },
    consequence = "every apply will fail",
  })

  -- replacer.casing delegates to lib.lua.strings (case_preserve); an older lib.nvim lacks the functions
  local loaded, strings = pcall(require, "lib.lua.strings")
  if
    loaded
    and type(strings) == "table"
    and type(strings.identifier_style) == "function"
    and type(strings.apply_style) == "function"
  then
    health.ok("lib.lua.strings.identifier_style available (case_preserve)")
  else
    health.error(
      "lib.lua.strings.identifier_style / apply_style not found — case_preserve will fail",
      {
        "Update 'WKDSteve/lib.nvim' (replacer.casing needs lib.lua.strings.identifier_style)",
      }
    )
  end
end

---@internal
--- Check ripgrep
---@param health table vim.health module
local function check_ripgrep(health)
  health.start("ripgrep")

  if not cmd_exists("rg") then
    health.warn("ripgrep (rg) not found in PATH — using the native vimgrep backend", {
      "ripgrep is faster and honors .gitignore/--type; vimgrep works without it.",
      "Install ripgrep: https://github.com/BurntSushi/ripgrep#installation",
      "On macOS: brew install ripgrep · Ubuntu: apt install ripgrep · Windows: choco install ripgrep",
    })
    return
  end

  local version = get_version("rg", { "--version" })
  if version then
    health.ok(string.format("Found ripgrep %s", version))

    -- Check version >= 11.0 (for --json support)
    local major = tonumber(version:match("^(%d+)"))
    if major and major < 11 then
      health.warn(
        string.format("Version %s is old (recommended: 11.0+)", version),
        { "Consider upgrading for better JSON support" }
      )
    end
  else
    health.ok("Found ripgrep (version unknown)")
  end

  -- Test JSON output
  local test_ok = false
  local test_result = ""

  pcall(function()
    if vim.system then
      local obj = vim
        .system({ "rg", "--json", "-e", "test" }, { text = true, stdin = "test" })
        :wait()
      test_ok = obj.code == 0 or obj.code == 1 -- 0 = match, 1 = no match (both OK)
      test_result = obj.stdout or ""
    else
      -- Fallback for older Neovim (pre-vim.system). Argv form with stdin, not
      -- io.popen: the shell string this used to run was a POSIX pipeline
      -- (`echo test | rg ... 2>&1`), which is not the same command under
      -- cmd.exe -- `echo test |` there feeds "test " with the space before the
      -- pipe included. vim.fn.system involves no shell at all.
      test_result = vim.fn.system({ "rg", "--json", "-e", "test" }, "test")
      test_ok = test_result:match('"type"') ~= nil
    end
  end)

  if test_ok and test_result:match('"type"') then
    health.ok("JSON output working")
  else
    health.warn("JSON output test inconclusive", { "Plugin may still work" })
  end
end

---@internal
--- Check picker availability
---@param health table vim.health module
local function check_pickers(health)
  health.start("Pickers")

  local telescope_ok = pcall(require, "telescope")
  local fzf_ok = pcall(require, "fzf-lua")

  if telescope_ok then
    health.ok("telescope.nvim is installed")

    -- Check plenary.nvim (telescope dependency)
    local plenary_ok = pcall(require, "plenary")
    if plenary_ok then
      health.ok("plenary.nvim is installed")
    else
      health.error(
        "plenary.nvim not found (required by telescope)",
        { "Install: https://github.com/nvim-lua/plenary.nvim" }
      )
    end
  end

  if fzf_ok then
    health.ok("fzf-lua is installed")
  end

  if not telescope_ok and not fzf_ok then
    health.error("No picker found", {
      "Install telescope.nvim: https://github.com/nvim-telescope/telescope.nvim",
      "OR install fzf-lua: https://github.com/ibhagwan/fzf-lua",
    })
  end

  -- pickers.nvim is optional: only the in-picker `filter` key (keymaps.filter,
  -- pickers.refine) needs it. Everything else works without it.
  if pcall(require, "pickers.refine") then
    health.ok("pickers.nvim is installed (in-picker result filtering available)")
  else
    -- vim.health.info takes a message and nothing else — a second argument is
    -- dropped in silence (LLS-29) — so the hint lives in the message.
    health.info(
      "pickers.nvim not found — the picker 'filter' key is disabled; install "
        .. "WKDSteve/pickers.nvim for stacked path/content filters"
    )
  end
end

---@internal
--- Check plugin configuration
---@param health table vim.health module
local function check_config(health)
  health.start("Configuration")

  local ok, cfg_mod = pcall(require, "replacer.config")
  if not ok then
    health.error("replacer.config not loaded", { "Check plugin installation" })
    return
  end

  local cfg = cfg_mod.get()

  -- ERR-22: an invalid single config value degrades to its default silently
  -- at the `validate()` call site -- `setup()` records what it had to
  -- reject/degrade so that degradation is visible somewhere, not just
  -- inferable from the resolved value matching a default by coincidence.
  if cfg_mod.issues then
    local issues = cfg_mod.issues()
    if #issues == 0 then
      health.ok("every setup() option was recognized and valid")
    else
      for _, issue in ipairs(issues) do
        health.warn(issue, { "Fix the option in require('replacer').setup({ ... })" })
      end
    end
  end

  -- Picker engine ("auto" resolves to fzf-lua, else telescope)
  if cfg.engine == "auto" then
    local resolved = pcall(require, "fzf-lua") and "fzf-lua"
      or (pcall(require, "telescope") and "telescope")
      or "none"
    health.ok(string.format("Picker engine: auto (resolves to %s)", resolved))
    if resolved == "none" then
      health.error("No picker available for engine='auto'", { "Install fzf-lua or telescope.nvim" })
    end
  elseif cfg.engine == "telescope" or cfg.engine == "fzf" then
    health.ok(string.format("Picker engine: %s", cfg.engine))
    -- ERR-60: `a and b or c` falls through to `c` whenever `b` itself is
    -- falsy -- and `pcall(require, ...)`'s whole purpose here is to be
    -- `false` when the picker is missing. An explicit `if` is required.
    local picker_ok
    if cfg.engine == "telescope" then
      picker_ok = pcall(require, "telescope")
    else
      picker_ok = pcall(require, "fzf-lua")
    end
    if not picker_ok then
      health.error(
        string.format("Configured engine '%s' not available", cfg.engine),
        { "Install the picker or change 'engine' in config" }
      )
    end
  else
    health.warn(
      string.format("Unknown engine: %s", tostring(cfg.engine)),
      { "Expected 'auto', 'fzf', or 'telescope'" }
    )
  end

  -- Search backend ("auto" prefers ripgrep, falls back to vimgrep)
  health.info(string.format("Search backend: %s", tostring(cfg.search_engine)))

  health.info(string.format("write_changes: %s", tostring(cfg.write_changes)))
  health.info(string.format("confirm_all: %s", tostring(cfg.confirm_all)))
  health.info(string.format("literal mode: %s", tostring(cfg.literal)))

  local filters = {}
  if #(cfg.file_types or {}) > 0 then
    filters[#filters + 1] = "types=" .. table.concat(cfg.file_types, ",")
  end
  if #(cfg.globs or {}) > 0 then
    filters[#filters + 1] = "globs=" .. table.concat(cfg.globs, ",")
  end
  if #(cfg.exclude or {}) > 0 then
    filters[#filters + 1] = "exclude=" .. table.concat(cfg.exclude, ",")
  end
  if #filters > 0 then
    health.info("Default filters: " .. table.concat(filters, "  "))
  end
end

---@internal
--- Check optional integrations (progress indicator, which-key).
--- Both are soft dependencies: missing is fine, this is informational only.
---@param health table vim.health module
local function check_optional(health)
  health.start("Optional integrations")

  if pcall(require, "lib.nvim.progress") then
    health.ok("lib.nvim.progress available — progress_style is functional")
  else
    -- vim.health.info drops a second argument in silence (LLS-29), so the
    -- hint lives in the message.
    health.info(
      "lib.nvim.progress not available — progress_style has no effect; update "
        .. "'WKDSteve/lib.nvim' to enable the progress indicator"
    )
  end

  if pcall(require, "which-key") then
    health.ok("which-key.nvim available — picker keymaps show labels in its popup")
  else
    health.info("which-key.nvim not installed — picker keymaps still work, just unlabeled there")
  end
end

---@internal
--- Check UTF-8 support
---@param health table vim.health module
local function check_utf8(health)
  health.start("UTF-8 Support")

  -- Check vim.str_byteindex availability (Neovim >= 0.9)
  if vim.str_byteindex then
    health.ok("vim.str_byteindex available")

    -- Test UTF-8 conversion
    local test_line = "Müller test" -- ü = 2 bytes
    local ok, result = pcall(vim.str_byteindex, test_line, 2, true)
    if ok and result == 2 then
      health.ok("UTF-8 byte index conversion working")
    else
      health.warn("UTF-8 conversion test inconclusive", {
        "Replace may still work; report at the repo if column offsets come out wrong",
      })
    end
  else
    health.error(
      "vim.str_byteindex not available",
      { "Upgrade to Neovim 0.9.0 or newer for UTF-8 support" }
    )
  end
end

--- Main health check entry point
--- This function is called by :checkhealth replacer
function M.check()
  -- Get health module (compatible with Neovim 0.9 and 0.10+)
  local health = vim.health or require("health")

  check_neovim(health)
  check_lib_nvim(health)
  check_ripgrep(health)
  check_pickers(health)
  check_config(health)
  check_utf8(health)
  check_optional(health)

  -- Declared tools (lib.nvim.deps) — same rg check_ripgrep() already does,
  -- but with the declared `why` and a pointer to `:Lib deps show`. Does
  -- nothing if lib.nvim.deps is unavailable (older lib.nvim).
  local ok_deps, deps_health = pcall(require, "lib.nvim.deps.health")
  if ok_deps then
    health.start("replacer.nvim: declared tools (lib.nvim.deps)")
    deps_health.report_for("replacer.nvim")
  end

  -- Summary
  health.start("Summary")
  health.info("Usage: :[range]Replace[!] {old} {new} [scope] [--flags]")
  health.info("See :help replacer for documentation")

  -- Composer route pre-flight (:Replace, :Surround)
  require("lib.nvim.bindings.usercmd.composer").checkhealth("Replace")
  require("lib.nvim.bindings.usercmd.composer").checkhealth("Surround")
end

return M
