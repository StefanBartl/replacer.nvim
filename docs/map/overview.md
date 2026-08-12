# replacer.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**3 modules** · 4 namespaces · 32 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua["replacer.nvim"]
  nlua_replacer["replacerbr/smallCore orchestration: parse a request,…/small"]
  nlua_replacer_command["command"]
  nlua_replacer_config["configbr/smallCentral configuration for replacer./small"]
  nlua_replacer_pickers["pickers"]
  nlua_replacer_types["typesbr/smallCentral type definitions for the replacer…/small"]
  nlua_replacer_util["util"]
  nlua --> nlua_replacer
  nlua_replacer --> nlua_replacer_command
  nlua_replacer --> nlua_replacer_config
  nlua_replacer --> nlua_replacer_pickers
  nlua_replacer --> nlua_replacer_types
  nlua_replacer --> nlua_replacer_util
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_replacer_apply_lua["replacer.apply"]
  nlua_replacer_batch_lua["replacer.batch"]
  nlua_replacer_casing_lua["replacer.casing"]
  nlua_replacer_checkpoint_lua["replacer.checkpoint"]
  nlua_replacer_command_lua["replacer.command"]
  nlua_replacer_config["replacer.config"]
  nlua_replacer_debug_lua["replacer.debug"]
  nlua_replacer_encoding_lua["replacer.encoding"]
  nlua_replacer_error_lua["replacer.error"]
  nlua_replacer_export_lua["replacer.export"]
  nlua_replacer_fnames_lua["replacer.fnames"]
  nlua_replacer_health_lua["replacer.health"]
  nlua_replacer_history_lua["replacer.history"]
  nlua_replacer_hooks_lua["replacer.hooks"]
  nlua_replacer_messages_lua["replacer.messages"]
  nlua_replacer_pickers["pickers"]
  nlua_replacer_presets_lua["replacer.presets"]
  nlua_replacer_regex_lua["replacer.regex"]
  nlua_replacer_rename_assist_lua["replacer.rename_assist"]
  nlua_replacer_rg_lua["replacer.rg"]
  nlua_replacer_root_lua["replacer.root"]
  nlua_replacer_surround_lua["replacer.surround"]
  nlua_replacer_tscode_lua["replacer.tscode"]
  nlua_replacer_util["util"]
  nlua_replacer_apply_lua --> nlua_replacer_casing_lua
  nlua_replacer_apply_lua --> nlua_replacer_error_lua
  nlua_replacer_apply_lua --> nlua_replacer_hooks_lua
  nlua_replacer_apply_lua --> nlua_replacer_regex_lua
  nlua_replacer_apply_lua --> nlua_replacer_util
  nlua_replacer_batch_lua --> nlua_replacer_command_lua
  nlua_replacer_batch_lua --> nlua_replacer_util
  nlua_replacer_checkpoint_lua --> nlua_replacer_util
  nlua_replacer_command_lua --> nlua_replacer_root_lua
  nlua_replacer_command_lua --> nlua_replacer_util
  nlua_replacer_debug_lua --> nlua_replacer_util
  nlua_replacer_export_lua --> nlua_replacer_apply_lua
  nlua_replacer_export_lua --> nlua_replacer_encoding_lua
  nlua_replacer_fnames_lua --> nlua_replacer_command_lua
  nlua_replacer_fnames_lua --> nlua_replacer_config
  nlua_replacer_fnames_lua --> nlua_replacer_util
  nlua_replacer_health_lua --> nlua_replacer_config
  nlua_replacer_history_lua --> nlua_replacer_util
  nlua_replacer_hooks_lua --> nlua_replacer_util
  nlua_replacer_messages_lua --> nlua_replacer_util
  nlua_replacer_pickers --> nlua_replacer_encoding_lua
  nlua_replacer_pickers --> nlua_replacer_messages_lua
  nlua_replacer_pickers --> nlua_replacer_util
  nlua_replacer_presets_lua --> nlua_replacer_command_lua
  nlua_replacer_presets_lua --> nlua_replacer_util
  nlua_replacer_regex_lua --> nlua_replacer_command_lua
  nlua_replacer_regex_lua --> nlua_replacer_util
  nlua_replacer_rename_assist_lua --> nlua_replacer_fnames_lua
  nlua_replacer_rename_assist_lua --> nlua_replacer_util
  nlua_replacer_rg_lua --> nlua_replacer_encoding_lua
  nlua_replacer_rg_lua --> nlua_replacer_error_lua
  nlua_replacer_rg_lua --> nlua_replacer_tscode_lua
  nlua_replacer_rg_lua --> nlua_replacer_util
  nlua_replacer_root_lua --> nlua_replacer_command_lua
  nlua_replacer_root_lua --> nlua_replacer_util
  nlua_replacer_surround_lua --> nlua_replacer_command_lua
  nlua_replacer_surround_lua --> nlua_replacer_config
  nlua_replacer_surround_lua --> nlua_replacer_messages_lua
  nlua_replacer_surround_lua --> nlua_replacer_util
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `replacer` | Core orchestration: parse a request, collect matches, then either plan (dry-run / export) or apply (interactive picker / non-interactive ALL). | 8 | [src](../../lua/replacer/init.lua) |
| &nbsp;&nbsp;`command` |  |  |  |
| &nbsp;&nbsp;`replacer.config` | Central configuration for replacer. | 13 | [src](../../lua/replacer/config/init.lua) |
| &nbsp;&nbsp;`pickers` |  |  |  |
| &nbsp;&nbsp;`replacer.types` | Central type definitions for the replacer plugin. |  | [src](../../lua/replacer/types/init.lua) |
| &nbsp;&nbsp;`util` |  |  |  |

## Drift

0 errors · 1 warnings · 17 info

| Severity | Check | Message |
|---|---|---|
| warn | `doc-references-missing` | docs/TODO-Guidelines-Review.md:53 references 'replacer.options', but replacer has no 'options' |

<details>
<summary>17 informational findings</summary>


| Check | Message |
|---|---|
| `missing-readme` | lua/replacer has no README.md |
| `missing-readme` | lua/replacer/config has no README.md |
| `missing-readme` | lua/replacer/types has no README.md |
| `undocumented-param` | M.setup has 1 parameter(s) but only 0 @param line(s) |
| `undocumented-param` | M.resolve has 1 parameter(s) but only 0 @param line(s) |
| `undocumented-param` | M.preview_lines_with_pos has 2 parameter(s) but only 0 @param line(s) |
| `undocumented-param` | M.notify_result has 3 parameter(s) but only 0 @param line(s) |
| `undocumented-param` | M.register_which_key has 2 parameter(s) but only 0 @param line(s) |
| `unreferenced-module` | replacer.batch is required by no other file in the tree |
| `unreferenced-module` | replacer.debug is required by no other file in the tree |
| `unreferenced-module` | replacer.health is required by no other file in the tree |
| `unreferenced-module` | replacer.pickers.utils is required by no other file in the tree |
| `unreferenced-module` | replacer.presets is required by no other file in the tree |
| `unreferenced-module` | replacer.surround is required by no other file in the tree |
| `unreferenced-module` | replacer.types is required by no other file in the tree |
| `unreferenced-module` | replacer.types.config is required by no other file in the tree |
| `unreferenced-module` | replacer.types.pickers is required by no other file in the tree |

</details>
