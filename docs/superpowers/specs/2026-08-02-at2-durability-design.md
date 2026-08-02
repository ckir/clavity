# AT-2 — Durability for the machine-wide learning-loop artifacts

**Status:** design, owner-approved 2026-08-02 · **Supersedes:** the options block in `agy-autotrain/ROADMAP.md` AT-2
**Provenance:** AT-2 (opened 2026-07-30) · negotiated with the agy peer over three rounds
(`.clavity/seams/at2-durability-fork.md`, `at2-negotiation-r2.md`, `at2-negotiation-r3.md`)

## Goal

Give the two machine-wide artifacts of the agy learning loop a recovery path against **data loss**, without
grafting a lifecycle subsystem onto a plugin that is deliberately being thinned.

## The problem, measured

Both artifacts are machine-wide, live outside every repository boundary, and have no history.

| Artifact | Path | State (2026-08-02) |
|---|---|---|
| Inbox | `%LOCALAPPDATA%\Programs\agy-autotrain\plugins\agy-autotrain\knowledge\agy-observations.md` | 9.8 KB, 8 pending |
| Inbox, peak | same file, pre-drain | **67,231 B / 79 entries** |
| GROWTH | `%USERPROFILE%\.clavity\golden-header.growth.md` | 7,984 B + `.sha256` sidecar |

**Neither directory is inside any git repo. Neither is `~/.claude`.** There is no off-machine copy, no
history, and no way to see what an entry said before something rewrote it.

**Three single-slot backups exist, and no code writes any of them:**
`agy-observations.md.preinstall-backup` (22,975 B, dated Jul 20 — written by the installer),
`agy-observations.md.pre-drain-2026-08-01` (67,231 B), and
`golden-header.growth.md.corrupt-backup-2026-07-21`. The last two were made by hand. **The instinct keeps
firing and nothing institutionalises it** — that is the clearest evidence the gap is real rather than
theoretical.

**The two artifacts cannot reconstruct each other.** `agy-curate` empties the inbox when it drains, so
after a drain GROWTH holds distilled knowledge that no longer exists in the inbox. GROWTH is also not
mechanically regenerable even from a preserved inbox: `agy-curate/SKILL.md:173-180` folds legacy
flat-header wisdom that was never in the inbox, and `:195-203` requires live probe execution plus an
explicit human approval gate. Recreating GROWTH is a session, not a command.

**What already protects them, which this design does not rebuild.** `agy-autotrain/installer/agy-autotrain.iss`
seeds the inbox with `onlyifdoesntexist` so an upgrade cannot overwrite accumulated observations, and
`GoldenHeader.Commit()` already writes header and sidecar via atomic tmp→rename. Those cover the *install*
and *torn-write* vectors. Everything else is uncovered.

## Architecture

**Two mechanical snapshots, each at the point of mutation.** Neither artifact moves; nothing learns
anything about the other's storage layout.

| Artifact | Snapshot site | Why there |
|---|---|---|
| `golden-header.growth.md` | `GoldenHeader.Commit()`, immediately before the atomic replace | Compiled code, always runs; the driver already owns this file and this class of machinery |
| `agy-observations.md` | A `PreToolUse` hook matching `Skill`, in **agy-autotrain's own** `hooks.json` | Compiled trigger, always runs; the plugin that owns the inbox owns the guard; zero driver coupling |

Both use **N=5 timestamped slots, FIFO prune**: `<file>.YYYYMMDD-HHMMSS.bak`.

### Why the inbox snapshot is a hook and not skill prose

The first proposal put it in `agy-curate/SKILL.md`. That would have left the artifact with **no version
control and the larger corpus** protected by the weaker of the two mechanisms — prose runs only if the
agent complies. This repo has twice learned that instructions alone are not self-enforcing: the anomaly
capture clause needed a PostToolUse hook, and the dispatch file allow-list needed a gate.

A hook is available and proven here:

- `agy-autotrain/hooks/hooks.json` — the plugin **already ships and installs its own hooks** (currently
  `SessionStart` and `PreCompact` only).
- `clavity-dotnet/plugin/hooks/hooks.json` registers `"matcher": "Skill"` under `PreToolUse`, and
  `agy-seam-inject.sh` switches on which skill is being invoked. **A hook firing on one specific skill is
  already proven in this repo.**
- `agy-autotrain/installer/agy-autotrain.iss:98-102` registers the plugin with Claude Code, so its hooks
  are live on the installed path.

### Why the driver binary does not own the inbox snapshot

The architectural guardrail (`agy-autotrain/ROADMAP.md:11-16`) says capabilities migrate OUT to the
drivers, not IN — which argues for pushing durability down into the binary. That is right for GROWTH, which
the driver already owns, and wrong for the inbox: teaching `clavity-ls` the path
`{app}\plugins\agy-autotrain\knowledge\agy-observations.md` couples the driver to agy-autotrain's internal
storage layout. The driver is deliberately unaware of the plugin; it reads a well-known header path and
no-ops cleanly when absent.

## Components

### 1. Inbox snapshot hook — `agy-autotrain/hooks/agy-inbox-snapshot.sh`

Registered under `PreToolUse` with `"matcher": "Skill"` in `agy-autotrain/hooks/hooks.json`.

**Skill matching MUST be field-bounded, not a bare substring.** `agy-seam-inject.sh:27-28` documents why:
a bare substring can false-match when another skill merely *mentions* the name in its arguments. Match the
JSON field:

```bash
printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*agy-curate"' || exit 0
```

**Three stateless invariants gate the rotation.** Their shared purpose is that the snapshot ring must never
destroy its own history:

```bash
# 1. STRUCTURAL: header and section must both be present
grep -q '^# agy observations inbox' "$OBS" && grep -q '^## Pending' "$OBS" || exit 0

# 2. CONTENT: at least one parseable bullet
grep -Eq '^- \[[a-z-]+\]' "$OBS" || exit 0   # [a-z-] NOT [a-z]: see note below

# 3. DEDUP: never rotate when content is identical to the newest snapshot
latest=$(ls -1t "${OBS}".*.bak 2>/dev/null | head -n 1)
[ -n "$latest" ] && cmp -s "$OBS" "$latest" && exit 0
```

**The character class in invariant 2 MUST be `[a-z-]`, not `[a-z]`.** The valid entry classes are
`assumption | heuristic | anti-pattern` (`agy-learn/SKILL.md:53`), and **`[a-z]+` does not match the hyphen
in `anti-pattern`** — MEASURED against a real entry line. This is not an exotic edge case: **42 of the 79
entries in the last pre-drain corpus were `[anti-pattern]`**, the single most common class. With `[a-z]`,
an anti-pattern-only inbox is read as malformed and gets **no snapshot at all**, and a mixed inbox passes
the check only by accident because some other class happens to be present. Caught by the panel; the test
suite below pins it.

Invariants 1 and 2 stop a blank or structurally broken file from rotating five good backups out of the
ring. **Invariant 3 is the one that matters most in practice:** without it, an aborted or re-run
`agy-curate` burns a slot each time, so five retries silently evict the entire history. It also bounds the
rotten-snapshot problem — because identical content never rotates, **persistent corruption occupies one
slot, not five**, so the ring keeps four earlier distinct states rather than filling with copies of the
same bad file.

### The hook is fail-open, and that is a real limit — not a guarantee

Any missing tool, unreadable file, or failed check exits 0 and never blocks the skill, mirroring
`agy-curate-nudge.sh`'s posture. **State the consequence honestly: a hook is reliably INVOKED, not reliably
EFFECTIVE.** On any failure the design degrades to the retained prose step — the same non-self-enforcing
mechanism this design rejected as primary. That is an accepted trade (a durability guard must never block
the user's work), but it means "mechanical" describes the trigger, not the outcome.

**Snapshot failure MUST NOT be silent.** A disk-full, permission-denied or read-only directory is precisely
when the operator needs to know a drain is about to run unprotected. On any failed copy the hook emits a
one-line warning to stderr naming the reason, then still exits 0.

### 2. GROWTH snapshot — `GoldenHeader.Commit()`

Before the existing header tmp→rename, snapshot **both files as one slot**:

```
golden-header.growth.md         -> golden-header.growth.md.<stamp>.bak
golden-header.growth.md.sha256  -> golden-header.growth.md.<stamp>.bak.sha256
```

**Snapshotting the header without its sidecar produces an unrestorable backup.** `TryReadFile` compares the
live sidecar against the file it reads; restoring a header while the sidecar still holds the *previous*
hash yields a mismatch, and the read side **skips the region and returns null** — so the restored header is
silently dropped from every ask. The two files are one unit and must rotate together.

Concrete invariants for this half (not "in spirit"):

- Skip when `golden-header.growth.md` is absent.
- Skip when it is byte-identical to the newest `.bak` (the same dedup rule as invariant 3).
- Copy the sidecar too when it exists; if it does not, snapshot the header alone and note it.
- Prune to the newest **5** slots, removing a slot's `.bak` and `.bak.sha256` together.

Retention lives in one named constant beside `MaxBytes` in `GoldenHeader` — do not inline the literal 5.

Ordering is otherwise unchanged: header tmp→rename, then sidecar tmp→rename, per the existing comment.

### 3. Transactional ordering in `agy-curate`

`agy-curate/SKILL.md` must reset `## Pending` **only after `curate-commit` returns exit 0**. Today a crash
between compiling GROWTH and publishing it could leave an emptied inbox and no new GROWTH. The prose step
that snapshots the inbox is **retained as an idempotent fallback** for paths where the hook does not run —
made a no-op by invariant 3 when the hook already snapshotted.

## What this design does NOT cover

**This is durability against LOSS. It is not integrity against silent CORRUPTION.** The two were conflated
in the original AT-2 text and in the first round of design; separating them is a deliberate outcome.

**It would NOT have prevented the 13-day incident.** `golden-header.growth.md` sat mojibake-corrupted for 13
days while its `.sha256` sidecar MATCHED, because the content was wrong on arrival. Had this ring been
running throughout, every slot would have filled with corrupt content and rotated out the last good copy.
Snapshots preserve state; they do not evaluate correctness.

**Inbox integrity is DEFERRED, and the gap is named here.** `agy-observations.md` has zero mechanical
validation and no sidecar — worse than GROWTH, which gets strict throwing UTF-8 decode, a 16 KB cap, and
the mojibake tripwire. Deferring is justified because general inbox integrity means validating the
Structured Abstraction Schema, the two-axis tags, and the no-project-nouns rule — an authoring and linting
concern, not storage safety, and enforcing it at the storage layer would add exactly the stateful machinery
the guardrail forbids.

**A stateful entry-count check was considered and rejected.** Persisting the count from
`agy-curate-nudge.sh` and warning on an unexplained drop cannot distinguish a legitimate drain from
accidental loss without multi-process state across `agy-learn`, `agy-curate` and the hooks. Drift from any
crash or manual edit produces false alarms — and a guard that cries wolf gets ignored, which is how the
consult guard failed in this repo.

**Accepted residual risk, stated plainly.** A partial deletion that leaves the header and at least one
bullet intact WILL be snapshotted. If five full, distinct drains then complete without anyone noticing,
the pre-loss copy is gone. This is accepted because the guard is stateless and fail-open (no false
positives), because `agy-curate` inspects every pending entry on every drain (`SKILL.md:27`), and because
the measured drain cadence is slow: the nudge fires at 8 entries but the last real drain happened at **79**,
so five slots span many months of use.

**Known bypasses**, all uncovered by the hook and covered only by the retained prose step:

- A drain driven from the dev repo via `just drain-knowledge` — outside the Claude Code hook runtime.
- Any direct edit of the inbox with `Edit`/`Write` or a text editor — no `Skill` call, no `PreToolUse`.
- **An agent that READS `agy-curate/SKILL.md` directly instead of invoking it through the `Skill` tool.**
  The hook keys on the tool call, so following the skill's instructions without invoking the skill fires
  nothing.
- Any failure inside the hook itself (see fail-open above).

**Uninstall does not purge the rings.** `.bak` files in both directories survive removal of the plugin.
That is arguably correct for a durability artifact, but it is unstated behaviour today and the uninstaller's
existing inbox handling should be extended to at least mention them.

## Recovery

A backup nobody can restore from is theatre. Both procedures are one command.

**GROWTH — restore both files, always:**
```powershell
Get-ChildItem "$HOME\.clavity\golden-header.growth.md.*.bak" | Sort-Object LastWriteTime -Descending
Copy-Item "$HOME\.clavity\golden-header.growth.md.<stamp>.bak"        "$HOME\.clavity\golden-header.growth.md"
Copy-Item "$HOME\.clavity\golden-header.growth.md.<stamp>.bak.sha256" "$HOME\.clavity\golden-header.growth.md.sha256"
```

Restoring the header alone leaves the previous sidecar in place, the hashes mismatch, and the read side
**silently drops the region** — a restore that looks successful and quietly does nothing.

If a sidecar snapshot is missing and the hash must be regenerated instead, **do NOT pipe the file into
`curate-commit`.** A PowerShell pipe re-encodes the stream through the console code page — the exact
mechanism behind the 13-day corruption this spec exists to survive, and `agy-curate/SKILL.md` forbids it in
as many words. Use the raw-byte stdin sequence documented there (`ProcessStartInfo` +
`StandardInput.BaseStream.Write`).

**Inbox:**
```powershell
$k = "$env:LOCALAPPDATA\Programs\agy-autotrain\plugins\agy-autotrain\knowledge"
Get-ChildItem "$k\agy-observations.md.*.bak" | Sort-Object LastWriteTime -Descending
Copy-Item "$k\agy-observations.md.<stamp>.bak" "$k\agy-observations.md"
```

**A restored inbox is a PRE-drain inbox, and re-running `agy-curate` on it will double-promote.** Its
entries were already distilled into GROWTH by the drain being undone, so a straight restore followed by a
normal drain duplicates rules in the header injected into every ask. **Reconcile before the next drain:**
compare the restored `## Pending` against the current GROWTH region and delete entries already represented
there, keeping only what the drain had not yet folded in. This step is mandatory, not advisory.

**Two pre-existing hand-made backups sit OUTSIDE the ring** — `agy-observations.md.preinstall-backup` and
`agy-observations.md.pre-drain-2026-08-01`. MEASURED: the `*.bak` glob matches neither, so the ring will
never prune them. That is deliberate — they are historical evidence and should survive — but a restorer
should know they exist and are not part of the rotation.

Both procedures belong in the agy-autotrain README so they exist outside this spec.

## Testing

- **Hook, Pester** (`scripts/tests/agy-inbox-snapshot.Tests.ps1`, driven via `Invoke-BashHook`): fires for
  `agy-curate` and not for another skill; does NOT fire on a skill whose *arguments* merely mention
  `agy-curate` (the field-bounded-match regression); refuses to rotate on an empty file, on a file missing
  `## Pending`, and on a file with no bullets; does not rotate when content is identical to the newest
  snapshot; prunes to exactly 5; exits 0 on every failure path; **emits a warning when the copy itself
  fails** (simulate with a read-only target).
- **The `[anti-pattern]` regression is a REQUIRED test, not an optional one.** An inbox whose entries are
  ALL `- [anti-pattern] …` must still be snapshotted. This is the defect the panel found: `[a-z]+` silently
  skipped the most common class in the corpus, and only a test naming the hyphenated class distinguishes
  the fixed regex from the broken one.
- **GROWTH snapshot, xUnit** (`CliVerbsTests.cs`): a snapshot appears before the replace; **the `.sha256`
  sidecar is captured in the same slot**, and a restore of that slot round-trips through `TryReadFile`
  without a mismatch warning; the ring prunes to 5, removing `.bak` and `.bak.sha256` together; an
  identical re-commit does not consume a slot; the two pre-existing round-trip tests at `:31` and `:44`
  must pass **unmodified** — they pin `curate-commit` as a faithful byte transport.
- **Mutation-check both**, per this repo's standing practice: each new assertion must be observed failing
  against the pre-change code, and the mutation must be proven to have landed before its result is read.

## Non-goals

- No relocation of either artifact. Moving the inbox breaks the `../../knowledge/agy-observations.md`
  relative paths in both skills, collides with `onlyifdoesntexist` seeding on upgrade, and desynchronises
  the uninstaller's purge target.
- No git repository. `git init` inside a plugin directory is the lifecycle grafting the guardrail forbids.
- No restore command, status monitor, or retention-policy UI. Recovery is a documented `Copy-Item`.
- No off-machine or cloud copy.
- No change to what `agy-learn` or `agy-curate` capture or how they triage.
