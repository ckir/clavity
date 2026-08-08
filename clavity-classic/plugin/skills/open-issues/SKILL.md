---
name: open-issues
description: Use when an agent notices a defect, tool misbehavior, or operational blocker that is NOT the task at hand, and when triaging the anomalies already captured. Capture is one appended line; triage promotes each entry to a tracked item or deletes it with a reason.
---

# open-issues - capture an anomaly now, triage it later

An agent doing task X notices something wrong that is NOT task X. Historically the only channel was prose
in a reply, and prose scrolls away. This skill gives that observation somewhere durable to land, and a
procedure for emptying it.

## The bar - what to capture

> Capture any reachable code defect; or any tool misbehavior or operational blocker that actively
> degrades or prevents the agent/owner workflow.

That bar is deliberate on both edges. It is wide enough to catch things that are not code bugs at all -
a tool that truncates the reply you asked for, a test gate that outgrew its timeout - because those
silently tax every future session. It is narrow enough to exclude opinion: "this file is getting large",
"I would have named this differently", "this could be more elegant" are NOT anomalies. If you cannot say
what it degrades or prevents, do not capture it.

**Do not judge severity.** There is no severity field. An agent in the middle of a task has an obvious
incentive to rate its own interruption as unimportant, and the owner has to make the call at triage
anyway. Write the fact and move on.

## Who writes - the driver, after verifying

**A subagent REPORTS; the driver VERIFIES; the driver WRITES.** Owner ruling, and it overrides an earlier
converged design in which the spotter wrote to the file directly.

The reasoning is worth keeping visible, because the earlier design was not silly - it was solving a real
failure and traded away something more valuable to do it:

- Anomalies were being lost at SUMMARIZATION. A subagent reported one, the driver compressed a long report
  into a short answer, and the observation evaporated. Letting the spotter write directly closed that.
- But it closed it by removing the only step that ever checks anything. A subagent's report is a CLAIM, not
  evidence. Measured repeatedly in practice: a claimed anomaly turned out to be real and got fixed; a
  confidently-argued one turned out to be false and was refuted by measurement. Direct writes would have
  put both in the file, indistinguishable, with nobody looking.
- So the loss is not fixed by bypassing the driver. It is fixed by requiring the driver to CAPTURE BEFORE
  SUMMARIZING. That keeps the verification step and still closes the hole, because the hole was
  summarizing without capturing.

**If you are a subagent:** report anomalies in your final message under a heading of their own, so they
survive being skimmed. Do not write to the anomalies file. Do not judge severity. Do not stop your task
for it.

**If you are the driver receiving that report:** for each claimed anomaly, verify it by measurement before
recording anything - open the file, run the command, reproduce the behaviour. Then:

- **verified** -> capture it with the snippet below, BEFORE you write your summary to the user;
- **refuted** -> do not capture it, and say plainly in your summary that you checked and it did not hold;
- **cannot be checked cheaply** -> capture it with the fact stated as a claim (`reported, unverified:`)
  rather than dropping it, and let triage decide.

Capturing is not optional once something is verified. A verified anomaly that only appears in a chat
message is exactly the failure this whole mechanism exists to end.

Run this, filling the four fields:

```bash
# Resolve the REPOSITORY ROOT, never a relative path. Whoever runs this may be cd'd into a subdirectory,
# and a relative path would write scripts/.clavity/local-anomalies.md, which the SessionStart hook never
# looks at: durably recorded and permanently invisible, the exact opposite of the point. The hook resolves
# the root the same way, so both sides always agree.
R=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
F="$R/.clavity/local-anomalies.md"
mkdir -p "$R/.clavity"
# Self-ignoring directory. This makes .clavity/ invisible to git REGARDLESS of the host repository's own
# .gitignore, which matters because this plugin ships to repositories whose .gitignore we do not control.
# Without it, the "capture is private" property holds only in the repo where it was written.
#
# CHECKED ON EVERY CAPTURE, deliberately NOT nested inside the file-exists branch below. If it only ran
# when creating the file for the first time, then any later loss of the .gitignore -- someone deletes it,
# `git clean -Xdf` removes it, the file was created by hand -- would leave the anomalies file visible to
# git forever after, and the next `git add .` would publish a list of un-triaged defects. Re-asserting the
# shield costs one stat per capture.
[ -f "$R/.clavity/.gitignore" ] || printf '%s\n' '*' >> "$R/.clavity/.gitignore"
# The header uses >> and NEVER >. MEASURED: with >, two writers that both see no file destroy each other's
# work -- the first writes the header and appends its anomaly, the second's > truncates the file before
# appending its own, and the first anomaly is gone. Under the report-then-verify flow the concurrent
# writers are no longer subagents but two SESSIONS open on the same repository, which is ordinary. A
# mechanism whose entire purpose is not losing things must not have a path that silently eats one. With >>
# the worst case is a duplicate header, cosmetic and uncounted by the entry pattern; both survive.
[ -f "$F" ] || printf '%s\n\n' '# Untriaged anomalies (local, never committed)' >> "$F"
printf -- '- [%s] %s * %s * %s * task=%s\n' \
  'defect' 'one line stating the fact' 'path/file.ext:LINE' "$(date +%F)" 'what you were doing' >> "$F"
```

**Use exactly one of `defect`, `tool`, `process` as the type, lowercase, one word.** Not `[Defect]`, not
`[tool misbehavior]`. The hook tolerates other bracketed tokens when counting, but the three types are
what the triage procedure sorts on, so an invented type makes the entry harder to act on.

**Keep the four ` * ` separators.** The hook reads the capture date from the field before `task=`, by
position. An entry missing a separator still counts, but its age cannot be read.

Two things about that snippet are deliberate:

- **The `.clavity/.gitignore` containing `*` is load-bearing, not tidiness.** The decision to keep capture
  private rests on the directory being ignored. In this repository that happens to be true anyway; in a
  user's repository it is true only because of this file.
- **Append with `>>` and a single `printf`.** Two sessions can be open on the same repository at once. A
  single short append is atomic on POSIX, so concurrent writers interleave lines rather than corrupting
  them. Do not read-modify-write the file to add an entry.

- **type**: `defect` (reachable code defect) | `tool` (a tool or peer misbehaving) | `process` (an agent
  or workflow doing the wrong thing)
- **fact**: one line, specific enough to act on later. "discovery regex is brittle" is useless in a week;
  "ParseLatest never checks the HTTP line's pid matches the gRPC line's" is actionable.
- **where**: `file:line` if it has one, `n/a` if it does not.
- **task**: what you were actually doing. This is what lets the owner judge whether it was a distraction
  or a blocker.

The file is gitignored on purpose. An agent appending raw, un-triaged findings to a public repository can
publish sensitive local paths or exploitable detail before anyone reviews them. Triage is what makes an
entry public, by promoting it.

## Dispatching a subagent - the clause every dispatch must carry

A subagent reports nothing useful unless its dispatch asks for it. It will not invoke this skill on its
own: it is focused on the task you gave it, and an anomaly is by definition not that task. So the
instruction has to travel IN the dispatch. Paste this into every implementer dispatch, in its
report-back section:

> **ANOMALIES.** If you notice something wrong that is NOT part of this task - a defect in adjacent code,
> a tool misbehaving, a process that cannot work - report it under a heading `## Anomalies noticed` at
> the END of your final message, one line each, in this shape:
>
> `- [defect|tool|process] one line stating the fact * path/file.ext:LINE or n/a * what you were doing`
>
> State it as a FACT you observed, with whatever makes it checkable - the command you ran, the file and
> line, the output you saw. Do NOT judge severity, do NOT stop your task to investigate, and do NOT write
> to any anomalies file yourself: your report is the channel, and whoever dispatched you will verify each
> one by measurement before recording it. If you noticed nothing, write `## Anomalies noticed` followed by
> `none` - an explicit none is worth more than silence, because silence is indistinguishable from not
> having looked.

> **FILES.** This dispatch may create or modify ONLY the files listed here:
> `<list every path the subagent is permitted to touch>`. Touching anything else - including a file that
> seems obviously related, a test you think should be updated, or a doc you think is now stale - is out of
> bounds. If the task cannot be completed within that list, STOP and report
> `SCOPE: needs <path> because <reason>` rather than widening it yourself.

**The driver verifies this, and that half is the one that historically failed.** After the subagent
returns, compare the actual change set against the list you gave it. A subagent once wrote to a file
outside its named set, and nothing detected it except the driver happening to look. Naming the list
without checking it afterwards is theatre: the list is a statement of intent, and the diff is the only
evidence.

**`git status --short` alone is NOT that diff.** Most implementer subagents COMMIT their work, and a
committed write leaves the working tree clean. MEASURED: after a subagent commits a file outside its list,
`git status --short` prints nothing at all while `git show --stat HEAD` names the file. Record the SHA
before you dispatch, and check BOTH axes afterwards:

```bash
git status --short                 # uncommitted writes
git log --stat <sha-before>..HEAD  # committed writes - the axis a clean status hides
```

Neither axis sees a write outside the worktree (`~/.claude/`, a gitignored path, `.git/` itself). If the
dispatch could touch one of those, name it in the list and check it directly.

**Why a heading and not a sentence in the prose.** A report gets skimmed. A dedicated heading with a
fixed shape survives skimming, and it makes an omission visible: a report with no such section is a
report that did not answer the question.

**The driver's obligation is the other half, and it is the half that historically failed.** Verify each
reported anomaly by measurement, then capture the verified ones with the snippet above BEFORE writing
your summary. The summary is where these die. Capturing after summarizing is capturing never.

## Triage - the only two outcomes

A SessionStart hook names the count and the oldest entry until the file is empty. To clear it, take each
entry and do exactly one of:

1. **PROMOTE** it to a tracked item with an owner and a slot - a `ROADMAP.md` entry, or a plan, or an
   immediate fix if it is cheap enough to just do. Then delete the line. **Which `ROADMAP.md`:** this is a
   monorepo and several exist. Promote into the ROADMAP of the product that OWNS the defective file. For
   shared or root-level code (`scripts/`, root `docs/`, CI workflows), use `clavity-dotnet/ROADMAP.md`,
   which already carries the cross-cutting sections.
2. **DELETE** it with a recorded reason - it was wrong, it was already fixed, it does not meet the bar,
   or it is a duplicate. Say which, in the commit message or to the owner.

**There is no third outcome. Nothing may sit "acknowledged" or "noted".** A parked state is how a list of
surfaced-but-untracked findings forms in the first place, which is the failure this skill exists to end.
An entry that is real but not worth doing now is PROMOTED as tracked debt, not left in the file.

Severity is assigned here, at triage, by the owner - not at capture by the agent that was interrupted.

## Scope boundary

This skill is the CAPTURE half. What happens to a defect once tracked - that a defect's age is never a
disposition, that a verified pre-existing defect earns a planned fix rather than a mention - is the
disposition half, and belongs to AGY-SCOPE.
