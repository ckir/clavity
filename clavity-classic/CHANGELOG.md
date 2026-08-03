# classic changelog

## 0.4.0 — 2026-08-03

### Features
- feat(agy-autotrain): cheatsheet - check the clean round, not just license it
- feat(agy-autotrain): cost clause on the test-audit reminder
- feat(agy-autotrain): cost clause on the capstone seam
- feat(agy-autotrain): session-posture line on the brainstorm seam

### Fixes
- fix(hooks): strip non-ASCII from three hooks, guard the whole payload

## 0.3.0 — 2026-08-03

### Features
- feat(cheatsheet): sanction the null answer; verify the fix, not just the finding
- feat(dispatch): name the files a subagent may touch, and diff afterwards
- feat(agy-knowledge): drain the observations inbox - cheatsheet core + gRPC backlog item
- feat(anomalies): the FEED side - put the capture clause into every dispatch
- feat(anomalies): register the reminder in both drivers and enrol the new seed pairs
- feat(agy-capstone): ledger so a green capstone leaves a durable record
- feat(disciplines): report a personally-registered shipped hook (D1 enforcement)
- feat(agy-test-audit): the discipline SKILL.md (both mirrors)
- feat(agy-test-audit): register the reminder hook in both plugin manifests
- feat(agy-test-audit): marker-gated capstone->audit reminder hook + tests
- feat(sp-d): register liveness hook in both plugins + seed-sync SessionStart diff
- feat(sp-d): SessionStart liveness/degradation notice hook (stderr+exit2)
- feat(sp-d): jq-guard retrofit on agy-after-reminder.sh + activation tests
- feat(sp-c): register PreToolUse(Skill) auto-fire hook in both plugin manifests
- feat(sp-c): mirror auto-fire hook byte-identical into classic plugin
- feat(sp-b): agy-capstone discipline skill (both plugins) + lint enrollment
- feat(agy-first): mirror the discipline skill into clavity-classic (byte-identical)
- feat(sp0): rename plugin responder skill claudavity-responder -> responder (Option A)
- feat(sp0): rename skill clavity-driving -> driving
- feat(sp0): stage plugin at plugins/clavity to match derived identity
- feat(sp0): classic installer registers plugin identity clavity
- feat(sp0): plugin.json name -> clavity for both drivers
- feat(sp0): add pluginName field to driver members (identity != member key)

### Fixes
- fix(gates,dispatch): fold capstone round 2 - four verified findings
- fix(consult-guard): classify path- and .exe-qualified invocations
- fix(curate-commit): tripwire a mojibake payload at the receiving end
- fix(consult-guard): ship the VCS guard from the plugins, and fix both defects
- fix(disciplines): fail closed on settings schema drift, and stop forking on the boot path (capstone R2)
- fix(disciplines): match hook-name TOKENS, not substrings (capstone R1 folds)
- fix(classic): resolve psmux lazily so importing the module needs no binary
- fix(classic): resolve psmux from PATH instead of a pinned path
- fix(installer): correct the partial-failure warning + scoped not-detected message
- fix(agy-autotrain): register with Claude Code only, never agy
- fix(agy-test-audit): capstone R3 folds - core.quotePath=false for non-ASCII paths (F1), guard-message assert (F2), robust phantom injection (F3)
- fix(agy-test-audit): capstone R2 folds - case-insensitive ext grep (F1), jq empty-cwd guard (F3), F3-guard test (F4), stronger diff-path sanity (F5)
- fix(agy-test-audit): capstone R1 folds - no-jq .no-agy payload-cwd (F1), diff-path test coverage + mutant-proof (F2), linter unmapped-skill guard (F3)
- fix(sp-b): fold agy-capstone R4 (mid-adjudication sha-race + shell-agnostic recovery)
- fix(sp-b): fold agy-capstone R3 - close breach-waiver gate-bypass
- fix(sp-b): fold agy-capstone R2 findings (honest best-effort envelope + WAIVED reason)
- fix(sp-b): fold agy-capstone R1 findings (3, measurement-verified)
- fix(docs): correct stale "verified against" version-stamp advice in CONTRIBUTING

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

