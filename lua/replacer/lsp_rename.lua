---@module 'replacer.lsp_rename'
--- Soft LSP integration (--lsp): when a match's old/new text both look like
--- plain identifiers and its buffer has an attached LSP client that
--- supports rename, offer an LSP-driven rename (a proper workspace-wide
--- symbol rename) instead of a plain text edit for that one match --
--- falling back to plain text replace otherwise (ineligible text shape, no
--- client, or the request failed/timed out). Never a hard requirement:
--- every fallback path is silent and safe.
---
--- Position-based (uses the match's own lnum/col0 via textDocument/rename
--- directly), not cursor-based (unlike vim.lsp.buf.rename()) -- so this
--- never moves the user's cursor or window, which matters since it can run
--- from inside a picker callback.

local M = {}

--- True when `text` looks like a plain identifier (letters/digits/
--- underscore only, at least one char) -- the shape LSP rename is designed
--- for. Anything else (whitespace, punctuation, partial tokens, multi-word
--- phrases) falls back to plain text.
---@param text string|nil
---@return boolean
function M.looks_like_identifier(text)
  return text ~= nil and text ~= "" and text:match("^[%w_]+$") ~= nil
end

---@internal
--- List LSP clients attached to `bufnr`, tolerant of the Neovim API
--- generation (vim.lsp.get_clients is 0.10+; older versions only have
--- get_active_clients).
---@param bufnr integer
---@return table[]
local function list_clients(bufnr)
  if vim.lsp.get_clients then
    local ok, clients = pcall(vim.lsp.get_clients, { bufnr = bufnr })
    if ok and clients then return clients end
  end
  ---@diagnostic disable-next-line: deprecated
  if vim.lsp.get_active_clients then
    ---@diagnostic disable-next-line: deprecated
    local ok, clients = pcall(vim.lsp.get_active_clients, { bufnr = bufnr })
    if ok and clients then return clients end
  end
  return {}
end

---@internal
---@param client table
---@return boolean
local function supports_rename(client)
  if client.supports_method then
    local ok, result = pcall(client.supports_method, client, "textDocument/rename")
    if ok then return result == true end
  end
  return client.server_capabilities ~= nil and client.server_capabilities.renameProvider ~= nil
end

---@internal
--- Find an attached client for `bufnr` that supports textDocument/rename.
---@param bufnr integer
---@return table|nil
local function rename_capable_client(bufnr)
  for _, client in ipairs(list_clients(bufnr)) do
    if supports_rename(client) then return client end
  end
  return nil
end

--- Attempt an LSP rename for `match`. Always calls `on_done(ok)` exactly
--- once: true when the LSP workspace edit was applied, false to signal
--- "fall back to plain text replace" for this match.
---@param match RP_Match
---@param new_text string
---@param on_done fun(ok: boolean)
---@return nil
function M.try_rename(match, new_text, on_done)
  if not M.looks_like_identifier(match.old) or not M.looks_like_identifier(new_text) then
    on_done(false)
    return
  end

  local ok_add, bufnr = pcall(vim.fn.bufadd, match.path)
  if not ok_add or not bufnr or bufnr == 0 then
    on_done(false)
    return
  end
  pcall(vim.fn.bufload, bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    on_done(false)
    return
  end

  local client = rename_capable_client(bufnr)
  if not client then
    on_done(false)
    return
  end

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = match.lnum - 1, character = match.col0 },
    newName = new_text,
  }

  -- Dot-call form (client.request(client, ...)), not client:request(...):
  -- works across every Neovim LSP client API generation, unlike the
  -- method-call sugar which only exists on newer client objects.
  local ok_req = client.request(client, "textDocument/rename", params, function(err, result)
    if err or not result then
      on_done(false)
      return
    end
    local ok_apply = pcall(vim.lsp.util.apply_workspace_edit, result, client.offset_encoding or "utf-16")
    on_done(ok_apply == true)
  end, bufnr)

  if not ok_req then on_done(false) end
end

--- Attempt LSP rename for every item in `items`, blocking (vim.wait) until
--- every attempt finishes or `timeout_ms` elapses. Any item still pending
--- at the timeout is treated as a fallback (never applied twice).
---@param items RP_Match[]
---@param new_text string
---@param timeout_ms integer|nil
---@return RP_Match[] lsp_renamed, RP_Match[] fallback
---@see replacer.apply.apply_matches
function M.try_rename_batch(items, new_text, timeout_ms)
  local pending = #items
  ---@type table<integer, boolean>
  local results = {}

  for i, it in ipairs(items) do
    M.try_rename(it, new_text, function(ok)
      if results[i] == nil then
        results[i] = ok
        pending = pending - 1
      end
    end)
  end

  if pending > 0 then
    pcall(vim.wait, timeout_ms or 2000, function() return pending <= 0 end, 10)
  end

  ---@type RP_Match[]
  local lsp_renamed, fallback = {}, {}
  for i, it in ipairs(items) do
    if results[i] == true then
      lsp_renamed[#lsp_renamed + 1] = it
    else
      fallback[#fallback + 1] = it
    end
  end
  return lsp_renamed, fallback
end

return M
