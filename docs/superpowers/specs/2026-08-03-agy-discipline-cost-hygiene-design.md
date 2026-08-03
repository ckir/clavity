# Design — cost/quota hygiene for the shipped agy disciplines

**Date:** 2026-08-03
**Status:** design, approved in brainstorm; panel round 1 folded; implementation plan not yet written
**Owner ruling:** ship layers 1 and 2 now; layer 3 (the tier dimmer) becomes a separate roadmap item
and is reconsidered afterwards.

## Problem

The AGY-* review disciplines ship to third parties in the clavity plugin. They are deliberately
multi-round — that is where their defect-detection comes from — but nothing in the shipped product tells
a user, or the agent driving it, that *when* a discipline runs dominates what it costs.

The failure mode is not "the review was expensive". It is **the user stops using the product**: they
uninstall, or they set `.no-agy` and lose every discipline at once.

Two facts make this a shipping defect rather than a user-education gap:

1. **The shipped hooks fire at the most expensive possible moment — by design.** They trigger when work
   finishes, which is late in a session, when context is at its maximum.
   (`clavity-dotnet/plugin/hooks/hooks.json`: `agy-after-reminder.sh` on `Write|Edit`,
   `agy-test-audit-reminder.sh` on `Bash|Write|Edit`, `agy-seam-inject.sh` on `Skill`.)
2. **A hook directive outranks documentation.** The hook injects text into the conversation; a README
   does not. `agy-test-audit-reminder.sh:68` instructs the agent to "invoke the `agy-test-audit` skill to
   convene the live agy peer" with no cost qualification, and the agent obeys the text it can see.
   Documentation alone therefore cannot change the behaviour — which is why layer 1 exists.

   **This premise was observed, not merely reasoned.** During the session that produced this design, the
   `agy-after-reminder` directive fired repeatedly and drove the agent into running a full multi-round
   adversarial panel each time, without the user ever asking for one. A hook directive demonstrably
   changes what the agent does. That is the whole basis for expecting a COST clause in the same channel to
   work — and equally the reason its wording must not become an excuse to skip a gate.

Measured: **zero mentions of cost, quota, context size, or compaction in any shipped hook, on either
driver.**

**The two drivers do not ship the same hook set, and this matters for every count in this document.**
`clavity-dotnet/plugin/hooks/` holds 8 shell scripts; `clavity-classic/plugin/hooks/` holds 9 — the extra
is `agy-drive-session-reset.sh`, which exists only in classic. It was read in full and checked separately:
it clears a once-per-session driver-guidance flag on `source==startup` and convenes no discipline, so the
placement rule does not reach it and it carries no added text. Their `hooks.json` files also differ (they
must, since classic registers one more hook). So "byte-identical across the drivers" is a property of the
**individual hook scripts this change touches**, never of the plugin trees as a whole.

## Evidence

Measured by parsing one real 543-turn driver session's own transcript. Cost shares were computed from
token counts times the standard relative multipliers (uncached input 1.0, cache write 1.25, cache read
0.1, output 5.0). The resulting dollar total (`$379.84`) matched the harness's independently reported
figure (`~$366.19`, sampled slightly earlier in the same session) to within 2%, which corroborates the
model.

| finding | measurement |
|---|---|
| Share of session spend that is **context re-payment**, not generation | **87.2%** (cache read 59.2% + cache write 27.9%; output only 12.8%) |
| Context growth | 89k → 508k tokens across 522 turns, with **one** compaction |
| Same 305 turns of work, carried at ~380k context vs 40k | **$249 vs $47** |
| Tokens re-read per turn at those two context sizes | **~9.5×** |
| What the context actually consists of | 610k cumulative assistant output before compaction vs ~88k tokens of *all* tool results — roughly **7:1** |

Two consequences worth stating plainly, because both contradict intuitions this project has held:

- **Reducing agy rounds is not the lever.** Peer inference is billed on the peer's side; a round costs
  the driver only its payload and reply. Cutting rounds sacrifices proven defect detection for a small
  fraction of the spend.
- **Delegating bulky tool output is not the main lever either.** All tool results across the whole
  session came to ~88k tokens. The context is dominated by the agent's own prior prose.

The lever is **when a discipline runs**, not whether, and not how many rounds.

## Two audiences, one remedy

| audience | what they experience | what they watch |
|---|---|---|
| **Subscription** | Quota burn. A review fired at high context can consume the usage window needed to finish the work — **work stops mid-task**. | `/usage` |
| **API-billed** | The invoice. | cost |

The remedy is identical for both; only the framing differs. User-facing text must therefore lead with
**tokens and quota** and treat dollars as secondary.

Two multiples must not be conflated: context re-read scales ~9.5×, while measured *cost* scaled 5.3×,
because output and cache writes do not scale with context size. Separately, **the token multiple must not
be restated as a quota multiple.** Subscription usage windows are not a documented linear function of
tokens read, so user-facing text may say quota is consumed *faster*, and must not assert a specific
multiplier for it.

## Non-goals

- Reducing the number of rounds in any discipline. The owner's standing ruling — "review is INVESTMENT,
  not cost; repeat until green" — is unchanged by this design.
- Weakening, bypassing, or making optional any review gate.
- Any change to `.no-agy` semantics. It stays global; layer 3 is deferred.
- Recommending third-party tooling in shipped documentation.

## Layer 1 — a cost clause in the hook directives

### Placement rule

The clause goes where **both** conditions hold:

1. the site convenes a **multi-round** discipline, **and**
2. the site's trigger is **durable** — it will fire again in a fresh session, so deferring the review
   moves it rather than losing it.

Condition 2 is not cosmetic. `agy-after-reminder.sh` is an ephemeral `PostToolUse` trigger on `Write|Edit`
with **no marker file**: once the write event has passed, a fresh session will never re-fire it. Telling
the agent to defer that particular review would silently drop the gate, which is the opposite of this
design's intent. By contrast `agy-test-audit-reminder.sh` is marker-gated (it re-fires while
`agy-test-audit.head != HEAD`), and `agy-seam-inject.sh` re-fires whenever the user re-invokes the skill.

| site | discipline | clause? | why |
|---|---|---|---|
| `agy-test-audit-reminder.sh:68` | agy-test-audit | **yes — COST clause** | multi-round; marker-gated, so it re-fires |
| `agy-seam-inject.sh:77` | agy-capstone | **yes — COST clause** | rounds-until-green; re-fires on skill re-invocation |
| `agy-seam-inject.sh:75` | agy-first | **yes — SESSION POSTURE line** | the documented entry point; see below |
| `agy-after-reminder.sh:36` | adversarial-panel-review | **no** | multi-round but **not durable** — deferring it loses the gate |
| `agy-seam-inject.sh:79` | anomaly-capture | **no** | a dispatch obligation, no rounds |

`agy-seam-inject.sh` selects the discipline through a strict 1:1 `case` at `:51-55`; the AGY-CAPSTONE and
AGY-FIRST arms are touched, the ANOMALY-CAPTURE arm is not.

### The COST clause (exact text)

Appended to `agy-test-audit-reminder.sh:68` and `agy-seam-inject.sh:77`:

> COST: this discipline re-reads the whole session context every round, so running it in a long session
> burns several times the tokens - and subscription quota - of running it fresh. If this session carries
> substantial history, do not run it inline: tell the user it runs about 5x leaner after /compact or in a
> fresh session, and follow their answer. This changes WHERE the review runs, never WHETHER.

### The SESSION POSTURE line (exact text)

Users are directed to begin work from `superpowers:brainstorming`. That makes the AGY-FIRST arm (selected
by `case *brainstorm*` at `:53`, emitted at `:75`) the **earliest hook fire available**, landing while
context is still small — the one place where cost guidance is both cheap to deliver and still actionable.
Everywhere else the advice arrives after the expensive context has accumulated.

**This is a reachability limit, not a guarantee.** The seam fires only when the user actually invokes a
brainstorming skill. A user who starts by writing code, or from `writing-plans`, never sees the SESSION
POSTURE line, and for them the COST clause at the later sites is the only guidance that lands. The line is
therefore best-effort reinforcement of the documented flow, not a mechanism that covers every user. Layer
2's README section is what covers the rest.

Appended to `agy-seam-inject.sh:75`:

> SESSION POSTURE: reviews later in this work (capstone, test audit, panel) re-read the whole session
> context each round, so they run far leaner in a fresh session than at the end of a long one. Plan to
> commit first, then run them after /compact or in a new session.

This is **prospective** rather than a judgment about the current session, which sidesteps the weakness in
the COST clause noted below: at brainstorm time the session is known to be fresh, so no unobservable
"is this session long?" assessment is required.

### Insertion position

Appended to the **end** of each existing directive string, after its current closing sentence, separated
by a single space (these are single-line shell string literals; no newline is introduced). The existing
wording is not otherwise altered — this is an addition, not a rewrite, so the anchors the current tests
match on are untouched.

**Not applied to the `jq`-missing fallback paths.** Each hook carries a degraded branch that emits a
hardcoded "guard inactive" warning when `jq` is absent (`agy-seam-inject.sh:37`,
`agy-test-audit-reminder.sh:52`, `agy-after-reminder.sh:20`). Those emit a *failure notice*, not a
directive to convene anything, so the placement rule does not reach them and they stay unchanged.

### Design constraints on the wording

These are hard constraints, each verified against the code or a test:

1. **The final sentence is the integrity guard.** Without it a cost clause becomes a licence to skip the
   gate — precisely the failure the global-only kill-switch exists to prevent
   (`clavity-dotnet/plugin/README.md:128`). It is not optional phrasing.
2. **It ends by deferring to the user.** The agent proposes; it never unilaterally defers a review.
3. **It is phrased as a judgment the agent makes** ("substantial history"), because giving the agent a
   real token count requires new hook logic. That is layer 3, not this change. See *Known weaknesses*.
4. **It is deliberately short.** The clause is injected on every fire, so its own length is a recurring
   token cost. Two sentences is the budget.
5. **Pure ASCII — mechanically enforced.** All three suites assert it at byte level:
   `scripts/tests/agy-seam-inject.Tests.ps1:98-100`, `agy-after-reminder.Tests.ps1:56-57`,
   `agy-test-audit-reminder.Tests.ps1:146-147` each read the hook's bytes and require zero above 127.
   No em-dash, no curly quote, no `×`.
6. **No backtick, no apostrophe — the two sites use different quoting regimes.**
   `agy-seam-inject.sh:75/77` and `agy-test-audit-reminder.sh:68` are single-quoted `emit '...'`, where an
   apostrophe would terminate the string (the file already needs the `'"'"'` idiom for existing ones).
   `agy-after-reminder.sh:36` is double-quoted `msg="..."`, where a backtick becomes command substitution
   and would execute at hook runtime. Text that is safe in both regimes contains **neither**. Write
   `/compact`, not a backticked one.

### Known weaknesses (accepted, not solved here)

- **The clause's trigger is not observable by the actor asked to act on it.** "Substantial history" asks
  the agent to assess a context size it has no reliable read of, so the clause may fire on a short session
  (friction) or not fire on a long one (dead text). Giving the hook a real measurement — it already
  receives `transcript_path` on stdin — is layer 3, not this change. The SESSION POSTURE line at the
  brainstorm seam partly compensates by setting the habit before the question arises.
- **A deferred review depends on the user following through.** Both clause sites re-fire, so the gate is
  not lost, but the deferral has no durable record of its own.

## Layer 2 — a README section

### Exact text

> ## Running this economically
>
> clavity's review disciplines are multi-round by design — that's where the defects come from. But ~87%
> of an agent session's token use is re-reading its own accumulated context rather than producing new
> output. **Every turn re-reads everything before it**, so a review run at the end of a long session
> consumes several times the tokens it would in a fresh one.
>
> Measured on one real session — 305 turns of work at a ~380k context versus the same turns at 40k: about
> **9x the tokens read, for identical work**.
>
> - **On a subscription**, tokens are what matter: a review fired at high context burns through your usage
>   window far faster, and that is what stops work mid-task. Check `/usage` before starting a long review.
> - **On API billing**, that same run measured $249 against $47.
>
> Three habits, in order of payoff:
>
> 1. **Two chats.** Implement and commit in one session. Then `/compact`, or open a fresh chat, and run
>    the review there: *"run agy-capstone on `<range>`"*. Same rigor, a fraction of the tokens.
> 2. **Match the ceremony to the stakes.** The full harness is built for code where a missed defect is
>    expensive. On a smaller project, the cheapest move is habit 1 rather than switching anything off —
>    the disciplines still run, they just cost a fraction. Several of them are triggered by hooks rather
>    than invoked by you, and they are not individually switchable today; a finer-grained mode is under
>    consideration.
> 3. **Fix coverage gaps inline, for free.** Notice a missing test while implementing? Just ask for it
>    then — *"add a test for that case"*. One turn. Convening a full audit to rediscover the same gap
>    costs many. Save the convened audit for the gaps you *didn't* notice.
>
> **Turning it down.** If you do need to silence the disciplines, `.no-agy` in your project root or
> `~/.claude/` does it — but it is deliberately all-or-nothing, so it silences **every** one of them,
> including the cheap ones. It is a last resort rather than a tuning knob; try habit 1 first. A
> finer-grained mode is under consideration.

### Why habit 3 is scoped the way it is

Shifting work left is only cheap when it costs **zero extra turns**. Asking for a test the moment a gap is
noticed is one turn. Convening a peer consult mid-implementation is not the same thing, and would cost
more than it saves — intermediate code churns, so a review of it is frequently discarded work. The wording
deliberately describes the zero-turn variant only, so it cannot be generalised into the expensive one.

### Text constraints

- **No promise of unscheduled work.** Layer 3 is deferred and unscheduled, so the text says "under
  consideration", never "on the roadmap" — a shipped doc must not commit to a date nobody has set.
- **Habit 2 must not imply selective opt-out.** Several disciplines fire from hooks, so "leave the rest"
  read alone would be false.
- **Habit 2 must also not route the reader to the kill-switch.** Pointing a "this is more ceremony than I
  need" reader at `.no-agy` tells them to disable everything, which *accelerates* the abandonment this
  section exists to prevent. The cheap remedy (habit 1) is the answer; the kill-switch is disclosed
  honestly as a last resort, not offered as a tuning knob. **This constraint exists because the fix for
  the previous one created the defect** — a worked example of why a fold gets re-reviewed.
- **Dollars stay out of the opening summary.** A prospective user evaluating the plugin should meet the
  token multiple first; the dollar figure belongs in the API-billing bullet. Leading with a bolded
  four-figure sum invites bill-shock churn before the reader has seen any value.

### Placement

- **Full section:** `clavity-dotnet/plugin/README.md` and `clavity-classic/plugin/README.md`. Measured:
  both open with `# <title>` then `## What's in here` at `:10`, then `## Install / registration`. Insert
  the new `## Running this economically` **immediately after `## What's in here`** in both — structurally
  identical in the two files, and early enough that a reader evaluating the plugin meets it before setup
  rather than after their first expensive session. (The files diverge below that point — dotnet has
  `## Troubleshooting` and `## Hook ownership`, classic has sub-sections under MCP configuration — so do
  not anchor on anything lower.)
- **One-line pointer:** root `README.md`, at the end of `## How to get started` (`README.md:27`) —
  *"Review disciplines are multi-round; see Running this economically before you start."*

## Cross-driver parity

The three hooks are currently byte-identical between `clavity-dotnet/plugin/hooks/` and
`clavity-classic/plugin/hooks/` (verified). Each edit must be applied to both copies.

**Enforcement is inconsistent, and the gap lands exactly where this change works.** Measured:

| suite | pins byte-identity with the classic mirror? |
|---|---|
| `agy-test-audit-reminder.Tests.ps1:149` | **yes** — `It 'is byte-identical to the clavity-classic mirror'` |
| `agy-seam-inject.Tests.ps1` | **no** |
| `agy-after-reminder.Tests.ps1` | **no** |

So one of the two hooks this change edits is protected and the other — `agy-seam-inject.sh`, where two
separate arms are touched — is not. `scripts/check-core-integrity.ps1:4` does not close the gap: it
compares each protected file against its own committed HEAD blob (tamper detection), not against the other
driver's copy.

Because the pattern already exists as `agy-test-audit-reminder.Tests.ps1`'s
`It 'is byte-identical to the clavity-classic mirror'`, adding the same assertion is a copy of established
repo practice rather than new design. **Both remaining mirrored hooks are pinned by this change**, not
deferred:

- `agy-seam-inject.Tests.ps1` — because this change edits that hook, on both drivers.
- `agy-after-reminder.Tests.ps1` — **even though its hook is not edited**, because the negative assertion
  that pins its *exclusion* inspects only the dotnet copy (see *Testing*). Without parity, classic's copy
  could gain the clause with nothing failing.

After this change all three mirrored hook **scripts** are pinned. What remains deferred is parity for the
other mirrored plugin files, which this change does not touch.

## Testing

The existing hook suites assert on **anchors**, not whole message strings — e.g.
`scripts/tests/agy-seam-inject.Tests.ps1:44-45` matches `'AGY-CAPSTONE auto-fire'` and `'agy-capstone'`.
Appending text therefore does not red them. The ASCII byte tests (constraint 5) **will** catch a non-ASCII
character, and are the existing safety net for that class.

Nothing currently pins the clause's *presence*, so a future edit could silently drop it. Add one assertion
per touched directive:

| suite | asserts |
|---|---|
| `agy-test-audit-reminder.Tests.ps1` | the COST clause is present (anchor: `COST:` and `never WHETHER`) |
| `agy-seam-inject.Tests.ps1` (capstone arm) | same anchors on the AGY-CAPSTONE emit |
| `agy-seam-inject.Tests.ps1` (brainstorm arm) | `SESSION POSTURE:` present on the AGY-FIRST emit |

Add one negative assertion too: the AGY-FIRST emit must **not** contain `COST:`, and the
`agy-after-reminder` message must contain neither anchor — otherwise the placement rule is unpinned and a
later edit could reintroduce the non-durable-deferral defect.

Plus parity assertions for **both** `agy-seam-inject.Tests.ps1` **and** `agy-after-reminder.Tests.ps1`,
copied from `agy-test-audit-reminder.Tests.ps1`'s `It 'is byte-identical to the clavity-classic mirror'` — a `Get-FileHash` (SHA-256) comparison against
the classic mirror:

```powershell
It 'is byte-identical to the clavity-classic mirror' {
    $classic = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-classic/plugin/hooks/<hook>.sh'
    (Get-FileHash $script:Hook).Hash | Should -Be (Get-FileHash $classic).Hash
}
```

**`agy-after-reminder` needs one even though its hook is not edited, and the reason is subtle.** Every
suite roots `$script:Hook` at the **dotnet** copy, so the negative assertion that pins this hook's
*exclusion* — that its message carries neither anchor — only ever inspects dotnet. If a later edit added
the clause to classic's copy alone, nothing would fail, and the excluded non-durable site would silently
start telling agents to defer a review that never re-fires. That is precisely the CA-1 defect, re-entering
through the driver the tests do not look at. The parity assertion is what makes the negative assertion
cover both drivers.

**Both touched suites live in the SLOW half**, which changes how they are run and which count is
re-measured. Measured from the justfile:

| suite | recipe | note |
|---|---|---|
| `agy-seam-inject.Tests.ps1` | `test-scripts-slow` (`justfile:101`) | touched |
| `agy-test-audit-reminder.Tests.ps1` | `test-scripts-slow` (`justfile:101`) | touched |
| `agy-after-reminder.Tests.ps1` | `test-scripts-fast` (`justfile:94`) | **hook** not touched, but the **suite** gains the negative assertion |

**The hook and its suite are touched independently — do not conflate them.** `agy-after-reminder.sh`
itself is excluded by the placement rule and must not change, but its *test* gains the negative assertion
that pins that exclusion. So a FAST suite does change, even though no fast-half hook does.

Consequences the implementer must not get wrong:

- **Both** counts in `scripts/tests/_partition.md` move and both must be re-measured: slow, because the
  two touched hooks' suites live there; fast, because `agy-after-reminder.Tests.ps1` gains an assertion.
- `test-scripts-slow` can exceed the 600s foreground tool cap, so per `_partition.md` it must be
  **backgrounded** and blocked on its own `Tests completed` line — never on a process count.

**Positive and negative assertions are proven differently — do not apply one procedure to both.**

- **Positive assertions** (the clause IS present) are watched **RED first**: written before the hook text
  is added, they fail because the anchor does not yet exist, then go green when it does. Standard TDD.
- **Negative assertions** (the clause is ABSENT where the rule excludes it) **cannot be watched RED** —
  they pass on clean baseline precisely because the forbidden string does not exist yet. Watching them
  "fail first" is impossible, and an implementer following a blanket RED-first instruction will either
  stall or contort the test. They are proven non-vacuous by **mutation** instead: temporarily insert the
  forbidden anchor into the hook, confirm the assertion fails, then revert and confirm it passes. The
  mutation must be proven to have landed — a mutation that silently did not apply produces a
  green-looking test that proves nothing.

Any count in `scripts/tests/_partition.md` is re-measured by running the recipe — never by addition or
subtraction.

## Deferred work

1. **Layer 3 — the tier dimmer.** Replace the binary `.no-agy` with a loud, self-announcing reduced mode
   (working name `CLAVITY_TIER=lean`): interactive skills stay available, end-of-branch auto-fire hooks go
   dormant, and every affected surface announces the mode. This preserves the anti-*silent*-disable
   rationale, which is about concealment rather than reduction. Real code, and it reopens a deliberate
   design decision, so it gets its own roadmap item. Owner ruling: reconsider after layers 1-2 ship.
2. **A durable marker for `agy-after-reminder.sh`.** It is the only multi-round discipline whose trigger is
   ephemeral, which is why it is excluded from the clause above. Giving it a marker (as
   `agy-test-audit-reminder.sh` has) would make it durable and let it carry the clause too.
3. **A real context measurement in the hooks.** They already receive `transcript_path` on stdin, so the
   "substantial history" judgment could be replaced by a measured threshold. This is what would turn
   constraint 3 from a weakness into a mechanism.
4. **Cross-driver parity for the mirrored files this change does NOT touch.** After this change all three
   mirrored hook *scripts* are pinned (`agy-test-audit-reminder` already was; `agy-seam-inject` and
   `agy-after-reminder` are pinned here). What remains unpinned is every other mirrored plugin file —
   skills, knowledge manuals, and the rest — and no gate compares the two plugin trees wholesale.
   Reachable, since a future edit can diverge them silently, so it stays tracked.

## Risks

| risk | mitigation |
|---|---|
| The clause reads as permission to skip a gate | The "never WHETHER" sentence; the durability condition in the placement rule; a test asserting the anchors are present |
| The two touched hooks must stay in sync across both drivers (four files) | A single commit touches all four, and after this change **all three** mirrored hook scripts are pinned by a SHA-256 parity assertion — `agy-test-audit-reminder` already was, and this change adds one for `agy-seam-inject` and one for `agy-after-reminder`. Only the *other* mirrored plugin files remain unpinned (deferred item 4) |
| Added text costs tokens on every hook fire | Capped at two sentences; only three of five directive sites carry any added text |
| The quoted figures come from a single session | Stated as such in the README text ("one real session"); the method is reproducible from the transcript |
| `/compact` is itself a summarization pass over the whole context, so the net saving is smaller than the raw multiple | The recommendation stands on the measured 305-turn comparison, which is a like-for-like turn cost; the one-off compaction cost is not modelled and is assumed small against a 300-turn tail. **Unquantified — flagged, not proven.** |

## File manifest

Every file this change touches, in one place. The rest of this document derives these from five separate
sections; a review whose dominant defect class was *facts restated in scattered places* should not also
require the implementer to assemble its own file list.

| # | file | change |
|---|---|---|
| 1 | `clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh` | append COST clause to the emit |
| 2 | `clavity-classic/plugin/hooks/agy-test-audit-reminder.sh` | identical (parity) |
| 3 | `clavity-dotnet/plugin/hooks/agy-seam-inject.sh` | append COST clause to the AGY-CAPSTONE arm, SESSION POSTURE to the AGY-FIRST arm |
| 4 | `clavity-classic/plugin/hooks/agy-seam-inject.sh` | identical (parity) |
| 5 | `scripts/tests/agy-test-audit-reminder.Tests.ps1` | + positive assertion |
| 6 | `scripts/tests/agy-seam-inject.Tests.ps1` | + 2 positive, + 1 negative, + parity assertion |
| 7 | `scripts/tests/agy-after-reminder.Tests.ps1` | + negative assertion, + parity assertion |
| 8 | `clavity-dotnet/plugin/README.md` | + the full section |
| 9 | `clavity-classic/plugin/README.md` | + the full section |
| 10 | `README.md` | + the one-line pointer |
| 11 | `scripts/tests/_partition.md` | both counts re-measured |

**Not touched, deliberately:** `agy-after-reminder.sh` itself (either driver) — see the placement rule;
the ANOMALY-CAPTURE arm of `agy-seam-inject.sh`; every `jq`-missing fallback branch; and
`agy-drive-session-reset.sh`, which exists only in classic and convenes nothing.

## Acceptance criteria

1. The COST clause appears in exactly two directive sites — `agy-test-audit-reminder.sh:68` and
   `agy-seam-inject.sh:77` — in both drivers.
2. The SESSION POSTURE line appears in exactly one site — `agy-seam-inject.sh:75` — in both drivers.
3. `agy-after-reminder.sh` and the ANOMALY-CAPTURE arm are **unchanged**.
4. The **two** touched hook files — which between them carry all three directive sites — remain
   byte-identical across the two drivers. (`agy-test-audit-reminder.sh` carries one site;
   `agy-seam-inject.sh` carries two. Do not conflate sites with files.)
5. Every touched hook still passes its ASCII byte test; no clause text contains a backtick or apostrophe.
6. New assertions pin the presence of each clause and the absence of the clause where the rule excludes
   it. **Positive** assertions are watched RED first; **negative** assertions are proven non-vacuous by a
   mutation that is verified to have landed (they cannot go RED on clean baseline).
7. The full section appears in both plugin READMEs; the pointer line appears in the root README.
8. `agy-seam-inject.Tests.ps1` **and** `agy-after-reminder.Tests.ps1` each gain a cross-driver parity
   assertion matching `agy-test-audit-reminder.Tests.ps1`'s `It 'is byte-identical to the clavity-classic mirror'`. After this change all three mirrored
   hooks are pinned.
9. **Both** counts in `_partition.md` are re-measured by running each recipe — slow (backgrounded) because
   the two touched hooks' suites live there, and fast because `agy-after-reminder.Tests.ps1` gains the
   negative assertion. Neither is computed by addition.
10. No change to `.no-agy` semantics, to any round count, or to any gate's pass condition.

## Panel record — round 1

Solo panel (relentless-adversarial-auditor; seats: Axiom Breaker, Cascade Analyst, Resource Vampire,
Protocol Pedant, Blindspot Auditor, Literal Implementer, Activation Auditor, Mechanism Gamer) plus a live
agy escalation on the same artifact, framed neutrally with the solo findings withheld.

**PANEL VERDICT round 1: RED.** Folded, each verified by measurement first:

| id | finding | verification | fold |
|---|---|---|---|
| AB-1 | Session Posture section contradicted acceptance criteria 1-2 | read the artifact | criteria rewritten |
| CA-1 | `agy-after-reminder` has no marker, so deferral loses the gate | hook has no `.head` read | site excluded; durability added to the placement rule |
| PP-1 | clause contained em-dashes; ASCII enforced by tests | 3 suites confirmed at the cited lines | clause rewritten ASCII |
| PP-2 | two quoting regimes; backtick executes in the double-quoted site | `:36` double, `:68`/`:75`/`:77` single | constraint 6 added; clause rewritten |
| RV-1 | token multiple restated as a quota multiple | not a documented linear relation | claim softened |
| BA-1 | habit 2 implied selective opt-out that does not exist | `.no-agy` is global | habit 2 rewritten |
| LI-1 | insertion whitespace unspecified | — | separator pinned |
| MG-1 | subjective trigger fires unevenly | — | recorded under *Known weaknesses* |
| solo | compaction is itself a summarization cost, unmodelled | — | added to Risks as unquantified |
| solo | "on the roadmap" promised unscheduled work | — | softened to "under consideration" |
| solo | plugin README structures assumed identical | — | implementer told to confirm |

## Panel record — round 2

Seats rotated in: **Dependency Cynic** (environment assumptions: `jq`, bash quoting, Pester, `/compact`,
`/usage`) and **State Corruptor** (marker-file lifecycle), plus both core seats. The live peer returned
`PANEL VERDICT: GREEN - all round-1 defects successfully folded`.

**That GREEN was not banked.** Every section of it restated an item from the do-not-re-raise ledger and
confirmed it back — nothing in it was a surprise, which is this project's recorded signature for a false
GREEN (see `docs/agy-capstone-ledger.md`, where a peer's first-round GREEN was false on two consecutive
capstones). A driver-side hunt was run over surfaces the ledger never mentioned, and found two real
defects the peer missed:

| id | finding | verification | fold |
|---|---|---|---|
| H1 | The doc asserted "nothing enforces cross-driver parity". **False** — `agy-test-audit-reminder.Tests.ps1:149` pins it; `agy-seam-inject` and `agy-after-reminder` do not. The unpinned one is where this change does most of its work. | read all three suites | claim corrected; the parity assertion moved from *deferred* into scope |
| H2 | Acceptance criteria pointed at the **fast** suite count, but both touched suites are in `test-scripts-slow` (`justfile:101`); the only fast one is the suite this design now excludes. | read `justfile:93-101` | criteria retargeted to the slow half, with the backgrounding requirement stated |

**Round 2 disposition: RED** — on driver-side findings, against a peer GREEN.

## Panel record — round 3

Seats rotated in: **Boundary Smuggler** (the mechanism is text injected into an agent's prompt; the hooks
parse stdin JSON) and **Adoption Skeptic** (bespoke — does publishing concrete cost figures make a
prospective user *more* likely to walk away?), plus both core seats. The peer was told plainly that its
round-2 GREEN had not been banked and that a GREEN which walks the ledger is worth nothing; each seat was
required to state **where it looked**. That calibration worked — the round returned four findings, all
verified and folded:

| id | finding | verification | fold |
|---|---|---|---|
| AB-1 | AC 4 claimed "three touched hook pairs"; only **two files** are touched (three *sites* across two *files*), and criterion 9 appeared twice | read the criteria list | AC 4 rewritten to distinguish sites from files; renumbered |
| AB-2 | The mandated negative assertion edits `agy-after-reminder.Tests.ps1`, which is in the **fast** half — contradicting the design's own "fast count unchanged" | `justfile:94` vs the design's table | hook-touched vs suite-touched separated; both counts now re-measured |
| AS-1 | The README opened with a bolded `$249` despite the design mandating tokens-first | read both sections | dollars moved into the API-billing bullet |
| AS-2 | Habit 2 routed "this is too much ceremony" readers straight to the all-or-nothing kill-switch, accelerating abandonment | read habit 2 against *Turning it down* | habit 2 points at habit 1; kill-switch reframed as last resort |

**AS-2 is a worked example of the fold-spawns-its-own-edge rule.** Round 1's BA-1 finding was that habit 2
implied a selective opt-out that does not exist; the fix pointed the reader at *Turning it down* — and
*that* is what created AS-2. One finding, two rounds, and the intermediate fix was the defect.

**Round 3 disposition: RED.**

## Panel record — round 4

Palette exhausted, so two bespoke seats via its escape hatch, both hunting classes no earlier round
covered: **Implementation Rehearsal** (walk the change in execution order; find the step that cannot be
done given the state the previous one leaves) and **Self-Application Auditor** (this repo runs these
disciplines on itself — what breaks when the change lands on its own maintainers?). Core seats re-seated.

Cascade Analyst and Self-Application Auditor both returned "no new findings" **with where-they-looked
stated** — degradation branches under missing `jq`, fail-open behaviour on detached HEAD and empty
history, and the marker-debounce interaction when a maintainer follows habit 1 across two chats.

| id | finding | verification | fold |
|---|---|---|---|
| AB-1 | The exact-text block specified `### Running this economically` (H3) while the placement instruction said `## ` (H2); both target READMEs use H2 for top-level sections | `:188` vs `:246` | exact text corrected to H2 |
| IR-1 | Criterion 6 required every new assertion be "watched RED first", but a **negative** assertion passes on clean baseline and can never go RED — the instruction is unexecutable for exactly the assertions that pin the placement rule | reasoned from the assertion semantics | positive and negative proof procedures separated; negatives proven by a verified mutation |

**AB-1 was introduced by my own D1 fold** — the third fix-spawns-its-own-edge instance in this review
(BA-1 → AS-2, and now D1 → AB-1). That rate is itself the argument for re-running a round after every
fold rather than folding and shipping.

**IR-1 is the most valuable finding of the whole review**, because it would not have failed loudly: an
implementer would have written the negative assertions, seen them pass, and recorded them as verified.
A vacuous test that pins nothing is indistinguishable from a real one until the day it is needed.

**Round 4 disposition: RED.**

## Panel record — round 5

Seats: **Stale-Fold Auditor** (bespoke — hunt only the wreckage of ~20 edits: counts, cross-references,
sentences describing reversed decisions) and **Fresh Reader** (bespoke — read only the Layer 2 README text
cold, as a developer deciding whether to install), plus both core seats.

The peer returned `PANEL VERDICT: GREEN`, and unlike round 2 it stated where each seat looked, with
citations that checked out. **But it was still not banked as-is** — inside its Stale-Fold narrative it
volunteered a fact I had never verified, and measuring that fact falsified a claim in the document.

| id | finding | verification | fold |
|---|---|---|---|
| R5-1 | The doc asserted "across all eight shipped hooks" as a universal measurement. It was only ever run against **dotnet**. Classic ships **nine** — `agy-drive-session-reset.sh` exists only there. | `ls` on both hook directories | count corrected per driver; the extra hook read in full and dispositioned (it clears a session flag, convenes nothing, so the placement rule does not reach it); added the note that the two `hooks.json` differ, so "byte-identical" is a property of the touched scripts, not of the plugin trees |

**Credit where it is due: the peer found this, not me.** It surfaced as a volunteered aside rather than a
numbered finding, which is worth recording — a peer's incidental claims are worth measuring too, not just
the ones it flags.

**Round 5 disposition: RED** (on a peer-volunteered fact confirmed by measurement, against a peer GREEN).

## Panel record — round 6

Seats: **Driver-Asymmetry Auditor** and **Rollback Auditor** (both bespoke; reversibility had never been
examined by any round), plus both core seats. The peer returned GREEN, and this time its volunteered
claims were **checked and correct** — including that the existing parity test is a SHA-256 `Get-FileHash`
comparison at `agy-test-audit-reminder.Tests.ps1`'s `It 'is byte-identical to the clavity-classic mirror'`, verified by reading it. Its citation accuracy
is now good.

One driver-side finding remained:

| id | finding | verification | fold |
|---|---|---|---|
| R6-1 | Every suite roots `$script:Hook` at the **dotnet** copy. So the negative assertion pinning `agy-after-reminder`'s *exclusion* only ever inspects dotnet — a later edit adding the clause to classic's copy alone would fail nothing, silently re-introducing CA-1 through the driver the tests do not look at. | read the suites' `$script:Hook` rooting | a parity assertion is now required for `agy-after-reminder.Tests.ps1` too, even though its hook is not edited; the exact `Get-FileHash` pattern is pinned in the design so the implementer does not have to invent it |

**Round 6 disposition: RED** (one driver-side finding, against a peer GREEN whose own claims all held).

## Panel record — round 7

Seats: **Regression Archaeologist** (does this re-open something the repo already fixed? it audited the
hooks' own comment blocks, which encode past defects) and **Success-Criterion Auditor** (how would anyone
know this worked?), plus both core seats. Both new seats returned no new findings with where-they-looked
stated; the Success-Criterion seat confirmed that retention is structurally unmeasurable for a zero-
telemetry local plugin, while in-session adherence *is* observable by the same transcript-parsing method
used in *Evidence* — and that the design already discloses its non-observable parts rather than claiming
them.

| id | finding | verification | fold |
|---|---|---|---|
| R7-1 | The round-6 fold updated *Testing* and criterion 8 but left three other sections — *Cross-driver parity*, *Deferred work* item 4, and the *Risks* row — still asserting `agy-after-reminder` is unpinned and deferred, directly contradicting them | read all four sections | all three corrected; a line-number citation my own earlier fold had missed was corrected at the same time |

**Round 7 disposition: RED.**

## Panel record — rounds 8 and 9: CONVERGED

**Round 8.** Seats: **Fold Verification Auditor** (walk all 27 ledger items and confirm each fix landed in
*every* section stating that fact) and **Cold-Implementer Completeness** (given this document alone, what
would you have to invent?), plus both core seats. The peer returned GREEN having cross-checked each ledger
item across sections. Two driver-side additions followed — a consolidated **file manifest** (the change
touches ~11 files, previously derivable only by assembling them from five sections) and a paragraph
recording that the hook-outranks-documentation premise was **observed** this session rather than reasoned.

One correction to the peer's round-8 report: it claimed tests are cited "strictly by test name". A sweep
found test line citations still present as *evidence* references, which the standing caution above already
covers. The document is correct; the peer's summary overstated it.

**Round 9 (confirming).** Run because this review's own rule is *never fold and ship* — the manifest was
new content assembled from scattered facts, which is exactly the operation that failed five times here.
Focus seat **Manifest Cross-Check** verified all eleven rows and the not-touched list against their source
sections individually. GREEN.

**Disposition: the panel is CONVERGED at round 9.** Findings per round ran **11, 2, 4, 2, 1, 1, 1, 0, 0** —
two consecutive clean rounds, the second of which specifically covered the final folds. Thirty findings
folded in total, every one verified by measurement before folding.

Of those thirty, **eleven came from the driver rather than the peer**, including two that were false claims
in this document and one — the negative assertions that could never go RED — that would not have failed
loudly. Two peer GREENs were rejected on driver-side findings before the panel genuinely converged.

## The pattern this review kept hitting, and what to do about it

**Five of the folds in this review created the next defect.** BA-1's fix created AS-2. D1's fix created
round-4's AB-1. The H1 fold left a stale Risks row. The round-6 fold left three stale sections. A
find-and-replace intended to remove line citations missed one.

The shape is always the same: a fold updates the section the finding pointed at, and leaves every *other*
section that restated the same fact untouched. It is not carelessness about the finding — it is that a
document repeats its facts across sections, and a fix aimed at one instance does not know about the rest.

**Two rules follow, and they apply to executing this design as much as to reviewing it:**

1. **After folding anything, grep the whole document for the fact you just changed** — not the wording,
   the *fact*. Every count, every "X is pinned / not pinned", every scope boundary.
2. **Never fold and ship.** Re-run a round after every fold. Five defects here were invisible at the
   moment of the fix and only surfaced on the next pass.

## A standing caution on this document's own citations

This design cites test locations **by test name**, not by line number, wherever the implementer is sent
somewhere to copy from. That is deliberate: executing this design adds `It` blocks to the very suites it
cites, so any line number pinned here can drift as the work is done — the document would misdirect its own
implementer. This repo has already been bitten once by a pinned line that moved.

Hook citations (`agy-test-audit-reminder.sh:68`, `agy-seam-inject.sh:75/77`, `agy-after-reminder.sh:36`)
are stable by contrast, because the change appends **within** an existing single-line string and adds no
lines. Re-locate anything here by content if it does not match.
