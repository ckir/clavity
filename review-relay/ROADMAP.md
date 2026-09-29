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

The fully automated design is archived, not abandoned. Neither document is in this repository; both
live in the owner's local working copy:
- the bridge: the AIBridgeWeb MVP specification, v0.13 (seven review rounds recorded in its revision
  delta);
- the clavity client on top of it: the web-seats design spec of 2026-09-28 (a local, uncommitted spec).

Resume when the manual paste is the bottleneck. review-relay's templates, read proof and ledger carry over.

## Tracked defects

### R1 - collect gives the wrong advice for an AiSaveDev capture whose scraper fell back

**Status:** promoted from the anomalies conveyor 2026-09-29, not yet planned.

When a site's layout drifts, AiSaveDev's scrapers fall back: `scrapeGeneric` saves the whole page as one
turn labelled "Conversation", and the OpenAI Playground scraper labels every turn "message". The file still
says `format: aisave-dev/1`, but it has no `role=human` / `role=assistant` marker, so `Read-AiSaveCapture`
drops to the H2 path (`Format=aisave`, empty reply). `collect` then warns, correctly, that the capture has
no reply - but for `Format=aisave` it adds "save it again with AiSaveDev instead"
(`scripts/collect.ps1:121`), which is wrong for a file AiSaveDev already saved.

MEASURED 2026-09-29 (AGY-CAPSTONE round 4 on the AiSaveDev shipping branch) with a jsdom-emitted
drifted-ChatGPT capture: parsed as `Format=aisave`, empty reply, `NO-VERDICT`. The failure is loud (a
warning plus a NO-VERDICT row) and no wrong reply is produced; only the diagnosis misleads.

A fix needs `Read-AiSaveCapture` to expose the DECLARED format as well as the path it used, so collect can
say "AiSaveDev could not find the turns on this page - the site may have changed".
