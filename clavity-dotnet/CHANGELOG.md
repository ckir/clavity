# dotnet changelog

## 0.2.1 — 2026-07-13

### Fixes
- fix(installer): refuse uninstall while Claude Code is running (symmetric clobber guard)
- fix(installer): refuse install in all 5 members while Claude Code is running (Bug 2 primary)
- fix(clavity-ls): refuse install while Claude Code (claude.exe) is running (Bug 2 primary)
- fix(clavity-ls): read back the exact plugin@marketplace after install (Bug 2 backstop)
- fix(clavity-ls): deregister the pre-cohesive 'clavity' marketplace on install (Bug 1 migration)

## 0.2.0 — 2026-07-13

### Features
- feat(clavity-ls): append CF1 escalation index (Option C, built once from install root)

### Fixes
- fix(drain): abort-drain reset --hard HEAD (staged-safe) + document curator trust model + clarify injection toggles (agy merge-gate folds)
- fix(classic): sync stale bridge uv.lock to 0.1.2; correct ROADMAP classic release note

