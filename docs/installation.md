# Installation

## Requirements

| | |
| --- | --- |
| **Neovim** | 0.9 or newer |
| **[`lib.nvim`](https://github.com/StefanBartl/lib.nvim)** | **required** — the `:Replace`/`:Surround` command layer, notifications, confirm dialogs, file writes and the progress indicator all resolve through it at load time |
| **A picker** | **required** — [`fzf-lua`](https://github.com/ibhagwan/fzf-lua), or [`telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim) (+ [`plenary.nvim`](https://github.com/nvim-lua/plenary.nvim)). `engine = "auto"` prefers fzf-lua when both are present |
| **[ripgrep](https://github.com/BurntSushi/ripgrep)** | recommended, not required — without `rg` on `PATH` the native `vimgrep` backend takes over automatically, at the cost of `.gitignore` awareness and rich `--type` filtering |
| [`fidget.nvim`](https://github.com/j-hui/fidget.nvim) | optional — only for `progress_style = "fidget"` |
| [`which-key.nvim`](https://github.com/folke/which-key.nvim) | optional — labels the picker keymaps it can see, see [BINDINGS.md](BINDINGS.md) |

`lib.nvim` is a hard dependency, not a soft one. Roughly every module in
`lua/replacer/` opens with a bare `require("lib.nvim…")`; without it the
plugin does not load at all. The *progress indicator specifically* is the one
part guarded by `pcall`, which is why it is sometimes described as optional —
that description applies to the indicator, never to `lib.nvim` itself.

## lazy.nvim

```lua
{
  "StefanBartl/replacer.nvim",
  cmd = { "Replace", "Replacer", "Surround", "Wrap" }, -- lazy-load on first use
  dependencies = {
    "StefanBartl/lib.nvim",
    "ibhagwan/fzf-lua", -- or nvim-telescope/telescope.nvim + nvim-lua/plenary.nvim
  },
  opts = {}, -- engine defaults to "auto": fzf-lua first, then telescope
}
```

Every option that can go into `opts` is listed in
[configuration.md](configuration.md).

## Declared CLI tools

replacer declares ripgrep in [`install.json`](install.json), which
`lib.nvim`'s [`deps`](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md)
module reads: a popup explains the tool and its package names once, on the
first `setup()` after installing. `:Lib deps show replacer.nvim` repeats it on
demand, and `:checkhealth replacer` folds the same information in.

Three ways to turn the popup off, narrowest first:

```lua
require("replacer").setup({ deps_popup = false })     -- this plugin only
vim.g.lib_nvim_deps_disabled_plugins = { "replacer.nvim" } -- this plugin, from anywhere
vim.g.lib_nvim_deps_disable_first_run = true          -- every plugin
```

## Verifying the install

```vim
:checkhealth replacer
```

reports Neovim's version, whether `lib.nvim` resolved, which search backend
and picker were detected, config validity, UTF-8 support, and the declared
tools. See [health.md](health.md).
