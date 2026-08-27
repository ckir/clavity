# Backlog stub - `fatal: .git/index: index file smaller than expected` during test runs

**Status:** OPEN, cause UNPROVEN. Promoted 2026-08-27 from `.clavity/local-anomalies.md`.
**Raised:** observed FOUR times across capstone rounds.

## The observation

A test run emits `fatal: .git/index: index file smaller than expected` twice to stderr while every suite
still passes.

**The first recorded cause was WRONG and is retracted.** It was attributed to a subagent arm running git
concurrently; it then recurred with NO subagent running at all. The better-supported cause - still not
proven - is the drain suites (`abort-drain`, `accept-drain`, `drain-*`) creating and manipulating
temporary repositories.

## Why it is worth tracking despite passing suites

The suites pass, so nothing gates on it, which is exactly the shape of a defect that is discovered later
at a worse moment. A corrupted index read during a gate that DOES depend on git state would fail in a way
nobody would connect to this. **A retracted cause is recorded here deliberately** - the first explanation
was confident and wrong, and re-attributing it without evidence is how it would become folklore.
