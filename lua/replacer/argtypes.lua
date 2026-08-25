---@module 'replacer.argtypes'
---@brief Custom composer argument types for `:Replace`'s value flags.
---@description
--- `:Replace` declares 41 flags; composer completes every flag *name* from
--- that declaration for free, but a flag's *value* is only completable if its
--- type says how. Three of them have a real answer:
---
---   --type=<ft>       ripgrep's own type names, read from `rg --type-list`
---   --changed=<kinds> modified|staged|untracked, comma-joinable
---   --export=<path>   an output file — plain FILE completion, declared in
---                     command.lua rather than here
---
--- The rest deliberately have none, and the reasons differ:
---
---   --context=, --max-filesize=  integers; there is no list to offer.
---   --glob=, --exclude=          *patterns*, not paths. Completing them
---                                against existing files would suggest
---                                `lua/replacer/command.lua` where the flag
---                                wants `**/*.lua` — a candidate that is
---                                accepted, matches one file, and silently
---                                narrows the replacement. Worse than
---                                offering nothing.

local composer = require("lib.nvim.usercmd.composer")
local job = require("lib.nvim.system.job")

local M = {}

--- The kinds `--changed=` accepts. Kept in sync with `apply_tokens`'
--- validation by being the same three literals it rejects everything else
--- against; a divergence would show up as a completed value being refused.
---@type string[]
local CHANGED_KINDS = { "modified", "staged", "untracked" }

---Cached `rg --type-list` names. `false` means "asked, and rg had no answer"
---— distinct from `nil` ("not asked yet"), so a missing rg costs one probe
---per session instead of one per `<Tab>`.
---@type string[]|false|nil
local rg_types = nil

---Read ripgrep's type names.
---
---`rg --type-list` prints `name:glob,glob,...` per line; only the name before
---the first colon is a valid `--type` value.
---@return string[]
local function ripgrep_types()
  if rg_types ~= nil then
    return rg_types or {}
  end

  if vim.fn.executable("rg") ~= 1 then
    rg_types = false
    return {}
  end

  -- Blocking, because completion is synchronous: nvim wants the candidate
  -- list as the return value of this call. Bounded tightly -- `--type-list`
  -- is a built-in table, not a search, so anything slower than this is a
  -- broken rg and not worth freezing <Tab> for.
  local ok, res = pcall(job.start_blocking, {
    command = "rg",
    args = { "--type-list" },
    timeout_ms = 2000,
  })
  if not ok or type(res) ~= "table" or res.code ~= 0 or type(res.stdout) ~= "string" then
    rg_types = false
    return {}
  end

  local out = {}
  for line in res.stdout:gmatch("[^\r\n]+") do
    local name = line:match("^([%w_%-%+%.]+):")
    if name then
      out[#out + 1] = name
    end
  end

  if #out == 0 then
    rg_types = false
    return {}
  end

  table.sort(out)
  rg_types = out
  return out
end

---@param candidates string[]
---@param lead string
---@return string[]
local function prefixed(candidates, lead)
  local out = {}
  for _, c in ipairs(candidates) do
    if c:sub(1, #lead) == lead then
      out[#out + 1] = c
    end
  end
  return out
end

---Register the types. Idempotent — `composer.register_type` overwrites by
---name, and `register()` is called from `command.register`, which itself runs
---once per `setup()`.
---@return nil
function M.register()
  composer.register_type("RP_RG_TYPE", {
    -- Anything rg accepts; validating against the probed list would reject a
    -- type from a user's own `--type-add` that this process never saw.
    validate = function(raw)
      return true, raw, nil
    end,
    complete = function(arg_lead)
      return prefixed(ripgrep_types(), arg_lead)
    end,
  })

  composer.register_type("RP_CHANGED_KINDS", {
    validate = function(raw)
      return true, raw, nil
    end,
    -- `--changed=` takes a comma-separated subset, so completion has to
    -- continue an in-progress list rather than replace it: the committed
    -- kinds are carried back into every candidate, and kinds already named
    -- are dropped so a second `<Tab>` cannot produce `staged,staged`.
    complete = function(arg_lead)
      local committed, last = arg_lead:match("^(.*,)([^,]*)$")
      if not committed then
        committed, last = "", arg_lead
      end

      local already = {}
      for kind in committed:gmatch("([^,]+)") do
        already[kind] = true
      end

      local out = {}
      for _, kind in ipairs(prefixed(CHANGED_KINDS, last)) do
        if not already[kind] then
          out[#out + 1] = committed .. kind
        end
      end
      return out
    end,
  })
end

M.CHANGED_KINDS = CHANGED_KINDS

---Drop the cached rg type list. Tests only — there is no runtime reason to
---re-probe, `rg --type-list` being fixed for a given rg binary.
---@return nil
function M._reset_cache()
  rg_types = nil
end

return M
