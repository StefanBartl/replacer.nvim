-- luacheck configuration for replacer.nvim.
-- Neovim's Lua runtime is LuaJIT with the `vim` global injected by the host.
std = "max+vim"
max_line_length = 120

stds.vim = {
  globals = { "vim" },
}
