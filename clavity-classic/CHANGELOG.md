# classic changelog

## 0.2.2 — 2026-07-24

### Fixes
- fix(golden-header): route accumulated wisdom to the driver, not the agy peer (T4b)

## 0.2.1 — 2026-07-21

### Fixes
- fix(installer): resolve the 5.1 interpreter with {sys}, not {sysnative}

## 0.2.0 — 2026-07-20

### Features
- feat(panel): make the negotiation turn point at files, not at your evidence
- feat(gate): a member README's H1 must name that member
- feat(agy-autotrain): make the negotiate-with-agy reminder a forcing function
- feat(golden-header): actually verify the .sha256 sidecar on read
- feat(installer): migrate 4 plugin-only members to register-plugin.ps1 (ship + shell + hash-pin)

### Fixes
- fix(installer): route the seed WRITER through the same resolved data dir
- fix(installer): make "keep" and "remove" mean what the dialogs say
- fix(classic): actually delete the data the uninstaller promises to delete
- fix(golden-header): close three cross-variant divergences found in round 3
- fix(golden-header): decode strictly as UTF-8 so both variants agree
- fix(golden-header): strip leading HTML comments from injected regions
- fix(agy-autotrain): resync both BASELINE_FLOOR constants to driver-cheatsheet.core.md

## 0.1.4 — 2026-07-13

### Fixes
- fix(installer): refuse uninstall while Claude Code is running (symmetric clobber guard)
- fix(installer): refuse install in all 5 members while Claude Code is running (Bug 2 primary)

## 0.1.3 — 2026-07-13

### Fixes
- fix(classic): sync stale bridge uv.lock to 0.1.2; correct ROADMAP classic release note

