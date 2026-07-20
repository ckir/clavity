# commonmemory changelog

## 0.2.0 — 2026-07-20

### Features
- feat(installer): migrate 4 plugin-only members to register-plugin.ps1 (ship + shell + hash-pin)

### Fixes
- fix(commonmemory): ignore /dist ΓÇö a 2.1 MB installer was one `git add -A` away
- fix(commonmemory installer): exclude .claude-plugin from bundled Source (nested-manifest)
- fix(commonmemory): restore dev clone installation for claude

## 0.1.1 — 2026-07-13

### Fixes
- fix(installer): refuse uninstall while Claude Code is running (symmetric clobber guard)
- fix(installer): refuse install in all 5 members while Claude Code is running (Bug 2 primary)

