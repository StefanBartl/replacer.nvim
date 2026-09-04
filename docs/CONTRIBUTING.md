# Contributing

## Layout

Standard `lua/<plugin_name>/…`, so lazy.nvim and LuaLS both find things where
they expect them.

| | |
| --- | --- |
| `plugin/replacer.lua` | Entry point. Registers the commands, idempotently, whether or not `setup()` is ever called |
| `lua/replacer/bindings/` | One place that answers "what does this plugin bind": `usrcmds`, `keymaps`, `autocmds` |
| `lua/replacer/config/` | `DEFAULTS.lua` is pure values; `init.lua` is validation and merging |
| `lua/replacer/types/` | The EmmyLua contracts — `RP_Config`, `RP_Request`, `RP_Match` and friends |
| `lua/replacer/pickers/` | One module per backend, plus the shared helpers |
| `doc/replacer.txt` | Vimdoc. Falls out of every markdown grep, so check it by hand |
| `TESTS/` | Headless test suite, run through `nvim -l` |

The command *specs* live with the feature modules, not in `bindings/usrcmds`:
`:ReplaceUndo` cannot be described without `checkpoint.lua`'s snapshot model,
and a spec kept away from the code it drives is a spec that drifts.
`bindings/usrcmds` owns the registry of which module creates which command.

## Running the checks

The same three CI runs on every push and PR
([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)):

```sh
make lint       # luacheck lua/
make fmt-check  # stylua --check lua/
make test       # headless test suite
make check      # all three
```

`make test` needs [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) on the
runtimepath — it is the plugin's hard dependency, so nothing loads without it:

```sh
nvim --headless -u NONE -c "set rtp+=." -c "set rtp+=/path/to/lib.nvim" \
  -c "luafile TESTS/feature_smoke.lua" -c "qa"
```

## Working on it locally

Point your plugin manager at the checkout instead of GitHub:

```lua
{ dir = "/path/to/replacer.nvim", dependencies = { "StefanBartl/lib.nvim" } }
```

A useful loop for anything touching the apply path: set
`write_changes = false` so applies leave the buffers modified but unsaved, run
`:Replace foo bar cwd`, inspect the preview, and `:earlier`/`u` your way back
between attempts. `--dry` gives the same diff without touching a buffer at
all, and `:ReplaceDebug` ([troubleshooting.md](troubleshooting.md)) prints the
byte offsets when a match is being skipped rather than applied.

## Documentation

Anything user-facing has three homes and they are not interchangeable:

- **`README.md`** is the shop window — what this is, how to install it, and
  where to read further. Not a reference.
- **`docs/`** is the reference. [`docs/README.md`](README.md) says which file
  answers which question.
- **`doc/replacer.txt`** is the same reference for people who never leave the
  editor. It is the only one no markdown tooling will check for you.

New feature? It needs a `##` section in the right
[`docs/FEATURES/`](FEATURES/README.md) file, naming the module and the config
option that implements it — that folder is what makes "did we ever build X"
answerable without walking the module tree.
