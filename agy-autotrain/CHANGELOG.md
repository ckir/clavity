# agy-autotrain — changelog
## 0.2.0 — 2026-07-20

### Features
- feat(panel): make the negotiation turn point at files, not at your evidence
- feat(agy-autotrain): make the negotiate-with-agy reminder a forcing function
- feat(installer): migrate 4 plugin-only members to register-plugin.ps1 (ship + shell + hash-pin)

### Fixes
- fix(installer): make "keep" and "remove" mean what the dialogs say
- fix(installer): keep the inbox on uninstall; correct a false ordering claim
- fix(installer): stop the upgrade from destroying the capture inbox
- fix(agy-autotrain): resync both BASELINE_FLOOR constants to driver-cheatsheet.core.md

## 0.1.5 — 2026-07-13

### Fixes
- fix(installer): refuse uninstall while Claude Code is running (symmetric clobber guard)
- fix(installer): refuse install in all 5 members while Claude Code is running (Bug 2 primary)


Prior version history lives in `git log`; this changelog starts at 0.1.3.

## 0.1.4
- Move the `adversarial-panel-review` skill (de-transported) + AGY-AFTER hook into each driver's plugin —
  the panel discipline is now driver-native. agy-autotrain retains the learning loop (learn/curate/verify +
  observations inbox). (The agnostic manuals + golden-header baseline move to the driver seed in Phase 3.)

## 0.1.3
- Add the **`adversarial-panel-review`** skill — convene an adversarial multi-seat panel to tear down a
  spec, plan, or other high-leverage artifact before it is acted on: a palette of distinct expert seats
  (each hunting a different defect-class), a live-agy escalation round, fold-with-verification, and a
  PANEL VERDICT. Codifies the AGY-AFTER team-panel review discipline that previously lived as prose in
  the global driving instructions.
- Ship the **AGY-AFTER reminder** as a plugin hook (`hooks/agy-after-reminder.sh`, PostToolUse on
  spec/plan edits) that points at the `adversarial-panel-review` skill. The discipline now installs,
  updates, and uninstalls entirely with the plugin — no edits to the user's global `CLAUDE.md`.
- Capture 3 agy driving observations (forcing-functions beat vague volume/creativity dials; genuine
  creativity is unlocked by a clear goal + a verifiable success criterion + full method latitude).
