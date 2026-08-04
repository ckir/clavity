# dotnet changelog

## 0.6.0 — 2026-08-04

### Features
- feat(knowledge): promote the 4 manual-tier rules into the shipped manuals
- feat(seed): promote 7 verified agy-driving rules into the SHIPPED golden-header
- feat(hooks): dual-channel the SessionStart anomaly notice for the model
- feat(hooks): register the anomaly capture and dispatch reminders; split SessionStart
- feat(hooks): add the AGY-ANOMALIES dispatch reminder on PreToolUse Agent\|Task
- feat(hooks): add the AGY-ANOMALIES PreCompact capture reminder

## 0.5.0 — 2026-08-03

### Features
- feat(agy-autotrain): cheatsheet - check the clean round, not just license it
- feat(agy-autotrain): cost clause on the test-audit reminder
- feat(agy-autotrain): cost clause on the capstone seam
- feat(agy-autotrain): session-posture line on the brainstorm seam

### Fixes
- fix(hooks): strip non-ASCII from three hooks, guard the whole payload

## 0.4.0 — 2026-08-03

### Features
- feat(cheatsheet): sanction the null answer; verify the fix, not just the finding
- feat(golden-header): snapshot the GROWTH region and its sidecar before replacing
- feat(dispatch): name the files a subagent may touch, and diff afterwards
- feat(agy-knowledge): drain the observations inbox - cheatsheet core + gRPC backlog item
- feat(anomalies): the FEED side - put the capture clause into every dispatch
- feat(anomalies): register the reminder in both drivers and enrol the new seed pairs
- feat(anomalies): open-issues skill - the capture bar and the triage procedure
- feat(anomalies): SessionStart hook that counts untriaged anomalies and demands triage
- feat(agy-capstone): ledger so a green capstone leaves a durable record
- feat(disciplines): report a personally-registered shipped hook (D1 enforcement)
- feat(agy-test-audit): the discipline SKILL.md (both mirrors)
- feat(agy-test-audit): register the reminder hook in both plugin manifests
- feat(agy-test-audit): marker-gated capstone->audit reminder hook + tests
- feat(clavity-ls): agy_status never-throws on a dead channel (channel_down + diagnostic)
- feat(clavity-ls): diagnose a wrapped channel death on the new-conversation model path (F3)
- feat(clavity-ls): central channel_down catch in RunAsync + ChannelDown helper
- feat(clavity-ls): ChannelDiagnostic record + optional AgyStatus diagnostic/hint
- feat(clavity-ls): progress-extensible idle-wait (limit-aware ModalGuard + windowed loop + payload)
- feat(clavity-ls): add CLAVITY_AGY_IDLE_STALL/MAX_SECONDS knobs + AgyViewOptions
- feat(clavity-dotnet): bundle agy-mcp-bridge into dotnet installer for parity with classic
- feat(sp-d): register liveness hook in both plugins + seed-sync SessionStart diff
- feat(sp-d): SessionStart liveness/degradation notice hook (stderr+exit2)
- feat(sp-d): jq-guard retrofit on agy-after-reminder.sh + activation tests
- feat(sp-c): register PreToolUse(Skill) auto-fire hook in both plugin manifests
- feat(sp-c): auto-fire seam-inject hook (dotnet) + synthetic-payload smoke
- feat(sp-b): agy-capstone discipline skill (both plugins) + lint enrollment
- feat(agy-first): author the AGY-FIRST + AGY-NEGOTIATE discipline skill
- feat(sp0): rename skill clavity-ls-pairing -> ls-pairing
- feat(sp0): rename skill clavity-ls-driving -> ls-driving
- feat(sp0): dotnet PluginName const -> clavity (rebuild clavity-ls)
- feat(sp0): stage plugin at plugins/clavity to match derived identity
- feat(sp0): plugin.json name -> clavity for both drivers
- feat(sp0): add pluginName field to driver members (identity != member key)

### Fixes
- fix(gates,dispatch): fold capstone round 2 - four verified findings
- fix(consult-guard): classify path- and .exe-qualified invocations
- fix(curate-commit): tripwire a mojibake payload at the receiving end
- fix(consult-guard): ship the VCS guard from the plugins, and fix both defects
- fix(anomalies): detect an unreadable file from grep's exit code, not [ -r ]
- fix(disciplines): fail closed on settings schema drift, and stop forking on the boot path (capstone R2)
- fix(disciplines): match hook-name TOKENS, not substrings (capstone R1 folds)
- fix(roadmap): file the two new items under clavity, not ghidrust
- fix(clavity-ls): require adjacent ports on the id-fallback pairing path
- fix(clavity-ls): make the session-id match a preference, and never abort a scan on a foreign line
- fix(clavity-ls): pair the HTTP line of the SAME agy session, and cover both surviving mutants
- fix(clavity-ls): surface an unusable captured number as LsDiscoveryException, tighten the anchor test
- fix(clavity-ls): anchor LS port discovery on the message body, not the glog line start
- revert(clavity-dotnet): un-bundle agy-mcp-bridge from the dotnet product
- fix(agy-test-audit): capstone R3 folds - core.quotePath=false for non-ASCII paths (F1), guard-message assert (F2), robust phantom injection (F3)
- fix(agy-test-audit): capstone R2 folds - case-insensitive ext grep (F1), jq empty-cwd guard (F3), F3-guard test (F4), stronger diff-path sanity (F5)
- fix(agy-test-audit): capstone R1 folds - no-jq .no-agy payload-cwd (F1), diff-path test coverage + mutant-proof (F2), linter unmapped-skill guard (F3)
- fix(clavity-ls): clear sawChannelDeath on a successful reach so a startup-transient death does not latch (capstone F5)
- fix(clavity-ls): report channel_down (not waiting_for_human) when the LS dies after being reached-empty (capstone F4)
- fix(clavity-ls): propagate a caller-cancel from the three boot/model gRPC catches (capstone F1/F2/F3)
- fix(clavity-ls): propagate a caller-cancel from the idle-wait progress probe (F3 consistency)
- fix(sp-b): fold agy-capstone R4 (mid-adjudication sha-race + shell-agnostic recovery)
- fix(sp-b): fold agy-capstone R3 - close breach-waiver gate-bypass
- fix(sp-b): fold agy-capstone R2 findings (honest best-effort envelope + WAIVED reason)
- fix(sp-b): fold agy-capstone R1 findings (3, measurement-verified)
- fix(sp0): derive Program.cs manualsDir staging path from PluginName (knowledge dir moved to plugins/clavity)
- fix(sp0): derive CliRouter staging pluginDir from PluginName (was stale clavity-dotnet)

## 0.3.1 — 2026-07-24

### Fixes
- fix(golden-header): route accumulated wisdom to the driver, not the agy peer (T4b)
- fix(curate-commit): decode stdin as strict UTF-8, not the console code page

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

