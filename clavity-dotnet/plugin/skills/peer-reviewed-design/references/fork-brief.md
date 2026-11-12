# The fork brief

Write the brief to `.clavity/seams/<topic>-first.md` (the word `first` in the file name is what the
clavity recovery hook recognises) and give the peer a scratch area `.clavity/scratch/<topic>/` with a
named reply file. Prepare both through the clavity marker writer so the `.clavity/` shield is
asserted before anything is written:

```bash
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "seams/<topic>-first.md"; then
  echo "peer-reviewed-design: ABORTING - could not prepare a shielded .clavity/ directory for seams/<topic>-first.md." >&2
  exit 1
fi
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "scratch/<topic>/notes.md"; then
  echo "peer-reviewed-design: ABORTING - could not prepare a shielded .clavity/ directory for scratch/<topic>/notes.md." >&2
  exit 1
fi
```

If either call exits non-zero, the marker writer is missing or refused the path, which means the peer
channel is not available on this machine: halt and ask the owner, exactly as for an unreachable peer. Do
not create `.clavity/` by hand and continue; the shield the writer asserts is what keeps the peer's writes
out of the repository.

## Template

```markdown
# agy-first seam, round N: <the fork in one line>

Date. Context: what artifacts exist, what is committed, what is built (usually nothing).

## What the owner has said
Verbatim quotes. If the owner has not answered a question yet, say "UNKNOWN; reason under each
plausible reading" rather than guessing.

## Fixed facts (owner-ratified, do not re-open)
One line per prior ruling, with where it lives.

## Do-not-re-raise ledger
Every finding already folded, rejected or discarded, with its disposition. Pointers to "the ledger"
do not count; list them.

## The fork
Two to five options, unranked, each with a line on its real tradeoff. End with "Option N: something
none of these name (the peer may propose one)".

## The driver's current recommendation (to be challenged)
Which option and why, then: "Where I think my own recommendation is weakest: ...". This is the
sentence the peer argues against; without it, the peer argues against nothing.

## Success criterion
A sentence the owner could check twelve months later.

## Open questions for the peer (answer in your own words)
1. DISAGREE WITH MY GUESS. I think the weakness is X. Where do YOU think it is; say plainly if I am wrong.
2. A DISPOSITION I HAVE NOT NAMED. Is there an option none of the above describes? Name it concretely.
3. REJECT THE FRAME. Is this even the decision to make now? Name the decision that constrains the most.
4. PERMIT IGNORANCE. What cannot be judged without data the owner lacks? Name the data.

Severity floor: naming and wording are below the floor. "No new findings" and "cannot determine" are
correct, welcome answers.

End of round-N artifact <topic>-first, questions one to four above.
```

The last line is deliberate: it is the line the peer must echo, and it carries no inline code so the
peer cannot drop backticks and fail the echo check (the driver's on clavity-dotnet, your own eye on
clavity-classic).

## The payload

Send the path, not the text. The payload carries, in this order:

1. The closed-rounds preamble: "Rounds 1 to N-1 are CLOSED and owner-ratified; do not re-open."
2. The review-only banner with writing, redirection and scratch dumps enumerated as separate
   forbidden acts, the home directory named as off-limits, and a sanctioned alternative for anything
   the peer needs to run ("do it under `${TMPDIR:-/tmp}/agy-<topic>/`, no dependency installs or
   builds, or name the command and I will run it"). A prohibition with no legal path invites a
   workaround.
3. Discipline name (on clavity-dotnet also passed as the `discipline` argument, see "Transport"),
   artifact path, scratch path, reply file path.
4. The goal and success criterion restated in one line, with full method latitude.
5. The panel: named seats, the rule that a seat with nothing new writes exactly "no new findings",
   the instruction to name dropped seats.
6. Divergence vectors.
7. The four open questions, by reference to the artifact, with "mark every external claim
   [CLAIM] with the date of the newest fact you rely on; any number you propose is [PROPOSED,
   UNMEASURED]".
8. The reply contract, verbatim:

> Keep your chat reply to at most 6000 characters. Write the complete analysis to the reply file
> named in this brief - writing that one file is the only exception to "do not create any file" -
> and let the chat reply carry only a one-line summary per seat, then the report blocks this contract
> requires, then the echo, then the terminal token. If the required blocks cannot fit in 6000
> characters, shorten each detail and drop the seat lines first: the cap never displaces a required
> block, the echo or the terminal token.

> Immediately before your terminal verdict, quote verbatim the last line of `<artifact>` that carries
> at least 8 letters or digits. Quote it exactly.

> Put nothing after the terminal token. It must be the LAST thing in your reply. Every REQUIRED block
> comes immediately BEFORE it, in this order: your report, then any [VERIFIED: ...] block, then any
> closing disclosures, then the echo line, then the token.

9. The terminal token. There are two different tokens and they are easy to confuse:
   - **The peer's last line.** For a fork consult or an agreement round (discipline `agy-first`), a
     last line starting with `VERDICT:` followed by a few words (`VERDICT: RECOMMEND B`,
     `VERDICT: AGREE 7, AMEND 2, DISSENT 1`). For a panel round (discipline
     `adversarial-panel-review`), a last line starting with `PANEL VERDICT:`. On clavity-dotnet the
     language-server driver checks the last line's prefix against the discipline name you passed; any other
     wording trips a false "truncated" flag on a complete reply. On clavity-classic no automatic check runs,
     so check the prefix by eye.
   - **Your own closing line to the owner**, after you have verified and folded: one bracketed
     ASCII token, `[VERDICT: ALIGNED]`, `[VERDICT: REJECTED - <measured reason>]`,
     `[VERDICT: NEGOTIATE - <reason>]`, or `[VERDICT: SKIPPED-UNREACHABLE]`. Emit it only when a
     consult ran or was waived by the owner. While you are halted waiting for the owner to restore
     the channel, there is no verdict; say "awaiting the owner" instead.

## Transport

Use the channel the installed clavity plugin provides.

- **clavity-dotnet:** check idle with `agy_status`, then call `agy_ask` with `discipline` and
  `artifactPath` set, so the language-server driver runs its own completeness checks on the reply (a
  missing echo or terminal token is flagged). A flagged reply is incomplete, not empty: never read it as
  "no findings". Recover in this order: the `ReplyFile` the notice names (its last 200 lines first), then
  the peer's own reply file, then re-ask at most once, then halt and ask the owner. The `clavity:agy-first`
  skill documents the flagged notices in full.
- **clavity-classic:** `clavity ask "<payload>" --review-only` is the front door. No `discipline` or
  `artifactPath` parameter exists there, so no automatic check runs: demand the echo and the terminal
  line in the payload and verify both by eye. A reply missing either is incomplete, not empty: read the
  reply file the brief named (the reply contract makes the peer write its whole analysis there), then
  re-ask at most once, asking for that file if it is absent, then halt and ask the owner.

Never use the delegation bridge for a consult: it gates on committed changes and fails by construction
for review-only work.

## After the reply

1. Diff `git status --short` against the snapshot. Unchanged is the only acceptable result.
2. Read the reply file in full, not only the chat summary; the chat summary drops detail.
3. Verify every claim that bears on the decision (see the verification playbook). Note where a
   citation is invented even if the conclusion stands.
4. Write the discipline marker through the marker writer so the auto-fire hook does not re-inject
   the consult for the same commit (skip it when `git rev-parse HEAD` cannot resolve):

   ```bash
   bash "<BASE>/../../hooks/agy-mark.sh" head "agy-first" "$(git rev-parse HEAD)"
   ```
5. Update the execution index.
6. Present to the owner: what the peer said, what you measured, where it was wrong, your read, the
   question, the verdict token.
