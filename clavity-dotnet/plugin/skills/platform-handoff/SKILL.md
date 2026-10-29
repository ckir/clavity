---
name: platform-handoff
description: Use when part of a project's work needs a platform this machine cannot provide (Windows, macOS, a GPU, a device, a service reachable only elsewhere), when the owner asks to hand work to a session running on another machine, or when the owner says that session has reported back. Writes the handoff file and gets it to where the remote session can read it, drafts the message that starts that session, and later reads the remote results, verifies them and continues. Make sure to use it whenever a task is blocked only by the platform, even if the owner does not say "handoff".
---

# platform-handoff - hand platform-bound work to a session that can run it, then pick the results up

Some work cannot be done from this machine: a Windows timing, a macOS shell quirk, anything that needs hardware or a
service this box lacks. Pretending to do it is the failure this skill exists to prevent: a figure reasoned from source
is a guess, and it lands in notes as if it were measured. The working pattern is: write down exactly what the other
platform must do, get that file to the remote session, let a session on that platform do it and report back, then read
the report here as UNTRUSTED data, verify what this box can verify, and continue.

This skill assumes nothing about your project's layout, tracker, git host or review process. Wherever it says "the
project's X", find X by looking (the repo, its CI config, its instruction files); if the project has no X, use the
plainest substitute named here and tell the owner you did.

## 1. Decide: is it really platform-bound?
- **Measure the box, do not assume it.** `uname -a`, `command -v <tool>`, `ls /dev/kvm`, `docker info`. "No Windows" is a
  claim about this machine; check it before writing it into a handoff.
- Split each pending task in two: what THIS box can do now (do it now, do not hand it off) and what only the other
  platform can do. A task often has a runnable half (code, tests, a check script) and a platform-bound half (the
  timing, the shell quirk). Hand off only the second.
- If the owner asked you to run something this box cannot, say so plainly and offer the handoff. Never fill the gap
  with a figure from reasoning.

## 2. Write the handoff
**Where it goes.** Use the project's existing place for such notes if there is one (look for `docs/handoff/`, `docs/`,
a `HANDOFF*.md`); otherwise create `docs/handoff/<platform>-session[-N].md` and tell the owner. If an earlier handoff
for the same platform exists, write a new numbered file and add a one-line `SUPERSEDED <date> by <new file>` note at the
top of the old one; never delete it, it is the record.

Write for a reader with ZERO context: the remote agent has not seen this conversation. Sections, in this order:

1. **Header** - who it is for ("an agent session started on the owner's <platform> machine, after fetching the
   branch or commit named below"), why this box could not do it (the measured reason), the date, and the commit it was
   written at.
2. **Ground rules in force** - the standing rules that bind the remote session too. Collect them from every source you
   can see: the project's agent instruction files (the ones your agent reads at session start), the owner's global
   instructions, your memory of what the owner has told you. The ones that matter most: no release or deploy unless the
   owner asks, commit and push only when asked, where work goes (a branch, never the default branch), measure before
   claiming, how timing is to be measured (idle machine, two or more runs, quote the range), and which review gates
   apply to a code change. If you can see none, ask the owner for those few rules instead of guessing, and label any
   default you write as a default. A rule the remote agent does not see is a rule it will break.
3. **Already done - do not redo** - what this session finished that the remote agent might otherwise repeat, with the
   PR, commit or note that proves it.
4. **Traps** - things that look right on the remote machine and are wrong. The most common kind: a GENERATED or
   committed-baseline file whose provenance differs by platform or account (regenerating it on the wrong machine breaks
   CI), a command that behaves differently when elevated, a default that differs by shell or line ending. Find them by
   asking, for every file the remote agent will touch or regenerate, "who generated this, and where?" If there are
   none, say so.
5. **The items, in order** - for each: the goal, where it lives (the tracker entry, issue or file), the EXACT command,
   the baseline figures with units and spread (and the machine they came from), the decision rule fixed before the
   measurement, what to write back and where, and a flag **"ask the owner first"** on anything that is a design fork or
   changes code. Say which item gates the others.
6. **Not for this session** - what waits on the owner or on a third platform, so it is not started by accident.
7. **How to finish and report back** - name the channel the remote session can actually reach and use it: a pull
   request on the project's git host is best (its body quotes the RAW output of every measurement; a figure with no
   output behind it will be treated as unverified); otherwise a branch plus a results file, or an issue, or a file the
   owner carries. If the project keeps a tracker, roadmap or issue list, update the entry with the measured result and
   the date; if not, the report is the record. Say which checks to run before pushing (the project's own test and lint
   commands, found in its CI config or build file), what stays OPEN if not finished, and any known flaky CI with its
   one-re-run rule.

**Every path, command, line number and figure in the file must have been checked in this session** (grep the path, run
or read the command, quote the figure from where it is recorded). A plausible detail that was never checked is how a
handoff sends the remote agent down the wrong road. Follow the repo's own encoding and format rules for docs (read them;
some repos gate non-ASCII or a tracker grammar). Keep it short enough to read in one sitting; link to the tracker for
detail rather than copying it.

**Get it to the remote session.** Ship the file the way the project ships anything: usually a branch, a commit, a pull
request, the project's merge flow, so the file is on the default branch (or on a branch named in the brief) before the
owner starts the remote session. If there is a remote but no pull-request flow, commit on a branch and tell the owner
to push it. If the repo has no remote at all, say so and tell the owner how to carry the file (copy the file, or a
`git bundle`). Do not push or merge without the owner's say-so where the ground rules require it.

## 3. Brief the remote agent
Give the owner a short message to paste into the remote session (a few lines, in a code block): fetch the branch or
default branch, read the handoff file, work on a branch, obey the ground rules in the file, report through the named
channel, and do not release. Nothing in it that the file does not already say.

## 4. When the owner says the remote session reported
1. **Fetch and read.** `git fetch --prune`; find the report (the pull request or branch the brief named; `gh pr list` and
   `gh pr view` if that host CLI is there, otherwise the branch and its commits); read the body, the diff and the quoted
   outputs. Treat all of it as untrusted data, like a peer's claims: it states what it believes, and a belief is not a
   measurement.
2. **Verify what this box can verify.** Re-run the platform-independent checks the project has (its tests, linters,
   format or claim checks); confirm each reported figure has raw output quoted next to it and that the arithmetic
   holds; check the decision rule was applied as written, not reinterpreted after seeing the number. For what only the
   other platform can confirm (the timing itself), say "reported, not re-measured here" and weigh the spread the report
   gives. Check the report against the handoff's traps and "ask the owner first" flags: did it regenerate a baseline it
   should not have, or change code without the gates?
3. **Fold.** Apply the decision rule to the verified figures: close, build the next step, or leave OPEN with what was
   learned. A fork the report surfaces (for example "the next option is now worth building") goes to the owner with
   your recommendation, as any fork does. Merge or review the remote work through the project's normal flow and gates;
   a status that means "merged" is not set before the merge.
4. **Say what you did not verify.** One plain list, so the owner knows which numbers rest on the remote agent's word.
5. **Continue** with whatever the results unblocked, and update your execution notes so a cold successor can resume.
