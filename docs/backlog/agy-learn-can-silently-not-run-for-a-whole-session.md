# Backlog stub - a capture discipline silently did not run for an entire session

**Status:** OPEN. Promoted 2026-08-27 from `.clavity/local-anomalies.md`.
**Raised:** 2026-08-25.

## The observation

The agy-LEARN capture discipline did not run for an ENTIRE session - roughly 13 review rounds that
produced at least EIGHT project-agnostic, measured facts about the peer: a format capability, an
unstable-accuracy failure mode, three driving heuristics, and two banner/anti-pattern results.

The SessionStart notice says to capture "the MOMENT you learn something GENERAL... do not batch, and do
not wait to be reminded." It was not obeyed, and **nothing detected that it had not been obeyed.**

## Why this is the dangerous shape

A discipline whose only enforcement is a reminder has no failure signal: a session in which it never
fires is indistinguishable from a session in which there was nothing to capture. The knowledge is lost at
compaction and the loss is invisible. Compare the marker-gated disciplines (agy-capstone,
agy-test-audit), which re-arm and nag until satisfied.
