# review-relay ROADMAP

## Open decisions

### D1 - Vendor APIs as review seats

**Status:** open (owner, 2026-09-28).

Web review seats currently go through consumer chat sites, by hand. Vendor APIs (OpenAI, Meta models via
a hosting provider, Google, and others) would give the same "different model family" benefit fully
automated, with no browser, no site changes to track, and no terms-of-service risk. The cost is metered:
a 20 KB review is roughly 5-10k tokens per seat, i.e. cents per seat per round, plus API keys to manage.
The owner preferred flat-rate subscriptions when the browser design was chosen; this entry keeps the
alternative on record so it is weighed with real usage numbers once review-relay has been used for a while.

### D2 - Resume full browser automation

**Status:** paused (owner, 2026-09-28).

The fully automated design is archived, not abandoned:
- the bridge: `AIBridgeWeb/AIBridgeWeb_MVP_Specification_v0.13.md` (owner's working folder; seven review
  rounds recorded in its revision delta);
- the clavity client on top of it: `docs/superpowers/specs/2026-09-28-web-seats-design.md`.

Resume when the manual paste is the bottleneck. review-relay's templates, read proof and ledger carry over.
