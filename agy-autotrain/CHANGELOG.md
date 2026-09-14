# agy-autotrain - changelog
## 0.5.0 — 2026-09-14

### Features
- feat(release): retire Inno for 3 members -> root marketplace + plugin.json version truth (Inno-retirement U3/U4 part 1)
- feat(agy-autotrain): seed the knowledge STORE - the earned corpus enters version control
- feat(cheatsheet): strip the safety-guard framing - the artifact cannot hold a guard
- feat(agy-autotrain): move the capture inbox to ~/.clavity (ROADMAP 14g)
- feat(cheatsheet): promote the review-only-banner rule; park 64 on the SEED/GROWTH split
- feat(agy-autotrain): drain 42 inbox entries - cheatsheet round-shaping bullet + 3 backlog items
- feat(hooks): enforce the agy-curate abort path with an inverted in-progress marker

### Fixes
- fix: correct Inno-retirement hook regressions the full ci-scripts suite caught
- fix(agy-learn): my two captures went to the DEAD repo template - move them out
- fix(capstone-r1): a reader with no writer, and two guards that certified what they had stopped checking
- fix(capstone-r1): the pair diverged on a present-but-unusable growth path
- fix(golden-header): raise the combined cap 16 -> 32 KiB - it was breached in production, silently
- fix(capstone-r27): a repo gate has been RED at HEAD for 29 commits and 15 folds
- fix(capstone-r26): a committed, wired hook whose only test nothing has ever run
- fix(capstone-r25): one member could overwrite another member's registered marketplace
- fix(capstone-r24): my own recovery check false-alarmed on a legitimately empty inbox
- fix(capstone-r24): a kill switch that stopped the output but not the side effects
- fix(capstone-r23): I invented the provenance for a fix while fixing false claims
- fix(capstone-r22): the one string that reaches another agent still asserted the old rule
- fix(capstone-r21): an interrupted migration was abandoned in silence
- fix(capstone-r20): all four guards I wrote were defeated, and one was defeating itself
- fix(capstone-r18): the destructive set was pinned, the consent that authorises it was not
- fix(capstone-r17): the destructive-set guard pinned three of the five deletions
- fix(docs): three stale doc claims - including a correction that was itself false
- fix(abort-drain): a missing manifest has TWO routes, and the operator was told only one
- fix(installer): the purge dialog called a SUCCESSFUL migration's audit trail failure wreckage
- fix(installer): correct a false claim I made one commit ago about uninstall logging
- fix(installer): a PURGE uninstall left the rolled-back inbox behind - and nothing guarded the set
- fix(installer): the 14g migration re-encoded the user's observations - move raw bytes instead
- fix(drain): fold capstone round 10 - the curator prompt still routed backlog files to a dead path
- fix(drain): fold capstone round 8 - a migrated inbox leaked its own header into the user's captures
- fix(tests): fold capstone round 6 - the round-5 fix skipped its own sibling scan
- fix(tests): fold capstone round 1 - six guards that passed for the wrong reason
- fix(14g): complete the kill-switch fold - the third hook in this plugin still read bare $HOME
- fix(14g): stop the drain duplicating its own residue, and fold four stale statements
- fix(14g): the .no-agy kill switch was resolvable at a path the inbox no longer used
- fix(14g): fold capstone round 1 - claim the inbox by rename BEFORE the write, and stop failing silently
- fix(ci): three first-run CI failures on PR #1
- fix(agy-autotrain): rescue 31 orphaned captures, close the inbox fork, file a curate-commit defect
- fix(agy-autotrain): correct a sentence round 4 made false, and record the hole it hides
- fix(agy-autotrain): fold capstone round 4 - three findings, one refuted
- fix(agy-autotrain): restore the path prefix the reference invariant caught
- fix(agy-autotrain): fold capstone round 3 - six findings from a SEATED panel
- fix(agy-autotrain): fold capstone round 2 - my round-1 fix had two reachable defects
- fix(agy-autotrain): fold capstone round 1 - three findings, two refuted
- fix(agy-autotrain): resolve the inbox by install, not by a path relative to the skill
- fix(capstone): fold R14's one finding - and the third instance it missed
- fix(capstone): fold R13 - formulation 6 VALIDATED; the rest was bookkeeping
- fix(capstone): fold R12 - the sixth formulation, and two incomplete folds of my own
- fix(capstone): fold R11 - my R10 fix re-broke what d3988b2 had fixed
- fix(capstone): fold R10 - including the ordering defect its Q4 exposed
- fix(agy-curate): tighten the dirty-path predicate - "did not publish" over-reached to exit 0
- fix(capstone): fold R9 - one finding as given, one on corrected grounds
- fix(capstone): fold all four R8 findings - every one a defect my R7 fold introduced
- fix(capstone): fold three of four R7 findings; F4 is an owner decision
- fix(agy-curate): write the cross-file citation at :89 in full
- fix(capstone): fold all four R6 findings - including one my own last fold left behind
- fix(capstone): fold R5 - cut every justification, keep the facts
- fix(capstone): fold all four R4 findings - and remove a false safety claim I wrote
- fix(capstone): fold R3 findings - a stricter debt anchor and a stated partial effect
- fix(capstone): fold R2 findings - pin the budget behaviourally, not by source text
- fix(capstone): fold R1 findings 3, 4 and 6 from the Stage 2 capstone
- fix(agy-autotrain): align hook matchers, cover them, and split fixed from released
- fix(agy-autotrain): close Group A skill-coherence findings and enforce the cheatsheet budget
- fix(agy-autotrain): stop the injected-context gate depending on an untracked file
- fix(injected-context): sanitise the whole domain - the gate now exits 0
- fix(injected-context): close 9 of the 10 audited anomalies (A2 withdrawn)
- fix(agy-autotrain): resolve two reference defects the new gate found
- fix(autotrain): snapshot the inbox on the slash-command path too
- fix(ls): status mirrors the gRPC code, and a peer-refused call stops claiming a shutdown

## 0.4.0 - 2026-08-03

### Features
- feat(agy-autotrain): cheatsheet - check the clean round, not just license it

### Fixes
- fix(agy-autotrain): a stamp is DELIMITED - do not let a prose date impersonate one
- fix(agy-autotrain): prefer the provenance stamp over any other date in the record
- fix(agy-autotrain): read the bullet RECORD and its trailing stamp, not the leftmost date
- fix(agy-autotrain): anchor the curate-nudge age scan to pending bullets

## 0.3.0 - 2026-08-03

### Features
- feat(cheatsheet): sanction the null answer; verify the fix, not just the finding
- feat(agy-autotrain): snapshot the observations inbox before a drain
- feat(agy-knowledge): drain the observations inbox - cheatsheet core + gRPC backlog item
- feat(verify): per-driver status columns in the assertion table
- feat(sp0): add pluginName field to driver members (identity != member key)

### Fixes
- fix(agy-autotrain): a malformed KEEP wiped the whole snapshot ring
- fix(agy-curate): reset the inbox only after curate-commit succeeds
- fix(gates,dispatch): fold capstone round 2 - four verified findings
- fix(curate-commit): tripwire a mojibake payload at the receiving end
- fix(agy-curate): define a legal end state for an unrunnable probe, and bound the rubric
- fix(agy-autotrain): emit the right payload shape for PreCompact
- fix(verify): close three silent-failure paths the capstone found
- fix(installer): correct the partial-failure warning + scoped not-detected message
- fix(agy-autotrain): register with Claude Code only, never agy
- fix(docs): correct stale golden-header injection claim in agy-autotrain README

## 0.2.2 - 2026-07-24

### Fixes
- fix(installer): anchor agy-autotrain's dev-folder excludes to the source root

## 0.2.1 - 2026-07-21

### Fixes
- fix(installer): resolve the 5.1 interpreter with {sys}, not {sysnative}

## 0.2.0 - 2026-07-20

### Features
- feat(panel): make the negotiation turn point at files, not at your evidence
- feat(agy-autotrain): make the negotiate-with-agy reminder a forcing function
- feat(installer): migrate 4 plugin-only members to register-plugin.ps1 (ship + shell + hash-pin)

### Fixes
- fix(installer): make "keep" and "remove" mean what the dialogs say
- fix(installer): keep the inbox on uninstall; correct a false ordering claim
- fix(installer): stop the upgrade from destroying the capture inbox
- fix(agy-autotrain): resync both BASELINE_FLOOR constants to driver-cheatsheet.core.md

## 0.1.5 - 2026-07-13

### Fixes
- fix(installer): refuse uninstall while Claude Code is running (symmetric clobber guard)
- fix(installer): refuse install in all 5 members while Claude Code is running (Bug 2 primary)


Prior version history lives in `git log`; this changelog starts at 0.1.3.

## 0.1.4
- Move the `adversarial-panel-review` skill (de-transported) + AGY-AFTER hook into each driver's plugin -
  the panel discipline is now driver-native. agy-autotrain retains the learning loop (learn/curate/verify +
  observations inbox). (The agnostic manuals + golden-header baseline move to the driver seed in Phase 3.)

## 0.1.3
- Add the **`adversarial-panel-review`** skill - convene an adversarial multi-seat panel to tear down a
  spec, plan, or other high-leverage artifact before it is acted on: a palette of distinct expert seats
  (each hunting a different defect-class), a live-agy escalation round, fold-with-verification, and a
  PANEL VERDICT. Codifies the AGY-AFTER team-panel review discipline that previously lived as prose in
  the global driving instructions.
- Ship the **AGY-AFTER reminder** as a plugin hook (`hooks/agy-after-reminder.sh`, PostToolUse on
  spec/plan edits) that points at the `adversarial-panel-review` skill. The discipline now installs,
  updates, and uninstalls entirely with the plugin - no edits to the user's global `CLAUDE.md`.
- Capture 3 agy driving observations (forcing-functions beat vague volume/creativity dials; genuine
  creativity is unlocked by a clear goal + a verifiable success criterion + full method latitude).
