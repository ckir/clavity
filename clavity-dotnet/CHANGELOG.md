# dotnet changelog

## 0.8.0 — 2026-09-14

### Features
- feat(release): retire Inno for 3 members -> root marketplace + plugin.json version truth (Inno-retirement U3/U4 part 1)
- feat(dotnet): preserved-extras setup hook (Inno-retirement U2 extras)
- feat(dotnet): fetch-on-first-run clavity-ls + .mcp.json -> CLAUDE_PLUGIN_DATA (Inno-retirement U2 core)
- feat(s15): panel marker contract - agy-panel.head makes panel seams concludable (Fork D)
- feat(s15): register agy-consult-recovery on the compact matcher (both products)
- feat(s15): reader logic - candidate model + output vocabulary (5 branches, reply flag, lazy age)
- feat(s15): consult-recovery reader skeleton - guard prologue + empty cases
- feat(cli): wire the endpoint path (--mcp) and the pairing INSTALL.md (start)
- feat(launcher): inject -i 'Fetch and follow <INSTALL.md>' so agy self-publishes its endpoint
- feat(ls): resolve the agy endpoint-file path (CLAVITY_AGY_ENDPOINT)
- feat(ls): send x-codeium-csrf-token via a client interceptor; ConnectToEndpoint
- feat(ls): AgyEndpoint reader for the self-published agy-endpoint.json
- feat(s27): the head arm refuses a marker the ledger does not record
- feat(s27): a ledger reader that locates a sha positionally, never by searching
- feat(s27): the ledger row precedes the marker write, pinned in both halves
- feat(s25): bounded negotiation in the two review skills that lacked one
- feat(s24): the capstone's mandatory design consult, with isolation recorded not gated
- feat(s24): agy-mark stamp records consult/review cascade isolation
- feat(s23): require a ledger row before an audit run may complete
- feat(skills): 21.4 - JSON inline, with a reader that validates a DECLARED schema
- feat(skills): 21.2 - the peer-side axis is claim-type, not disposition
- feat(skills): 21.1 - put nothing after the terminal token
- feat(guard): monitor seams/ as one aggregate digest (owner-ruled)
- feat(guard): widen the census into .clavity subdirectories (owner-ruled)
- feat(guard): add the ignored-paths axis and enumerate the degraded axes
- feat(cheatsheet): EXTEND not REPLACE - add the GROWTH region, retire the legacy file
- feat(cheatsheet): strip the safety-guard framing - the artifact cannot hold a guard
- feat(ci): delete the paths filter - the bypass class cannot occur if there is no decision
- feat(agy-capstone): a stopping rule, so GREEN means the software works
- feat(agy-autotrain): move the capture inbox to ~/.clavity (ROADMAP 14g)
- feat(mcp): surface the 13b verdicts to the caller
- feat(ls): wire 13b at the projection seam, with its end-to-end controls
- feat(ls): ReplyArchive - persist every reply, best-effort
- feat(ls): ReplySizeHistory - the heuristic half of 13b
- feat(ls): DisciplineContract - the driver owns the terminal tokens
- feat(ls): SemanticEcho - proof the peer reached the artifact's end
- feat(ls): TerminalToken - the deterministic half of 13b
- feat(mcp): report liveness while agy_ask waits - the wait was silent for its whole duration
- feat(cheatsheet): promote the review-only-banner rule; park 64 on the SEED/GROWTH split
- feat(shield): 14c - agy-mark.sh, the sanctioned .clavity writer for the skills
- feat(shield): 14c - the SessionStart recorder asserts the shield before writing
- feat(shield): 14d - effect-checking .clavity shield helper, mirrored across both plugins
- feat(agy-autotrain): drain 42 inbox entries - cheatsheet round-shaping bullet + 3 backlog items
- feat(assertion-strength): add the PostToolUse hook, dotnet only
- feat(open-issues): disambiguate the intake bar and route promotions by product ownership
- feat(panel-review): disposition taxonomy and the stand-downs output
- feat(agy-test-audit): disposition taxonomy, completion enums, and the boundaries-file split
- feat(agy-capstone): add the AGY-SCOPE disposition taxonomy and rewrite the ALIGNED enum
- feat(hooks): register the capture reminder on UserPromptSubmit in both drivers
- feat(hooks): the capture reminder reaches a driver working directly
- feat(hooks): schema v:3 - source replaces reason, model recorded

### Fixes
- fix(┬º43-45): clear the 3 pre-existing ┬º15 CI-red items (ci-scripts + ci-injected-context)
- fix(s15): capstone r2 folds - complete case-robust reply probe + honest degrade
- fix(s15): capstone r1 folds - case-robust reply probe + sort-failure fallback
- fix(s21): close AGY-TEST-AUDIT gaps - reject empty citations, pin spawn-guard + schema boundaries
- fix(pairing): scope the agy endpoint file per session so two sessions cannot collide
- fix(capstone-s21-r3): revert the r2 case-fold - it false-passed PANEL VERDICT
- fix(capstone-s21-r2): fold the terminal-token match to OrdinalIgnoreCase
- fix(ls): teach the compiler IsUsableExpectation's non-null guard (CS8604)
- fix(cli): only set AgyInstallDocPath when the pairing doc exists (honor Null semantics in dev)
- fix(ls): auth_failed hint points at the stale endpoint + relaunch, not the keyring
- fix(ls): connect via the published endpoint; surface Unauthenticated as auth_failed
- fix(hooks,gates): a file as cwd defeated the kill-switch, and a local gate was red on output git ignores
- fix(s30): a jump out of a Check is reported, and no rule can edit the rule table (capstone round 6)
- fix(s30): four ways a rule or a hand-written check still escaped the runner (capstone round 5)
- fix(s30): a control-flow guard pins that no linter check is skipped after a failure - and it found one
- fix(installers): heal a duplicated PATH on every install, not only when the PATH task is ticked
- fix(installers): every install appended another PATH copy; add and remove entry by entry
- fix(s28): the guard recognises a dot-source by what it loads, and sees subdirectories
- fix(s28): the resolver guard discovers its population, and says only what the README says
- fix(s28): the capstone found the helper cost ~64s a run; replace it with a factory
- fix(ci): a Windows path collapsed the hook's self-directory, and no test invoked one
- fix(ci): auto-fix CI failure
- fix(triage): check-ignore has three exit codes, and a precondition must ask the shell that runs the code
- fix(capstone-r2e): existence is its own cause, and a correct shield cannot hide a tracked file
- fix(capstone-r2d): my own fix named the wrong permission, and my own teardown could leak
- fix(capstone-r2c): the degraded branch told the owner alone, and a comment invited the wrong fix
- fix(capstone-r2b): the shield fallback failed silent, reproducing the defect it exists to prevent
- fix(capstone-r2a): a range modifier defeated the left-endpoint guard, live on the shipped ledger
- fix(capstone-r1): fold three verified findings; two rejected by measurement
- fix(ci): two failures the local gate could not see, both caught by the push
- fix(s22): redirect stderr BEFORE the target, and GUARD the class
- fix(s31): the kill-switch reports to the model, not to the owner's screen
- fix(s31): zero footprint, and the kill-switch stops crying wolf
- fix(s27): the unreadable-ledger guard now fires on Windows too
- fix(s27): three spaces of indentation is still a table row
- fix(s27): a row that was SEEN and rejected must not look like no row at all
- fix(s27): the refusal must name its actual cause
- fix(s27): normalise CRLF before any parse rule sees the line
- fix(s27): a fence ends the table block it interrupts
- fix(s27): stop blacklisting containers - a record must live in a real table
- fix(s27): a closing fence carries no info string, and trim after unwrapping
- fix(s27): round 1's fence guard was worse than the defect it repaired
- fix(s27): a ledger row quoted inside a code fence authenticated a marker
- fix(ci): repair ci-scripts - a missing dependency, two regressions I authored, and an index that never grew
- fix(ci): run the Python bridge's 24 tests in CI - the last test suite no workflow executed
- fix(agy-mark): an empty timestamp shifts every field, and it took THREE tries to write a test that could see it
- fix(agy-mark): stamp was the ONE arm that never asserted the .clavity shield - R7's below-floor item was real
- fix(s24,s25): fold capstone round 5 - a fail-open, a fix that fixed nothing, and a trapped instruction
- fix(capstone): replace Rule B's regex engine with ast-grep, per owner ruling
- fix(s24-trigger): fold three adversarial-capstone-verified defects in the AGY-FIRST mandatory-consult trigger
- fix(s24,s25): repair the line-count claims this plan itself invalidated
- fix(hooks): stop rendering the anomaly reminder as a SessionStart hook ERROR
- fix(s29a): derive the strip set from the skip set so they cannot diverge
- fix(s29a): a decoration-only line must not mask a truncated reply
- fix(s29a): store the enforced token, and treat a leading bracket as decoration
- fix(s29a): the panel's terminal token is PANEL VERDICT, not GREEN
- fix(s29): correct the entry BEFORE planning it - both "false flags" were mine
- fix(record): there was NO review-only breach - restore the dev marketplace and retract the claim
- fix(s23): capstone R2 fold - a drifted citation and a message the R1 fold made false
- fix(s23): capstone R1 fold - Test-Path accepted a DIRECTORY, and the clause hid its own conventions
- fix(roadmap): the four SKILL.md line counts went stale when ┬º21 shipped
- fix(skills): 21.1 - ship the anti-wrap-up clause as PAYLOAD, not driver prose
- fix(0a): reconcile four stale ROADMAP headers and guard the claims that rotted
- fix(guard): fold capstone round 7 - a return that did not return
- fix(guard): fold capstone round 6 - a proven-vacuous row, and E2BIG
- fix(guard): fold capstone round 5 - the third constant-answer defect
- fix(guard): fold capstone round 4 - the prune was not a boundary
- fix(guard): fold capstone round 3 - a name collision masked a swap
- fix(guard): a literal CR byte was committed inside printf, not the escape
- fix(guard): fold capstone round 2 - the fixes' own edges
- fix(guard): fold capstone round 1 - five verified defects
- fix(agy-first): give the peer a legal scratch directory
- fix(panel): the escalation round had no safety envelope at all
- fix(19): capstone round 9 - the sha was validated in one mode of two
- fix(19): capstone round 8 - round 6's fix was applied to one file and not its sibling
- fix(17a): capstone round 6 - the file measured a rule, then applied it to one line of five
- fix(19): capstone round 5 - the header described a contract the code stopped honouring
- fix(19): capstone round 4 - the caller could still disturb the record, one level down
- fix(17a,19): capstone round 3 - a guard that reported success for a write it never checked
- fix(17a): capstone round 2 folds - the peer broke my new guard, and it was right
- fix(17a): capstone round 1 folds - retract entry M, and stop two diagnostics lying
- fix(17a): key the shield markers on the repository by storing them in it
- fix(capstone-r1): a reader with no writer, and two guards that certified what they had stopped checking
- fix(capstone-r1): the pair diverged on a present-but-unusable growth path
- fix(golden-header): raise the combined cap 16 -> 32 KiB - it was breached in production, silently
- fix(capstone-r27): one fact in FOUR places, and three numbers offered as evidence that were not
- fix(capstone-r25): one member could overwrite another member's registered marketplace
- fix(capstone-r24): a kill switch that stopped the output but not the side effects
- fix(capstone-r23): I invented the provenance for a fix while fixing false claims
- fix(capstone-r22): the one string that reaches another agent still asserted the old rule
- fix(capstone-r21): an interrupted migration was abandoned in silence
- fix(capstone-r20): all four guards I wrote were defeated, and one was defeating itself
- fix(capstone-r20): my ledger-row fix punished the driver who audited on time
- fix(capstone-r19): the capstone's mandatory last step silenced the audit it gates
- fix(capstone-r18): the destructive set was pinned, the consent that authorises it was not
- fix(docs): three stale doc claims - including a correction that was itself false
- fix(plugin): give clavity-ls a 1800s idle cap via the MCP env block
- fix(tests): fold capstone round 2 - the round-1 fixes had holes of their own
- fix(13b): fold capstone round 11 - a budget checked between lines cannot bound the read
- fix(13b): fold capstone round 10 - a hang is not an exception, and one assertion was vacuous
- fix(13b): fold capstone round 9 - harden the file read the trim introduced
- fix(13b): fold capstone round 7 - a claim I wrote one round ago was false
- fix(13b): fold capstone round 6 - an unbounded temp leak round 3 created
- fix(13b): fold capstone round 5 - a heuristic with no positive control, and two false comments
- fix(13b): fold capstone round 4 - the archive filename was culture-formatted
- fix(13b): fold capstone round 3 - two verified defects, both introduced by earlier folds
- fix(13b): fold capstone round 2 - four verified defects, one of them mine
- fix(13b): fold capstone round 1 - four verified defects
- fix(hooks): the A2 sweep gate assumed TMPDIR exists; its sibling never did
- fix(ls): absolute_max when the budget is spent, even if the server ended the window
- fix(ls): decide the idle-wait limit label from the clamp, not the clock
- fix(mcp): fold capstone round 3 - revert to the original catch; both "fixes" were the defect
- fix(mcp): fold capstone round 2 - my round-1 filter was wrong in BOTH directions
- fix(mcp): fold capstone round 1 - the progress catch swallowed cancellation too
- fix(tests): anomaly triage 2026-08-17 - 2 fixed, 4 promoted, 1 deleted
- fix(agy-mark): exit 2 is "attempted and rejected", not "failed partway"
- fix(shield): capstone R2 - the sweep had no oracle, and a comment claimed a shared dir
- fix(shield): capstone R1 - the mktemp fallback left the DIRECTORY exposed
- fix(shield): 14d - open-issues asserts the shield's EFFECT, not the file's existence
- fix(cheatsheet): regenerate both pinned literals to ASCII - the gate has been RED since 2026-08-09
- fix(injected-context): sanitise the whole domain - the gate now exits 0
- fix(injected-context): close 9 of the 10 audited anomalies (A2 withdrawn)
- fix(assertion-strength): co-locate the hook with agy-after-reminder
- fix(hooks): the consult guard names the concurrent-local-agent confound
- fix(ls): status mirrors the gRPC code, and a peer-refused call stops claiming a shutdown
- fix(ls): bound agy_look by step COUNT, and stop the hint asserting one cause for ResourceExhausted
- fix(ls): agy_look keeps the newest trajectory steps under a tight budget
- fix(ls): set MaxReceiveMessageSize deliberately instead of inheriting gRPC's 4 MB default
- fix(ls): ChannelDown.Hint names the real fault instead of always blaming a peer shutdown
- fix(hooks): agy-liveness-check walks to the root and names the file that exists
- fix(hooks): agy-test-audit-reminder honours a root .no-agy, and its degraded cwd now resolves
- fix(hooks): agy-anomaly-reminder honours a root .no-agy from a subdirectory
- fix(hooks): agy-seam-inject honours a root .no-agy, and its marker contract is now tested
- fix(hooks): agy-anomaly-dispatch-reminder honours a root .no-agy from a subdirectory
- fix(hooks): agy-anomaly-capture-reminder honours a root .no-agy from a subdirectory
- fix(hooks): agy-after-reminder honours a root .no-agy from a subdirectory
- fix(hooks): agy-anomaly-model-notice honours a root .no-agy from a subdirectory
- fix(hooks): register the recorder on SessionStart, delete the SessionEnd block
- fix(hooks): .no-agy did not suppress a subdirectory launch, and non-git dirs got a .clavity/
- fix(hooks): remove every subprocess - 1,4s was the EDGE of the surviving band, not inside it
- fix(hooks): the first real row exposed TWO corruptions - backslashes and CRs
- fix(hooks): split capture from analysis - the SessionEnd hook was CANCELLED in production

## 0.7.0 — 2026-08-04

### Features
- feat(hooks): discipline-reaching recorder - and the 20,9s budget blowout it hid
- feat(hooks): AGY-ANOMALIES contract stamp, plus the coverage gap it exposed

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

