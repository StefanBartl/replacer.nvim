-- TESTS/ci_guard.lua -- runs one suite and turns an uncaught Lua error into a
-- failing exit code.
--
-- `nvim --headless -c "luafile TESTS/x.lua" -c "qa"` exits 0 even when x.lua
-- dies halfway: an uncaught error in a `-c` command is only printed (E5113),
-- the next `-c "qa"` still runs and nothing sets the exit code. A suite that
-- crashes before its closing `cquit 1` therefore leaves the CI step green and
-- every check after the crash silently never runs. Only `cquit`/`os.exit`
-- can fail the process, so the crash has to be caught and turned into one.
--
-- Loaded with `dofile` (it has to run before anything is on the path) and
-- called with the suite's path, exactly as `luafile` would receive it:
--
--   nvim -n -i NONE --headless -u NONE \
--     -c "set rtp+=." -c "set rtp+=./lib.nvim" -c "set rtp+=./ui.nvim" \
--     -c "lua dofile('TESTS/ci_guard.lua')('TESTS/feature_smoke.lua')" \
--     -c "qa"
--
-- A suite that ends in its own `cquit 1` / `os.exit(1)` (failed checks, missing
-- dependency) exits right there and never comes back to this function.

---@param path string  Suite file, relative to the cwd or absolute.
return function(path)
  local fail_msg
  -- loadfile keeps the "@<path>" chunk name that `luafile` would give, so a
  -- suite that derives its own directory from debug.getinfo behaves the same.
  local chunk, load_err = loadfile(path)
  if not chunk then
    fail_msg = "cannot load " .. path .. ": " .. tostring(load_err)
  else
    local ok, err = xpcall(chunk, debug.traceback)
    if not ok then
      fail_msg = tostring(err)
    end
  end

  if fail_msg then
    print("FAIL  suite crashed before it finished: " .. path)
    print(fail_msg)
    vim.cmd("cquit 1")
  end
end
