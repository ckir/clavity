# Productize release checklist

The productize epic (SP-0 → SP-D) is code-complete but has never shipped: the newest release tag
predates SP-D's commits. This checklist is its closing step.

## Contents the release must carry

- [ ] The four discipline skills in both plugins: `agy-first`, `agy-capstone`, `agy-after` (already
      shipped pre-epic), and the `agy-seam-inject` auto-fire hook.
- [ ] `agy-liveness-check.sh` including the D1 ownership check.
- [ ] The hook-ownership rule in both plugin READMEs.
- [ ] `docs/agy-capstone-ledger.md`.

## Before installing

- [ ] **Close all active Claude Code sessions.** The ownership notice is bound to SessionStart, so
      installing underneath a running session means it never fires while the newly-installed hooks are
      already executing — the double-fire then runs unannounced for the rest of that session.

## After installing

- [ ] Start a session. The ownership notice will name every personally-registered hook that the plugin
      now ships.
- [ ] **For each hook named, diff your copy against the shipped one before touching anything.** They are
      not guaranteed to be equivalent, and one of them is not. MEASURED at the time of writing:

      diff ~/.claude/hooks/agy-seam-inject.sh clavity-dotnet/plugin/hooks/agy-seam-inject.sh

      The personal `agy-seam-inject.sh` binds **five seams the shipped hook does not carry** —
      `writing-plans`, `requesting-code-review`, `systematic-debugging`, `subagent-driven-development`,
      `executing-plans`. Deleting its registration silently loses all five.
- [ ] **`agy-seam-inject.sh` specifically: rename, do not delete.** Rename to `agy-legacy-seams.sh`,
      delete its `*brainstorm*` and `*finishing-a-development-branch*` arms (the shipped hook covers
      both), register it under the new name, and keep the other five. Nothing checks this for you — the
      ownership check matches filenames, not behaviour, so a leftover duplicate arm will fire twice
      without being reported.
- [ ] **Know what moves even when you do this correctly.** The two hooks bind AGY-CAPSTONE to *different*
      seams: your personal copy fires it on `subagent-driven-development`/`executing-plans`, while the
      shipped hook fires it on `finishing-a-development-branch`. After retirement the capstone stops
      being nudged on the plan-execution seams. **This is a behaviour change, not a no-op.** The
      discipline itself is unaffected — the AGY-CAPSTONE rule binds whether or not a hook fires, which is
      exactly why the rule exists as a backstop — but the automatic prompt moves.
- [ ] For every OTHER named hook, apply the same order: **diff first, then decide.** If your copy is
      equivalent to the shipped one, remove the registration. If it does more, rename-and-trim as above.
      Do not assume equivalence because the filename matches — that assumption is what makes the loss
      silent. **The installer does not do any of this** — those files are yours, and an installer editing
      them silently is the surprise this design removes.
- [ ] Restart or `/clear` the session so the window closes at a known point.
- [ ] Start a session again and confirm the notice is gone.

## Not in this release

- The clavity-classic ME1 binary-native-vs-bash fork — tracked debt, does not gate (owner ruling).
- Productizing `agy-test-audit` and `AGY-SCOPE` — a follow-on epic; this release closes at four
  disciplines.
