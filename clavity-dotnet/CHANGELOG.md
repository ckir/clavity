# dotnet changelog

## 0.3.0 — 2026-07-20

### Features
- feat(panel): make the negotiation turn point at files, not at your evidence
- feat(agy-autotrain): make the negotiate-with-agy reminder a forcing function
- feat(golden-header): actually verify the .sha256 sidecar on read
- feat(docs): roster-driven member-docs floor gate + section-order templates
- feat(clavity-ls): run register-plugin.ps1 via -File (Option B) instead of embedded CLI vectors

### Fixes
- fix(installer): route the seed WRITER through the same resolved data dir
- fix(installer): make "keep" and "remove" mean what the dialogs say
- fix(installer): keep the inbox on uninstall; correct a false ordering claim
- fix(golden-header): write the sidecar after the header move, atomically
- fix(golden-header): close three cross-variant divergences found in round 3
- fix(golden-header): decode strictly as UTF-8 so both variants agree
- fix(golden-header): strip leading HTML comments from injected regions
- fix(agy-autotrain): resync both BASELINE_FLOOR constants to driver-cheatsheet.core.md

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

