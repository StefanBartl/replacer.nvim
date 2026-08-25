-- luacheck configuration for replacer.nvim.
-- Neovim's Lua runtime is LuaJIT with the `vim` global injected by the host.
std = "max+vim"
-- Line length is stylua's job (column_width in stylua.toml), not luacheck's.
-- The only lines luacheck flagged here were long string literals and LuaLS
-- doc comments -- exactly the two things stylua cannot break, so the second
-- limit only produced findings with no clean fix.
max_line_length = false

stds.vim = {
  globals = { "vim" },
}
