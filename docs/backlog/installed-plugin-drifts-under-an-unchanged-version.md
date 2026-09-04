# Backlog stub — the installed plugin silently drifts from source under an UNCHANGED version

**Status:** 🔴 **OPEN.** Verified by measurement, re-confirmed 2026-08-24.
**Raised:** 2026-08-19. Promoted from `.clavity/local-anomalies.md` at the 2026-08-25 triage.

## The defect

The INSTALLED `agy-autotrain` plugin ships a TRUNCATED copy of `agy-curate/SKILL.md` while reporting the
same `"version"` as source, so a drain executes roughly half the documented procedure and **nothing can
detect it.** MEASURED:

| artifact | installed | repo source |
|---|---|---|
| `skills/agy-curate/SKILL.md` | 276 lines | 543 lines (49% absent) |
| `docs/fix-the-tool-backlog/_template.md` | 1.5K | 2.3K |
| fix-the-tool backlog entries | 11 files | 17 tracked |
| `plugin/knowledge` core.md | 3515 B | 4750 B |
| `plugin.json` `"version"` | **0.4.0** | **0.4.0** |

Repo source last moved at `fd380fe` (2026-08-16). `clavity-ls.exe` is dated 2026-08-09, so the live
`agy_ask` predates the `discipline`/`artifactPath` arguments.

> ⚠ **Both sides of that table drift, and the RATIO is the claim.** The repo figure was recorded as 518
> and was 543 by 2026-08-26 - stale within days, and stale in two places at once (the other copy lived in
> `docs/coverage-debt.md`). Re-measure rather than trust these: `wc -l` on each side, paths as listed.
> What this entry asserts is that roughly HALF the skill is missing from the installed copy under an
> identical version string. That proportion has not moved, and it is what makes the entry live.

## Why it matters

**The drain reads the INSTALLED copy.** The canonical procedure an agent actually follows is silently
older than the reviewed one, and an identical version string on both sides means neither the installer
nor any check can see the drift. Every skill-level fix made in this repo — including the path anchoring
fixed at the same triage — is invisible until someone reinstalls by hand.

## The fix direction

Either stamp a content hash beside the version and check it at load, or make the installer refuse to
install over a differing tree without a version bump. A version string that does not change when content
changes is not a version.

## Related

`docs/coverage-debt.md` accepted boundary **F** ("Repo-vs-install drift is undetected") records the
*coverage* half of this; this stub is the defect half.


## 2026-08-31 - the drift CAUSED A WRONG ACTION, not just a risk

Until now this item recorded a truncated `agy-curate/SKILL.md` and argued the *risk* that a discipline
would execute half its procedure. Today it happened, and it is worth recording because the failure was
silent and the agent had no way to notice from inside the run.

`agy-test-audit/SKILL.md`, measured during a real AGY-TEST-AUDIT:

| artifact | installed | repo source |
|---|---|---|
| `agy-test-audit/SKILL.md` | **159 lines** | **332 lines** |

The two copies **contradict each other on a load-bearing contract**, and the installed copy carries the
side that was deliberately retired:

- installed `:152`, `:157` - "the audited sha ... not ambient HEAD"
- repo `:312` - "**ambient `HEAD`**, exactly as the command above writes it"

The repo copy carries a note at `:315` recording that the installed wording was removed on **2026-08-26**
precisely because it CONTRADICTED the `git rev-parse HEAD` command four lines above it, and that the
contradiction "survived nineteen review rounds" because each half read as correct alone.

**Consequence, and it is the exact one the repo note predicts.** The audit followed the installed copy and
wrote the AUDITED sha as its debounce marker. Under the current contract that marker never equals `HEAD`,
so the reminder hook "keeps nudging forever after a completed audit". The audit had even *reported* the
re-nudge to the owner as intended behaviour, citing the installed skill. It was corrected only because an
unrelated ROADMAP read (§23) quoted the repo line and the two did not match.

**What this adds to the case for fixing this item:** the existing entry showed drift produces INCOMPLETE
work. This shows it produces CONFIDENTLY WRONG work that passes its own self-checks, because the agent
verifies against the text it was given. No amount of care inside a run detects a stale instruction file.

## Second confirmed instance — `agy-learn/SKILL.md`, found 2026-09-03, recorded at the 2026-09-04 triage

The same drift class hit a second skill in the same plugin, with a sharper consequence: the INSTALLED
`agy-learn` is **pre-14g**, so it directs every capture to a path that 14g declared DEAD.

**MEASURED 2026-09-04 by line count on all three copies:**

| copy | lines |
|---|---|
| `AppData/Local/Programs/agy-autotrain/plugins/agy-autotrain/skills/agy-learn/SKILL.md` | 69 |
| `.claude/plugins/cache/clavity-agy-autotrain/agy-autotrain/0.4.0/skills/agy-learn/SKILL.md` | 69 |
| `agy-autotrain/skills/agy-learn/SKILL.md` (repo) | 143 |

Both installed copies' step 3 reads *"Append to `../../knowledge/agy-observations.md`"*; the repo copy
names `<USERPROFILE|HOME>/.clavity/agy-observations.md`. **An agent following the installed skill writes
captures where no drain ever reads them.** This is not hypothetical — it happened, and the write had to be
reverted (`42cfa84`).

This strengthens the original finding rather than duplicating it: the first instance degraded a
*procedure* (half a drain), this one silently *misroutes durable data* while reporting success.
