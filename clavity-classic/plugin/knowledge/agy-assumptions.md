# agy ground truth - peer-truth assumptions, and how to re-verify them

**This drives a live, external, frequently-updated peer - Antigravity (`agy`).** Almost everything
load-bearing here was *empirically observed*, not promised by a stable API, and we have no reliable way
to detect which agy version is running. **Assume behavior is stable and re-verify empirically** rather
than trusting a version stamp - an agy update can silently change any of these.

This file is the kick-off for a future session: if agy misbehaves (or before you change anything
agy-facing), read this and re-verify the relevant assumption with the listed check. This manual is
**driver-agnostic** - it states what agy *does*, not how any particular driver (transport, CLI verbs,
env knobs) reaches it. A driver's own docs cover its transport mechanics.

> **Capability/routing profile:** for *what agy can do* and how to route work to it (strengths,
> weaknesses, models, operational reach), see [`agy-capabilities.md`](agy-capabilities.md). It
> cross-references the assumptions here; e.g. its operational-reach axis resolves the workspace-write
> question in the workspace-only-writes assumption below.

## Load-bearing assumptions

- **Headless invocation hangs with no TTY.** Invoking agy non-interactively, with no terminal attached,
  hangs rather than returning - this is why a driver needs a live interactive session (a pane/pty it
  can read and write) instead of shelling out headless. **Re-verify:** invoke agy with a non-TTY
  subprocess and see whether it now returns promptly instead of hanging; if it does, a headless
  direct-invoke path may have become viable.

- **agy's shell tool is PowerShell (pwsh), not bash** - even on setups where bash is otherwise the
  default. Any shell snippet handed to agy as an instruction must be pwsh-syntax, or it'll fail or
  behave unexpectedly. **Re-verify:** ask agy to run a pwsh-only construct and a bash-only construct in
  the same turn and observe which succeeds, or check agy's own logs for the shell it actually invoked.

- **agy reads its skill files once per session and caches their content.** A skill file edited mid-session
  is not picked up until agy is restarted - this is about skill *content* being cached, not the
  autocomplete/discovery listing (which may refresh independently, e.g. on a conversation switch or
  `--add-dir`, without re-reading the file's body). **Re-verify:** edit an installed skill's canned reply
  to a distinguishing marker, then invoke that skill on the already-running session *without* restarting
  - an unmarked (stale) reply confirms caching still holds; a marked reply means agy re-read it.

- **agy writes only within its own working directory (cwd)**; a write attempt outside it is rejected
  with an artifact-path error, and agy falls back to a shell-based write if one is available.
  **Re-verify:** ask agy to create a file outside its cwd and watch for the rejection (visible in agy's
  own logs).

- **agy auto-authenticates via the OS keyring.** A transient "not logged in" message at startup
  self-heals on its own, and a permission-skip flag auto-approves tool calls so the session runs
  unattended. **Re-verify:** check agy's own logs for a "authenticated via keyring" line, and confirm no
  interactive login prompt actually blocks progress.

## Driving-protocol assumptions

How the peer responds to *how the driver frames a payload*. Each is gated by a harness probe; treat any
of these as live only after a fresh harness PASS, not on the strength of a past verification.

- **A1 - Honors a loud REVIEW-ONLY banner.** A consult opened with an enumerated no-edit/no-commit
  banner returns a verdict and makes no edits.
- **A2 - Latency is BIMODAL / payload-bound, not a constant.** Focused, bounded asks (one question,
  artifact by filepath, scoped) return in a short window (roughly under two minutes) and a synchronous
  call does not time out. Only deep-generative mega-payloads - or asks fired while the peer is
  mid-turn - reach minute-scale; use an asynchronous request/poll pattern for those. A reply can still
  land *after* a synchronous wait gives up: recover it from wherever the asynchronous channel stores it.
- **A3 - Replies land on a NEW thread per request.** Never assume a reply lands in the same thread as
  the request that triggered it - correlate replies by a request id (or equivalent), not by thread.
- **A4 - Phase isolation respected.** A payload marked `[PHASE: EXPLORATION]` with propose-only framing
  produces a proposal only, no edits (the target tree stays clean).
- **A5 - Checkpoint-before-mutation obeyed.** A `[PHASE: EXECUTION]` mutating delegation that orders a
  recoverable checkpoint first results in the peer creating a branch/stash that predates the edit
  (reversible).

### Failure modes - driver anti-patterns (how NOT to prompt the peer)

- A review/consult sent **without** a loud, enumerated REVIEW-ONLY banner -> the peer **executes** the
  task instead of reviewing it. Always banner + forbidden-actions list + explicit "permission to pass."
- **Mixing exploration and execution** in one payload degrades the build (context fills with raw search
  output). One phase per payload.
- **Delegating a mutating task without ordering a pre-change checkpoint** risks unrecoverable edits.
- Asking the peer to **"find bugs"** open-endedly -> over-escalation/hallucination. Seed the specific
  invariants to confirm/refute and grant "no must-fix is valid" (it **verifies >> discovers**).
- When the driver's **GLOBAL/top-priority config** prescribes low-level transport primitives as the
  primary way to reach the peer, that OVERRIDES a higher-level one-front-door abstraction (instruction
  priority: user-config > skills) and reproduces the leak even with the abstraction installed -
  reconcile global config to defer to the front door.
- **Seeding a KNOWN defect** ("here is the bug - find more like this") -> over-application: it flags every
  superficially-similar construct **without checking the mechanism**, producing a false-positive flood
  that costs more to triage than the hunt saved. Ask for an open hunt without naming the class, or
  require a proof against the actual failing operation for each hit.

## Transient runtime gotchas (agy/backend behavior, not config)

These are **not** driver bugs - they're how the live agy / its model backend behave. Recognize them so
a stuck or wrong reply doesn't get mistaken for a driver failure.

- **Backend overload aborts the turn.** agy's model backend can return a high-traffic/overload error and
  **abort mid-turn**, returning agy to idle with **no reply at all** to whatever request triggered the
  turn - a wait-for-reply simply times out.
  - **Diagnose:** observe agy's own output/state directly - the overload message appears there, and agy
    is idle, not dead or crashed.
  - **Recover:** wait roughly a minute, then **re-send the request**, not just re-signal readiness. If
    agy had already consumed the original request before erroring, merely poking it again finds nothing
    - the request itself must be re-sent (with a fresh correlation id), not just re-announced.

- **agy reads files relative to its OWN working folder - even when given an absolute path.** When asked
  to review a file that lives in a *different* repo, agy may open its **cwd's** same-named copy instead
  of the one at the given absolute path (this shows up when a stale/sibling copy exists in agy's cwd).
  This produces false negatives ("you didn't edit X" / wrong line count) against the wrong file.
  **Fixes, best first:** run agy with cwd = the target repo; otherwise give **absolute paths** *and*
  make agy **prove it read the right file** (have it report the line count); or remove stale sibling
  copies. Always verify agy's file claims against disk.

## Deferred / known gaps

Not yet addressed - candidates if you're improving robustness: **a checkpoint mechanism that snapshots
via a working-tree stash misses untracked files**; **a scrollback/history capture that transfers the
full history each call** (rather than incrementally).
