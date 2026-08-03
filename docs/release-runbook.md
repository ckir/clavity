# Release runbook

The operational wrapper around `just release`. It does not replace
[`productize-release-checklist.md`](productize-release-checklist.md) — that checklist owns what a
release must *carry* and the post-install hook migration; this runbook owns the *order of operations*
and the traps.

> **Every number here was measured on a specific day and drifts.** Re-measure rather than quoting.
> Where a step says "expect ~N", treat it as an order of magnitude, not a gate.

---

## Preconditions — clear these before you start

**1. The working tree must be completely clean.** `scripts/release.ps1:14-15` runs `git diff --quiet`
and `git diff --cached --quiet` and dies on *any* unstaged or staged tracked change. A
work-in-progress file you have been deliberately carrying uncommitted will stop the release at step 3,
before it does anything. Commit it or `git stash push -- <path>` for the duration.

**2. You must be on `main`** (`:13`) with tags fetched (`:12`).

**3. There must be no unpushed `chore(release):` commit** (`:18`), and the last release prep must have
a remote tag (`:29-30`) unless its serial is listed as abandoned in the script.

---

## Trap: never run `just release` inside an agent tool call

Its pre-flight (`:101-108`) runs, in order: `check-roster.ps1`, **`just test-scripts`** (the *whole*
Pester suite, not the fast half), `just lint`, `just test`, then `check-versions.ps1` twice per bumped
member. On 2026-08-02 the Pester suite alone measured **162 fast + 231 slow = 393 tests, ~916s**. The
whole pre-flight runs on the order of twenty minutes.

That is past the 600s agent tool cap, and the failure is not benign:

```
release.ps1:95   git commit -F $msgFile      <-- chore(release): clavity-vN is made HERE
release.ps1:101  ...pre-flight gates...      <-- and only validated HERE
release.ps1:18   Die "unpushed chore(release)..."   <-- which then blocks the retry
```

A timeout or any pre-flight failure leaves a `chore(release)` commit sitting unpushed, and the next
run refuses to proceed while it exists. **Run it from your own terminal** (`! just release`), or
background it. If you do get stranded, drop that commit before retrying.

A long silence during `just test-scripts` is expected. It is not a hang.

So is this line, which the suite prints to the console mid-run:

```
fatal: .git/index: index file smaller than expected
```

It is **not** your repo. It is real `git` stderr from inside a **scratch** repo that the accept-drain
F34 test corrupts on purpose to prove the guard fails closed. It surfaces between two passing results,
immediately before `[+] hard-fails (exit 1) and RETAINS staging when 'git status' fails (corrupt index;
F34 fail-closed)` — so the line is the evidence the guard works. It appears on every full-suite run.
If you want to confirm your own index is fine, stat it rather than running git (`ls -la .git/index` —
a healthy one is tens of KB); do not run git against the repo while the suite is running.

---

## Phase 0 — scope decisions

- [ ] **Is AGY-TEST-AUDIT due?** Its reminder hook gates on `.clavity/agy-marks/agy-capstone.head`
      equalling `HEAD` plus changed executable code. If it is armed, decide deliberately: run it
      before the release, or defer it. Running it after means any coverage gap it finds has already
      shipped.
- [ ] Resolve any deliberately-uncommitted working files (precondition 1).
- [ ] Confirm the productize checklist's "contents" list still matches what this release actually
      carries. Plugin payloads ship by recursive wildcard, so **new files reach users whether or not
      anyone updated a list** — see the note at the end of this file.

## Phase 1 — pre-push safety

The push is the irreversible step, and this is a public repository.

- [ ] **Leak-check.** `docs/superpowers/*` (`.gitignore:32`) and `.clavity/` (`.gitignore:45`) are
      ignored precisely because they hold local planning and runtime state. Both of these must return
      empty:
      ```
      git ls-files docs/superpowers .clavity
      git log --oneline origin/main..HEAD -- docs/superpowers .clavity
      ```
      A `git add -f` earlier in the branch's life is exactly what this catches.
- [ ] **`just release-dry`.** The `-WhatIf` preview: computes the serial, the per-member bumps and the
      CHANGELOG, and writes nothing. Always run this first and read the output.
- [ ] **Read the non-conventional-commit warning.** `scripts/lib/release-lib.ps1:190` accepts only
      `feat|fix|chore|ci|docs|refactor|test|perf|build|style|revert`. Anything else is listed as
      non-conventional, never raises the bump level (`:197`), and gets no CHANGELOG entry. The change
      still ships — only its provenance is lost. Decide per commit whether that matters; rewriting
      history to recover a changelog line is usually the worse trade.

## Phase 2 — release

- [ ] `! just release`

It commits `chore(release): clavity-vN`, runs the pre-flight above, then pushes the commit and only
then the tag (`:110`, deliberate ordering). SSH keepalives are set in-script (`:113`) because git
opens the connection *before* the pre-push hook runs and holds it idle for the hook's duration.

Push failures are classified, not blindly retried: rejection signatures are fatal, and only transport
signatures retry. That is deliberate — a retry must never turn a real refusal into a silent second
attempt that appears to succeed.

## Phase 3 — install

- [ ] **Close every active Claude Code session first**, including the one you are reading this in. The
      ownership notice binds to `SessionStart`; installing underneath a live session means it never
      fires while the newly-installed hooks are already executing.
- [ ] Then follow [`productize-release-checklist.md`](productize-release-checklist.md) "After
      installing" in full. The sharp edge is real: a personally-registered hook may bind seams the
      shipped one does not, so **diff before you delete, and rename rather than remove.**

## Phase 4 — verify

- [ ] Start a session; the ownership notice names every personally-registered hook the plugin now
      ships.
- [ ] Diff each named hook against its shipped counterpart before touching anything.
- [ ] Restart or `/clear`, start again, confirm the notice is gone.

---

## A standing note on "not in this release"

Both plugin installers ship their payload by **recursive wildcard**, not by an enumerated file list:

- `clavity-dotnet/installer/clavity-dotnet.iss:40` — `Source: "..\plugin\*"`
- `agy-autotrain/installer/agy-autotrain.iss:53` — `Source: "..\*"`, excluding only
  `installer,dist,publish,agy-observations.md`

**A skill or hook that exists in the plugin directory therefore ships, whether or not its epic was
declared closed and whether or not any checklist mentions it.** "Not in this release" is a statement
about scope and support, never about what lands on a user's disk. When you want something genuinely
excluded, exclude it in the `.iss` — a line in a checklist will not do it.
