---@module 'plugin.replacer'
--- Lazy-friendly plugin entry: main config lives in replacer.init

-- Runs when the plugin gets loaded (runtimepath: plugin/*)
-- Idempotent registration to avoid duplicates on reloads.

if not vim.g.__replacer_cmd_registered then
  local ok_core, core = pcall(require, "replacer")
  local ok_cmd,  cmd  = pcall(require, "replacer.command")
  if ok_core and ok_cmd then
    cmd.register(core.run)
    local ok_sur, sur = pcall(require, "replacer.surround")
    if ok_sur then sur.register(core.run) end
    local ok_rx, rx = pcall(require, "replacer.regex")
    if ok_rx then rx.register() end
    local ok_root, root = pcall(require, "replacer.root")
    if ok_root then root.register(core.run) end
    local ok_cp, checkpoint = pcall(require, "replacer.checkpoint")
    if ok_cp then checkpoint.register() end
    local ok_hist, history = pcall(require, "replacer.history")
    if ok_hist then history.register(core.run) end
    local ok_presets, presets = pcall(require, "replacer.presets")
    if ok_presets then presets.register(core.run) end
    local ok_batch, batch = pcall(require, "replacer.batch")
    if ok_batch then batch.register(core.run) end
    vim.g.__replacer_cmd_registered = true
  end
end

