---
name: peer-reviewed-design
description: Drive a design phase from a vague idea to approved, committed artifacts (design doc, implementation plan, release roadmap) by splitting it into decision forks, consulting an independent adversarial peer on each fork, measuring every claim before folding it, and letting the owner rule. Use this whenever a new product, system, service or subproject is being designed from scratch, whenever the user asks to brainstorm a roadmap, compare options, evaluate a licence or business model, "consult agy", "get a common agreed recommendation", or review their decisions, and whenever a real design, scope, sequencing or approach fork appears mid-project, even if the user does not say "design" or "review".
---

# Peer-reviewed design

A design phase produces decisions, and decisions made by one model in one context are the least
checked thing in a project. This skill makes every material decision pass through three hands:
the driver (you), an independent peer that has not seen your reasoning, and the owner, who rules.
Between the first two sits measurement: a claim is folded only after the file, the registry, the
database or the licence text has been read.

Announce at start: "Using peer-reviewed-design to run this design phase."

## The shape of the work

```
idea --> fork 1 --> fork 2 --> ... --> design doc --> plan --> roadmap --> (execution, out of scope)
          |           |                    |            |          |
       peer+measure  peer+measure     builder check   panel      panel
       owner rules   owner rules      + panel rounds  rounds     rounds
```

Every arrow writes to the execution index (section 8) the moment it lands, because the session
can die at any time and the next one must resume from the index alone.

## 1. Find the forks before the answers

Before anything else, look for an existing execution index and resume from it (section 8 says where
it lives and what to do when there are several); only a project with none starts fresh.
Then take the brainstorming posture (the brainstorming skill, when available): understand what the owner wants and why before proposing how.
Read whatever exists (repo, docs, earlier conversation) first; never ask what the project already
answers. Then name the forks, in dependency order. A fork is a decision whose different answers lead
to materially different work. Typical first forks for a product: who the first adopter is, what the
core mechanism is, how state is stored, how it makes money, under what licence. Sequencing is itself
a fork when the order of releases changes what each contains.

One fork at a time. Resolve it, record the ruling, then open the next. Do not batch forks into one
consult; the peer answers the easiest and stops.

## 2. The fork brief

Write each fork to a file the peer reads itself, never a pasted summary. Use the template in
`references/fork-brief.md`. The parts that make a brief work, and why:

- **Goal and a checkable success criterion.** Without one, the peer optimises for sounding
  thorough. With one, it can say "option C fails the criterion because".
- **Options, unranked, none marked as yours.** A peer treats anything the brief states as a premise.
  Mark your own recommendation separately as the thing to challenge, and say where you think it is
  weakest, so the peer argues against something concrete rather than agreeing with your frame.
- **Fixed facts and a do-not-re-raise ledger.** Rulings already made are listed as closed. Re-raising
  costs a round; the ledger stops it.
- **Four open questions, never yes/no:** disagree with my guess; a disposition I have not named;
  reject the frame (is this even the decision to make now?); permit ignorance (say plainly what you
  cannot judge and what data would settle it). These four shapes produce findings; checkboxes
  produce agreement.
- **Seated panel, rotated each round.** Name the lenses (contradictions, failure cascades, state
  corruption, literal implementer, blind spots, mechanism gaming, plus bespoke lenses the fork
  needs, such as a licensing lawyer or a go-to-market skeptic). Name the seats you dropped and why.
- **Divergence vectors:** invert the core constraint; the one-month and the two-year version; the
  dumbest baseline that still works; a cross-domain analogy. These force breadth without "be
  creative", which produces novelty theatre.
- **Reply contract:** the chat reply capped, the full analysis in a named scratch file, the last
  meaningful line of the brief echoed before a terminal line that starts with `VERDICT:`. The echo
  proves the peer reached the end of the artifact; the cap prevents stalls.

Send it review-only, with the forbidden actions enumerated (no edits, no file creation outside the
one reply file, no mutating commands, nothing under the home directory) and a sanctioned place to
write. Snapshot `git status --short` before and diff after; a changed tree is a breach, surfaced to
the owner, never silently reverted.

## 3. The peer

The peer is the live agy session reached through the clavity plugin. On clavity-dotnet that is the
`agy_status` idle check followed by `agy_ask`, and the language-server driver runs its own completeness
checks on the reply and flags one that does not end in the expected token. On clavity-classic there are no
such tools or parameters: the front door is `clavity ask --review-only`, and you demand the echo and the
terminal line and verify both by eye (`references/fork-brief.md`, "Transport"). If agy is unreachable, modal-stuck, the plugin or its
marker writer is not installed, or the channel itself is what is broken, **halt and ask the owner**
to restore the channel or waive the consult for this one fork. There is no self-exemption: not "it
looks busy", not "the fix is small", not "I'll use a subagent instead". Only the owner waives.
Record the halt in the execution index as the resume point.

What to expect from the peer, learned the hard way:

- It states false claims with the same confidence as true ones, and its citations can be invented
  even when its conclusion is right. Score the claim and the evidence separately. Fold the claim on
  your own measurement; never copy its numbers or line references into a durable artifact.
- Its account of an action it performed is not evidence. If it says it wrote a benchmark file, list
  the directory.
- A proposed fix is a separate claim from the finding and can be wrong while the finding is right.
  Trace the fix's case matrix before adopting it, and expect the fix to spawn its own edge.
- Its facts about external tools, prices and tiers may be years stale. Ask for the date of the
  newest fact it relies on, and verify at the source.
- It argues to win under adversarial pressure. Separate its conclusion from its argument and check
  each.

## 4. Measure before folding

A finding is folded only when you have seen the thing it is about. The playbook in
`references/verification-playbook.md` covers the common cases; the principle is that a claim about
how something behaves is a claim about its text or its runtime, and both can be read:

- A licence: fetch the exact text (the SPDX license-list-data repository is a reliable mirror when a
  project's own site is broken) and quote the clause.
- A library or service: `npm view` for versions and licences, the raw repository for source, the
  provider's docs page for an integration claim.
- A storage layout: build it in a throwaway database at the target scale and run the real queries
  with `EXPLAIN (ANALYZE, BUFFERS)`. A design that reads well and a design that plans well are
  different designs; this is where the difference shows.
- A market or adoption claim: usually unmeasurable. Mark it `[CLAIM]`, fold the direction if it is
  plausible, never the number.

Timing numbers are single samples on a shared machine unless you controlled the machine; say so.

## 5. Present, and let the owner rule

After each consult, give the owner one message with: what the peer said, what you measured, where
the peer was wrong, your own read, and the question. Both recommendations are visible; where they
differ, say why you differ. End with the bracketed verdict token (`[VERDICT: ALIGNED]`,
`[VERDICT: REJECTED - reason]`, `[VERDICT: NEGOTIATE - reason]`, or, only after the owner waived a
consult, `[VERDICT: SKIPPED-UNREACHABLE]`). When you halted because the peer was unreachable, there
is no verdict yet: present the brief and the payload you would send, ask the owner to restore the
channel or waive, and say "awaiting the owner". The owner's answer is
recorded verbatim in the index and in the next brief's ledger. If the owner's ruling contradicts your
recommendation, say so once, then execute the ruling fully; a ruling is not an invitation to
re-argue in the next round.

When the owner asks for a "common agreed recommendation", run the agreement round in
`references/agreement-round.md`: your draft as numbered points, the peer answering AGREE (naming the
one thing it checked), AMEND (full replacement text) or DISSENT (reason and evidence) per point, plus
at least one point where both reviewers are wrong. "None" is not an acceptable answer to that last
question, because two reviewers who built the text together are the least likely to see its gap.

## 6. Artifacts and their review

Three artifacts, each committed on a design branch (never directly on the default branch), each
carrying its own review ledger and a stand-downs section inside the file (the paths below are defaults;
the project's own convention overrides them):

- **Design doc** (`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`): intent, adopter, goals,
  non-goals, anti-goals, constraints, approaches considered with what was picked and why, the
  decided mechanism, what is measured, what is left to the builder, what is left to the owner.
  Outline in `references/design-doc-outline.md`.
- **Implementation plan** (`docs/superpowers/plans/`): only against code that exists. With an empty
  repo, the first plan is scaffold plus spike plus the first package, and later plans wait for it
  to merge. Write it with the writing-plans skill, when available.
- **Roadmap** (`docs/superpowers/specs/YYYY-MM-DD-<topic>-roadmap-design.md`): releases in
  dependency order, each with who it is for, what ships, what must already be true, the measurement
  it produces, and the decision rule for the next release with thresholds the owner writes before
  the release ships. No dates unless the owner sets them.

Each artifact gets two reviews before the owner sees it. A **builder check**: a fresh subagent that
has seen none of the conversation reads the document as the person who must plan from it and
reports only the questions a wrong guess would make matter. And an **adversarial panel** through
the peer (`references/panel-brief.md`), in rounds, each round rotating in a seat the review has not
used, each later round carrying the folded ledger and auditing the previous round's folds, until a
round has no live challenge. Findings resolve to exactly one disposition: folded, rejected with the
measurement that killed it, discarded below the floor with the guard that makes it unreachable,
deferred to the anomalies file, or accepted unverified by the owner. Run the builder check and the
panel's first round in the same turn; they converge often and the overlap is itself evidence.

## 7. Supersession

Owner rulings arrive out of order. A later ruling can void an earlier decision (a licence ruling
can void an adopter decision; a business-model ruling can void a roadmap). When it does: mark the
earlier decision withdrawn in the artifact where it lives, revise every section that depended on
it, add a section that records the new ruling and its agreed execution, run the panel over the
revision only, and update the plan's tasks that change. Never leave two sections that disagree; a
builder resolves that by guessing.

## 8. The execution index

Keep one execution index per project, holding: every ruling with its date and wording, every commit
by sha, every consult by seam path and scratch path, every in-flight background task by id, and exactly
one resume point stating the next action. Update it when a unit of work lands, not in batch.

Where it lives: the harness's persistent memory directory when it has one (for example
`project_<name>_execution.md` under the auto-memory directory, with a one-line pointer in the memory
index file); otherwise one file per project at `.clavity/execution/<project>.md`, where `<project>` is
the repository directory's basename with every character outside `[A-Za-z0-9_-]` replaced by `-` (the
marker writer refuses any path containing two consecutive dots). If no letter or digit survives that
replacement, use `project`; if `.clavity/execution/<project>.md` already exists and its `Repo:` line names
a different path, append `-2`, `-3`, and so on until the name is free. Only one location is ever written.
Create the fallback through the marker writer, which asserts the `.clavity/` shield, and abort if it
exits non-zero:

```bash
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "execution/<project>.md"; then
  echo "peer-reviewed-design: ABORTING - could not prepare a shielded .clavity/ directory for execution/<project>.md." >&2
  exit 1
fi
```

A file with no memory pointer is loaded by nothing, so the first step of every session is to list
`.clavity/execution/` and the memory index and read any existing index before starting new work; with
more than one candidate, ask the owner which project is meant and never guess. Close a finished
project's index by writing `DONE` as its resume point. `.clavity/` is gitignored, so `git clean -fdx`
erases the fallback: commit shas are re-derivable from git, verbatim rulings are not, so also write each
ruling into the committed artifact's review ledger as it lands. Template in
`references/execution-index.md`. The test of the index: a cold successor can continue safely from it
alone.

## 9. What this skill does not do

It does not execute plans; hand off to the subagent-driven-development or executing-plans skill (when available) when the owner
says go. It does not replace a lawyer for licence text, an accountant for pricing, or a market for
adoption numbers; it names those as owner items and leaves them open. It does not decide for the
owner; the owner can rule against both reviewers, and the skill records the ruling and proceeds.

## References

`<BASE>` is this skill's own base directory, as the harness supplies it at invocation time (the "Base
directory for this skill:" line that heads the loaded text); it is not `${BASH_SOURCE[0]}`. Every
`references/<file>` named in this skill means `<BASE>/references/<file>`, and the marker writer lives at
`<BASE>/../../hooks/agy-mark.sh`.

- `references/fork-brief.md`: the fork brief template and the payload wording that keeps a peer
  review-only and complete.
- `references/panel-brief.md`: the adversarial panel payload, seat palette, dispositions, stop rules.
- `references/agreement-round.md`: the point-by-point sign-off that produces a jointly agreed text.
- `references/verification-playbook.md`: how to measure licence, library, storage and market claims.
- `references/design-doc-outline.md`: section list and the review-ledger and stand-downs conventions.
- `references/execution-index.md`: the memory file template.
