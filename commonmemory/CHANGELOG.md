# commonmemory changelog

## 0.3.0 — 2026-08-03

### Features
- feat(sp0): add pluginName field to driver members (identity != member key)

### Fixes
- fix(installer): correct the partial-failure warning + scoped not-detected message
- fix(agy-autotrain): register with Claude Code only, never agy

## 0.2.2 — 2026-07-24

### Fixes
- fix(installer): retract the stale dev marketplace v7-v10 shipped
- fix(installer): ship commonmemory's plugin manifest by anchoring the Excludes

## 0.2.1 — 2026-07-21

### Fixes
- fix(installer): resolve the 5.1 interpreter with {sys}, not {sysnative}

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

