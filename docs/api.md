# Lua API

The commands are the plugin's real interface; this is the surface for
scripting it from your own config. Everything else in `lua/replacer/` is
internal and may change without notice.

The same reference is available in-editor as `:help replacer-api`.

## `require("replacer").setup(opts)`

Applies configuration. Optional — the `:Replace*` commands register from
`plugin/replacer.lua` whether or not `setup()` is ever called, so a config
that is happy with the defaults can skip it entirely.

```lua
require("replacer").setup({ engine = "telescope" })
```

`opts` is an [`RP_Config`](configuration.md). The validator rebuilds the
effective config from the known key set, so a misspelled option is dropped
rather than reported — `require("replacer.config").get()` is the way to see
what actually took.

## `require("replacer").run(request)`

Executes a replace workflow — the same executor every `:Replace*` command
dispatches into.

```lua
---@param request RP_Request|string
---@param new_text? string
---@param scope?    string
---@param all?      boolean
```

The structured form takes an `RP_Request`
([`types/init.lua`](../lua/replacer/types/init.lua)):

```lua
require("replacer").run({
  old = "oldName",
  new = "newName",
  scope = "cwd",
  all = false,
  dry = true,
  export = nil,
  line_range = nil,
  overrides = { case_preserve = true },
  filters = { file_types = { "lua" }, globs = {}, exclude = { "node_modules" } },
})
```

A legacy positional form is still accepted and normalised into the above:

```lua
require("replacer").run("old", "new", "cwd", false)
```

`overrides` are per-run config values (the programmatic equivalent of the
`--flags`); `filters` narrows which files are searched.

## `require("replacer.config").get()`

Returns a deep copy of the current effective configuration. Mutating the
result has no effect on the plugin.

```lua
local cfg = require("replacer.config").get()
print(cfg.default_scope) --> "%"
```

`require("replacer.config").resolve(partial)` resolves a partial override
against the current state without mutating it — what the command layer uses
to build a per-run config from flags.

## `require("replacer.hooks").on(event, fn)`

Registers a hook in addition to anything in `config.hooks`. Config hooks run
first, then registrations in the order they were made.

```lua
require("replacer.hooks").on("after_apply", function(ctx)
  print(string.format("%s: %d spot(s)", ctx.path, ctx.spots))
end)
```

`event` is one of `before_apply`, `after_apply`, `before_write`,
`after_write`; the `ctx` each one receives is tabulated in
[configuration.md](configuration.md#hooks). A `before_apply` hook returning
`false` skips that file. A hook error is caught and warned, never allowed to
abort the apply.

`require("replacer.hooks").clear()` removes every programmatic registration
(`config.hooks` is untouched) — mainly for tests.
