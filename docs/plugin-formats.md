# Plugin formats (verified reference)

Provenance: Claude docs (code.claude.com/docs/en/plugins-reference, 2026-06-17);
agy peer consults req-djbdx6998nv0 / req-djbeby5zp30k / req-djbemw4gbpoo (2026-06-17).
Re-verify after a `claude` or `agy` update (see the spec's open-items section).

## Disjoint filenames (the "universal" mechanism)
| Concern | Claude reads | agy reads |
| --- | --- | --- |
| Manifest | `.claude-plugin/plugin.json` | `plugin.json` |
| MCP config | `.mcp.json` | `mcp_config.json` |
| Hooks | `hooks/hooks.json` | `hooks.json` |

Shared: `skills/`, `hooks/` scripts, `bin/`. Both manifest sets coexist in one dir
because each CLI ignores the other's files (ASSUMPTION — re-verify).

## Manifest (both): `{ "name", "version", "description" }` — agy does NOT require `author`.

## MCP server command
- Claude `.mcp.json`: `"${CLAUDE_PLUGIN_ROOT}/bin/<binary>.exe"`
- agy `mcp_config.json`: `"./bin/<binary>.exe"` (agy sets CWD = plugin root)

## Hooks (same shape both): `{ "hooks": { "<EVENT>": [ { "matcher"?, "hooks": [ { "type":"command", "command" } ] } ] } }`
- agy hook commands also run with CWD = plugin root.
- UNVERIFIED: agy's session-start event NAME (assumed `SessionStart`) — confirm via agy `/hooks`.

## Install
- Both copy/stage only — NO build step. Ship pre-compiled binaries.
- agy stages to `~/.gemini/antigravity-cli/plugins/<name>/`.
- agy does NOT `chmod +x` on Unix (handle in xtask for the Unix port).

## MCP transport
Newline-delimited JSON-RPC 2.0 on stdio. stdout MUST stay JSON-RPC-pure; all logs/panics -> stderr.
