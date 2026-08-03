# AGY-ANOMALIES: closing the capture-side gap — design

**Status:** owner-approved scope, 2026-08-04. Targets a v16 plugin release.
**Origin:** `TODO.md` (repo root, untracked), filed by a parallel agent working in another repository.

---

## Problem

The AGY-ANOMALIES discipline has a **drain** push and no **capture** push. Its sibling `agy-learn` has
the inverse. Each has exactly what the other lacks, and the anomaly side's absence is the more dangerous
of the two because it is invisible.

A parallel agent detected four genuine anomalies over ~3 hours of direct implementation work in another
repo, reported all four in chat, and captured none until the operator intervened — having stated, in as
many words, that no hook told it how to record anomalies. The mechanism existed, was installed, and was
working. It was never reached.

**Why silence is the worst symptom.** `agy-anomaly-reminder.sh:56` exits 0 when the anomalies file is
absent. So an absent file cannot distinguish:

- *no anomalies occurred*, from
- *anomalies occurred and were never captured*.

The failure is self-reinforcing: nothing captured → file never created → hook stays silent → the owner
gets no signal that captures are being missed. A visible pile of 69 stale `agy-learn` entries is a
nuisance you can see. An invisible zero looks like success.

### The two gaps — both verified against v0.5.0, not taken on report

**Gap (a) — direct-driver work has no capture push at all.**
Nothing in the runtime addresses the capture contract to a driver that notices a defect itself. That
contract lives only in the `clavity:open-issues` skill, which the agent must decide, unprompted, to pull
at the exact moment its attention is elsewhere by construction.

**Gap (b) — the dispatch-side seam does not survive compaction.** *(Not in the original report.)*
`agy-seam-inject` is registered `PreToolUse` matcher `Skill` (`hooks.json:5`) and extracts
`.tool_input.skill` (`agy-seam-inject.sh:42`); its ANOMALY-CAPTURE arm fires only for
`*subagent-driven-development*|*executing-plans*` (`:54`). **No hook in either plugin matches the
Agent/Task tool.** Skill invocation is a one-shot event, so:

> invoke `subagent-driven-development` → `/compact` → dispatch four subagents
> = the ANOMALY-CAPTURE directive fires **zero times** across exactly the work it governs.

The reporting agent demonstrated this from its own session. This session is another instance.

**Gap (b) is not a new nicety — it is the previously-negotiated fix silently not firing.** An earlier
negotiation (`.clavity/seams/anomaly-capture-negotiate.md` §3) established *by measurement* that anomalies
died at **relay**, not at noticing: the driver compressed a subagent report into a summary. The resulting
rule is recorded at `open-issues/SKILL.md:41-44` — *"the loss … is fixed by requiring the driver to
CAPTURE BEFORE SUMMARIZING."* `PreCompact` **cannot** catch that loss: by the time compaction runs, the
report is already a two-line summary.

---

## Non-goals — withdrawn, and by whom

| proposal | disposition |
|---|---|
| A `Stop` hook alongside `PreCompact` | **Withdrawn by the report's author.** It cited `agy-learn` as the proven shape, which uses `PreCompact`+`SessionStart` and *not* `Stop`. Fires 100+ times in a long session and would manufacture exactly the blind-answering that `adversarial-panel-review`'s `--low` bypass exists to avoid. |
| A once-per-repo "no anomalies ever captured here" notice | **Withdrawn by its author.** Gated on file-absence it cannot distinguish "captured nothing" from "nothing happened yet", and the once-per-repo guard makes it fire at the moment of *least* diagnostic value and stay silent through the months of most value. |
| Auto-detecting anomaly-shaped language in tool output | Rejected in the original report and not revisited. Misses the quiet cases, fires on ordinary debugging. |
| Modifying `agy-seam-inject.sh` to handle `Agent` calls | Rejected. Its `case` keys on `$skill`, absent for an Agent payload. Gap (b) is closed by an **isolated** hook; `agy-seam-inject.sh` is not touched. |

---

## The channel contract — load-bearing, and measured

A sentinel experiment (three arms, `PostToolUse`, run by the reporting agent; full table in the appendix)
established two facts, the second of which **neither reviewing model predicted**:

1. **`exit 2` does not deliver stdout to the model.** The runtime treats it as a blocking error and
   surfaces *stderr* only.
2. **`exit 0` is necessary but NOT sufficient.** Plain text on stdout at `exit 0` is **silently
   discarded**. The delivery channel is specifically the JSON envelope.

> **The trap:** a hook written with a plain `printf` produces no error, no output, and looks installed
> and working. This is the single most likely way this change ships broken.

**The envelope is event-specific**, already documented and implemented at `agy-learn-reminder.sh:34-39`:
`hookSpecificOutput` is **invalid for `PreCompact`** (the owner sees a schema-validation dump instead).

Every channel this design uses has a production precedent:

| event | audience | shape | precedent |
|---|---|---|---|
| `PreCompact` | model | `{"systemMessage": "…"}`, exit 0 | `agy-learn-reminder.sh:38` |
| `SessionStart` | model | `hookSpecificOutput{hookEventName:"SessionStart"}`, exit 0 | `agy-learn-reminder.sh:39`; observed live 2026-08-04 as *"SessionStart hook additional context: agy-curate nudge…"* |
| `SessionStart` | owner | stderr + `exit 2` — **non-blocking** | `agy-anomaly-reminder.sh:9-12`, `agy-liveness-check.sh:8` |
| `PreToolUse` | model | `hookSpecificOutput{hookEventName:"PreToolUse"}`, exit 0 | `agy-seam-inject.sh:71` |

### 🔴 `exit 2` is non-blocking on `SessionStart` but BLOCKING on `PreToolUse`

Documented verbatim at `agy-liveness-check.sh:8`. A non-zero exit from the new dispatch hook would
**block every subagent dispatch**. Both shipping `PreToolUse` hooks fail open — 8 × `exit 0` each, zero
non-zero paths. **The new dispatch hook must copy that exactly.** This is the highest-blast-radius item
in the change and the constraint that makes it safe.

---

## Design

### 1. `agy-anomaly-capture-reminder.sh` — `PreCompact`, model-addressed *(closes gap (a))*

Registered `PreCompact`, matcher `manual|auto`. Emits `{"systemMessage": …}`, exit 0. Suppressed by
`.no-agy` (workspace or global), like every other reminder.

**Wording is a hard constraint, not prose.** agy named the failure mode this text must prevent —
*"Pre-Compaction False-Capture Rush"*: under context pressure the model logs **in-flight, in-scope** work
as an anomaly without meeting the verification bar. Its observable symptom is an entry whose `task=`
matches the session's own primary work. The text must therefore restate the verification bar and
explicitly exclude in-scope failures:

> AGY-ANOMALIES check BEFORE COMPACTION: did you VERIFY a defect this session that is OUTSIDE your
> current task and is not yet in `.clavity/local-anomalies.md`? Capture it now via the `open-issues`
> skill — one line: `- [type] fact * path:LINE * DATE * task=<what you were doing>`. Uncaptured
> anomalies are lost at compaction. NOT an anomaly: a test you expected to fail, an error in the work
> you are actively doing, or anything you have not verified by measurement. If nothing qualifies, do
> nothing — a speculative entry is worse than none, because it lands on a blocking triage gate.

### 2. Widen the drain matcher *(makes the existing owner signal reachable)*

`"matcher": "startup"` → `"matcher": "startup|resume|compact"` for `agy-anomaly-reminder.sh`, in **both**
drivers' `hooks.json`. Long sessions in an active repo accumulate the most anomalies and compact the most
often; as registered they get the drain notice least. No script change.

### 3. `agy-anomaly-dispatch-reminder.sh` — `PreToolUse` matcher `Agent`, isolated *(closes gap (b))*

A **separate** script. `agy-seam-inject.sh` is not modified. Emits
`hookSpecificOutput{hookEventName:"PreToolUse"}` at exit 0, carrying **only** the capture-relay rule — no
FILES clause, no implementer-dispatch obligations, so it is harmless when the subagent is a reviewer or
auditor:

> AGY-ANOMALIES relay: when this subagent returns, if it reports anything under `## Anomalies noticed`
> that is outside its task, VERIFY it by measurement and APPEND it to `.clavity/local-anomalies.md`
> BEFORE you write your summary. A verified anomaly that exists only in a chat message is lost the
> moment you compress that message.

**Must fail open on every path** — see the blocking rule above.

### 4. *(Optional, owner's call)* Dual-channel the `SessionStart` notice

No longer blocked: the sentinel determined the design. It is **two hooks on one matcher** — `hooks.json`
already registers two commands under `SessionStart` — one emitting the JSON envelope at exit 0 for the
model, one emitting stderr at `exit 2` for the owner. They cannot come from the same invocation. Lowest
value of the four; include or drop on merit.

---

## File manifest

| file | change |
|---|---|
| `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh` | **new** |
| `clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh` | **new**, byte-identical mirror |
| `clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh` | **new** |
| `clavity-classic/plugin/hooks/agy-anomaly-dispatch-reminder.sh` | **new**, byte-identical mirror |
| `clavity-dotnet/plugin/hooks/hooks.json` | register both; widen the drain matcher |
| `clavity-classic/plugin/hooks/hooks.json` | same edits (it differs from dotnet by exactly one legitimate line — classic-only `agy-drive-session-reset.sh`) |
| `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1` | **new** suite |
| `scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1` | **new** suite |
| `justfile` | register both new suites in a half |
| `scripts/tests/_partition.md` | re-measure BOTH halves by running each recipe |

**Not touched:** `agy-seam-inject.sh`, `agy-anomaly-reminder.sh` (script body — only its registration
changes), `open-issues/SKILL.md`.

---

## Testing

Both new hooks are mirrored, so `plugin-hooks-payload.Tests.ps1` covers them automatically for pure-ASCII
and cross-driver byte parity — it discovers the payload by glob, so no edit is needed there.

Per-hook suites must pin, at minimum:

1. **Envelope shape per event.** The `PreCompact` hook emits a top-level `systemMessage` and **not**
   `hookSpecificOutput`; the dispatch hook emits `hookSpecificOutput` with `hookEventName:"PreToolUse"`.
   Assert the parsed JSON key, not a substring — this is the silent-failure mode.
2. **Fail-open on the dispatch hook.** Assert exit 0 on: malformed payload, absent `jq`, unreadable cwd,
   and a non-Agent payload. There must be **no** path that exits non-zero.
3. **`.no-agy` suppression**, workspace and global, on both hooks.
4. **Wording invariants on the capture nudge** — assert the clause WHOLE via `[regex]::Escape`, not by
   bookend fragments. A prior epic proved bookend assertions leave ~95% of a directive unguarded.
5. **The widened matcher** — that the drain hook still fires on a `compact`/`resume` payload.

---

## Acceptance criteria

1. Both new hooks exist in both drivers and are byte-identical across them.
2. The `PreCompact` hook emits `{"systemMessage": …}` and exits 0; it does **not** emit
   `hookSpecificOutput`.
3. The dispatch hook emits `hookSpecificOutput{hookEventName:"PreToolUse"}`, exits 0 on **every** path,
   and carries no FILES clause.
4. The capture nudge's text contains the verification bar and the explicit in-scope exclusion, asserted
   whole.
5. `agy-anomaly-reminder.sh`'s registration is `startup|resume|compact` in both drivers; its script body
   is unchanged.
6. `agy-seam-inject.sh` is byte-identical to its pre-change state.
7. All 17+ shipped hooks remain pure ASCII with zero CR; every mirrored pair identical.
8. Both `_partition.md` counts re-measured by running each recipe — never computed.
9. New assertions proven non-vacuous by a mutation verified to have landed; negative assertions carry a
   control.

---

## Risks

| risk | mitigation |
|---|---|
| **Silent no-op** — a hook written with `printf` delivers nothing and looks fine | Acceptance criteria 2–3 assert the parsed envelope key; test 1 is written before the hook |
| **Blocked dispatches** — a non-zero exit from the `PreToolUse` hook halts every subagent call | Fail-open is an acceptance criterion with a dedicated test arm per failure mode |
| **False captures flooding a blocking triage gate** | Wording constraint in item 1, asserted whole |
| **Drift between drivers** | Already enforced by `plugin-hooks-payload.Tests.ps1` (glob-discovered) |
| Suite counts decay | `_partition.md` re-measured; it now carries the counting command |

---

## Appendix — sentinel measurement

Run on `PostToolUse` (`matcher: "Bash"`) in a project-local `settings.local.json`, three arms:

| # | hook body | exit | reached the model |
|---|---|---|---|
| 1 | plain stdout + stderr | 2 | **stderr only** — stdout absent |
| 2 | plain stdout + stderr | 0 | **nothing at all** — silently discarded |
| 3 | `hookSpecificOutput.additionalContext` JSON | 0 | **delivered** |

Cleanup verified: throwaway hook removed, `settings.local.json` restored and diffed byte-identical,
`git status` clean.

**Scope caveat, and how it was closed.** The arms ran on `PostToolUse`, not `SessionStart`. Arm 3 on
`SessionStart` is nonetheless confirmed by production observation — the agy-curate nudge was delivered as
*"SessionStart hook additional context: …"* on 2026-08-04. Arm 1 on `SessionStart` is moot: this design
never places stdout on an `exit 2` hook.
