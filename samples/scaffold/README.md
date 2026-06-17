# samples/scaffold — assembled universal plugin (reference)

This is a **sample** of what `cargo run -p xtask -- package scaffold` will emit into
`dist/scaffold/` (universal mode). It is committed for reference; the real `dist/` is
generated and gitignored.

Both hosts' files coexist (disjoint filenames):
- Claude: `.claude-plugin/plugin.json`, `.mcp.json`, `hooks/hooks.json`
- agy: `plugin.json`, `mcp_config.json`, `hooks.json`
- shared: `skills/`, `hooks/on-start.ps1`, `bin/scaffold-server.exe`

The rule `no-secrets` is mirrored into `skills/rule-no-secrets/` (universal mode ships
the mirror only; see the design spec).

> UNVERIFIED: the agy session-start hook event name is assumed `SessionStart`.
> Confirm via agy `/hooks` and update if different (see docs/plugin-formats.md).

Install to test (the skeleton ships a stub binary — not yet functional):

    claude plugin install ./samples/scaffold
    agy    plugin install ./samples/scaffold
