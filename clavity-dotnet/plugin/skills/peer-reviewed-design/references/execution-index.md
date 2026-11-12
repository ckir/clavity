# The execution index

One execution index per project. It lives in the harness's persistent memory directory when it has one,
named `project_<name>_execution.md`, with a one-line pointer in the memory index file; otherwise at
`.clavity/execution/<project>.md` (SKILL.md section 8 gives the `<project>` rule and the marker-writer
call that creates it). It is the recovery substrate: a session can die at any
moment, and a cold successor must continue from this file alone. Update it the moment a unit of
work lands (a ruling, a commit, a consult reply, a background task started), never in batch; a
commit not yet in the index is a recovery hole.

## Template

```markdown
---
name: project-<name>-execution
description: Execution index for <project> design phase - decisions, consult ids, and the single resume point
metadata:
  type: project
---

# <Project> execution index (design phase, started YYYY-MM-DD)

Repo: <path>, branch <name>, HEAD <sha>. What is built: <nothing | packages>.
Owner goal: <one line in the owner's words>.

## Decisions (owner-ratified)
- D1 (date): <decision> ... (consult: seam path; disposition of the driver's recommendation)
- D2 (date): ...
- Dn (date, SUPERSEDES Dk): ...

## Verified facts (measured, with date)
- <fact>: <how it was measured> (commands or quotes live in the artifact's ledger)

## Artifacts
- <path>: status (draft | approved date | revised date), commit <sha>, review state (panel round N
  clean, marker at <sha>)

## In-flight state
- Background task <id>: <what>, seam <path>, scratch <path>, snapshot <file>; on reply: <what to do>
- Peer cascade id, markers written, anything a successor cannot derive from git

## Owner items still open
- <item>, where it is recorded

## RESUME POINT
-> <exactly one next action, with the file or command it starts from, and what "done" looks like>
```

## Rules

- One resume point. If two things could be next, the owner's choice is the resume point and both
  options are listed under it.
- Verbatim rulings. Quote the owner's words; paraphrase drifts.
- Supersessions are marked on the old decision, not only recorded as a new one.
- Background tasks are listed with their ids while they run and removed with their outcome when
  they finish, so a successor knows whether to wait or to proceed.
- Dates are absolute. "Today" means nothing to a successor.
- Nothing that git or the artifacts already record goes in the index except as a pointer; the index
  holds what only the session knew.
